#!/usr/bin/env python3
##########################################
#########  final run: the launcher for Linux (the HPC)
#########  keeps R sessions busy with the tasks of the task table until all
#########  are done; the counterpart of launch.ps1 (own design; Python 3.6
#########  or later, standard library only)
##########################################

## from the project root, as the last command of a PBS job (hpc_job.sh):
##   python3 analysis/06_final-run/launch.py --slots 48
## A job that ends (walltime, qdel) is submitted again to resume: finished
## runs and tasks are never repeated.
##
## It follows THE CONTRACT at the top of launch.ps1 (the task table, done,
## the sessions and their environment, the shared runs, which task a free
## slot gets, failures, the smoke test, Python); the R side is the same on
## both computers. What differs on Linux:
##
##  4. A session is the Rscript of the PATH (module load app/R/... before
##     the launcher; --rscript names another one), in a process group of
##     its own.
##  8. The results are not committed and pushed: a cluster keeps no GitHub
##     credential. They stay under RUN_ROOT and are copied from the laptop
##     (scp or rsync, see hpc_job.sh).
## 10. The Python environment of the fits is built by setup_hpc.sh in
##     ../Masters-Research-R-python/env beside the project; every session
##     gets RETICULATE_PYTHON = its bin/python (--python names another
##     one, --python uv lets every session resolve its packages with uv).
## 11. One launcher for a RUN_ROOT: <RUN_ROOT>/final-run/launcher.pid holds
##     process id, start time, computer and PBS job of the launcher, which
##     touches the file every 30 s while it lives. A launcher that finds a
##     file that is still touched ends with exit code 2; a file left by a
##     job that was killed is taken over (after up to 150 s of looking if
##     it is of another node). The sessions an earlier launcher left on
##     this node are stopped, then every lock directory and .tmp file
##     under RUN_ROOT is removed.
##     SIGTERM (qdel, the walltime), SIGINT and SIGHUP stop the sessions
##     and end the launcher: it must be the top process of the job (exec).
##
## parameters
##   --slots          R sessions at once (default: NCPUS of the PBS job,
##                    else the processors of the computer)
##   --run-root       RUN_ROOT of the sessions (default:
##                    ../Masters-Research-R-results/results beside the
##                    project)
##   --profile        "" the final run (default), "quick" only the quick
##                    profile
##   --skip-smoke     no smoke test before the final run
##   --parts          the parts of the task table this computer runs, for
##                    a run on two computers: names joined by "+", as
##                    --parts nncl_grid+nncl_search (the names and what a
##                    part brings with it: the top of "final run tasks.R";
##                    default: all). The smoke test is then of these parts
##                    (marker smoke.<parts>.done)
##   --rounds         times the final run goes over the task table while
##                    tasks fail (default 2)
##   --rscript        Rscript to use instead of the one of the PATH
##   --python         python of the Python environment of the fits, or "uv"
##   --quiet-hours    a session without output and without a new run file
##                    for so long is named in the progress line (default 6)
##   for tests:
##   --tasks-file     an existing task table, used instead of a generated
##                    one (then there is no smoke test)
##   --tasks-script   the R script that writes the task table
##   --poll-seconds, --summary-minutes, --retry-seconds, --beat-seconds
##                    the waiting times below
##
## exit code: 0 every task done; 1 tasks failed or blocked, or the smoke
## test failed; 2 another launcher is running; 3 the launcher itself failed
## or was stopped

import argparse
import csv
import os
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time

MAX_FAILS = 3                  # failures in a row that fail a task
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
WINDOWS = os.name == "nt"      # the tests of the launcher run there too
HOST = socket.gethostname()
COLUMNS = ["id", "stage", "dataset", "unit", "profile", "validation",
           "final_fit", "script", "args", "kind", "sessions", "max_runs",
           "n_runs", "run_dir", "pattern", "needs"]


class Stop(BaseException):
    """a signal asked the launcher to end"""


class Record(object):
    """a task, a session or the state of the launcher: named fields"""

    def __init__(self, **fields):
        self.__dict__.update(fields)


## the state of the launcher: the options, the folders, the tasks of the
## table that is run and the running sessions (slot -> session)
run = Record(opt=None, root="", run_root="", run_root_r="", state="",
             log_file="", pid_file="", last_beat=0.0, rscript="",
             python_variables={}, retry_waits=[], parts=[], tasks=[],
             sessions={})

##########################################
#########  functions
##########################################


def stamp(seconds=None):
    """a time as text, for the logs"""
    return time.strftime(TIME_FORMAT, time.localtime(seconds))


def write_log(text):
    """one line with the time to the output and to the launch log; a log
    that cannot be written at this moment must not stop the launcher"""
    line = stamp() + "  " + text
    try:
        print(line, flush=True)
    except (OSError, ValueError):
        pass
    try:
        with open(run.log_file, "a") as log:
            log.write(line + "\n")
    except OSError:
        pass


def get_size(file):
    """the size of a file in bytes, -1 if it cannot be read"""
    try:
        return os.path.getsize(file)
    except OSError:
        return -1


def file_time(file):
    """when a file was last written or touched, None if it is not there"""
    try:
        return os.stat(file).st_mtime
    except OSError:
        return None


def tail(file, lines):
    """the last lines of a text file"""
    try:
        with open(file, "r", errors="replace") as text:
            return text.read().splitlines()[-lines:]
    except OSError:
        return []


def beat():
    """touches launcher.pid every --beat-seconds: the sign of life another
    launcher looks for (11.)"""
    now = time.time()
    if now - run.last_beat >= run.opt.beat_seconds:
        run.last_beat = now
        try:
            os.utime(run.pid_file, None)
        except OSError:
            pass


def nap(seconds):
    """waits, with the signs of life"""
    end = time.time() + seconds
    while True:
        beat()
        left = end - time.time()
        if left <= 0:
            return
        time.sleep(min(left, 5))


def start_logged(command, log, folder, variables):
    """starts a program that appends its output and messages to a log file,
    in a process group of its own; variables: environment variables to set
    (a text) or to remove (""). Returns the process"""
    env = dict(os.environ)
    for name, value in variables.items():
        if value == "":
            env.pop(name, None)
        else:
            env[name] = value
    more = {}
    if WINDOWS:
        more["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        more["preexec_fn"] = os.setpgrp
    with open(log, "ab") as out:
        return subprocess.Popen(command,
                                stdin=subprocess.DEVNULL,
                                stdout=out,
                                stderr=subprocess.STDOUT,
                                cwd=folder,
                                env=env,
                                **more)


def signal_tree(process_id, hard):
    """asks a process and the processes it started to end (hard: at once)"""
    try:
        if WINDOWS:
            subprocess.call(["taskkill", "/PID", str(process_id), "/T", "/F"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
        else:
            os.killpg(process_id, signal.SIGKILL if hard else signal.SIGTERM)
    except OSError:
        pass


def stop_all(processes):
    """stops processes of start_logged and the processes they started: all
    are asked to end, those still there after 5 s are killed. A PBS job
    that is deleted has about 10 s for this"""
    for process in processes:
        if process.poll() is None:
            signal_tree(process.pid, False)
    end = time.time() + 5
    while time.time() < end:
        if all(p.poll() is not None for p in processes):
            break
        time.sleep(0.2)
    for process in processes:
        # also the processes a session left behind in its group
        if not WINDOWS or process.poll() is None:
            signal_tree(process.pid, True)
    for process in processes:
        try:
            process.wait(5)
        except subprocess.TimeoutExpired:
            pass


def wait_logged(process, seconds):
    """waits for a process of start_logged; one still running after the
    limit is stopped. Returns its exit code, -1 after the limit"""
    end = time.time() + seconds
    while process.poll() is None:
        if time.time() >= end:
            stop_all([process])
            return -1
        nap(1)
    return process.returncode


def exit_text(code):
    """the exit code of a session as text; a negative one is the signal
    that ended it"""
    if code >= 0:
        return "exit code {}".format(code)
    try:
        name = signal.Signals(-code).name
    except ValueError:
        name = "signal {}".format(-code)
    text = "ended by {}".format(name)
    if name == "SIGILL":
        text += " (illegal instruction: TensorFlow needs a processor with AVX)"
    if name == "SIGKILL":
        text += " (killed: out of memory, or stopped from outside)"
    return text


def get_folders(top):
    """the folders under a folder, itself included; a lock directory is
    listed but not read, .git is left out, and a folder that disappears
    while it is read (the lock of a running session) is passed over"""
    found = []
    stack = [top]
    while stack:
        folder = stack.pop()
        if os.path.basename(folder) == ".git":
            continue
        found.append(folder)
        if folder.endswith(".lock"):
            continue
        try:
            with os.scandir(folder) as entries:
                for entry in entries:
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(entry.path)
        except OSError:
            pass
    return found


def remove_locks(top, slot, pattern):
    """removes lock directories of claim_run() under a folder: those of one
    slot (the file slot_<k> in them; slot 0: of any slot) and of the run
    files that match a pattern (None: any). A directory that holds anything
    but slot files is not a lock of ours and stays"""
    if not os.path.isdir(top):
        return
    for folder in get_folders(top):
        if not folder.endswith(".lock"):
            continue
        run_file = os.path.basename(folder)[:-5]
        if pattern is not None and not pattern.search(run_file):
            continue
        try:
            inside = os.listdir(folder)
            other = [f for f in inside if not f.startswith("slot_")]
            mine = slot == 0 or "slot_{}".format(slot) in inside
            if not other and mine:
                shutil.rmtree(folder)
                write_log("unlock  " + folder)
        except OSError:
            pass


def update_count(task, log_done):
    """counts the run files and the lock directories of a queue task
    (contract 3. and 6.; locks_live: those held by a session of the task
    that is running); a new run file sets the failures of the task back to
    0, and with all run files the task is done"""
    folder = os.path.join(run.run_root, task.run_dir)
    own_slots = [k for k, s in run.sessions.items() if s.task is task]
    files = 0
    locks = 0
    locks_live = 0
    try:
        if os.path.isdir(folder):
            for name in os.listdir(folder):
                if name.endswith(".lock"):
                    if not task.regex.search(name[:-5]):
                        continue
                    if not os.path.isdir(os.path.join(folder, name)):
                        continue
                    locks += 1
                    if any(os.path.exists(os.path.join(folder, name,
                                                       "slot_{}".format(k)))
                           for k in own_slots):
                        locks_live += 1
                elif (task.regex.search(name) and
                      not name.endswith((".tmp", ".partial"))):
                    files += 1
    except OSError:
        return                 # folder not readable now: keep the last count
    if files > task.files:
        task.fails = 0
    task.files = files
    task.locks = locks
    task.locks_live = locks_live
    if files > task.n_runs and not task.warned:
        # more run files than the task table says the task has (contract 2.)
        task.warned = True
        write_log("WARNING {}: {} run files match its pattern, n_runs is {}"
                  .format(task.id, files, task.n_runs))
    if files >= task.n_runs and not task.done:
        task.done = True
        if log_done:
            write_log("done    " + task.id)
        if task.failed:
            # the sessions still running finished a task given up before
            task.failed = False
            marker = os.path.join(run.state, "failed", task.id + ".failed")
            try:
                os.remove(marker)
            except OSError:
                pass


def write_sessions():
    """the running sessions to <state>/sessions.csv: "final run status.R"
    reads it, and a later launcher stops them from this file"""
    lines = ["slot,id,pid,started,log"]
    for slot in sorted(run.sessions):
        s = run.sessions[slot]
        lines.append('{},{},{},{},"{}"'.format(slot, s.task.id, s.process.pid,
                                               stamp(s.started), s.log))
    try:
        with open(os.path.join(run.state, "sessions.csv"), "w") as out:
            out.write("\n".join(lines) + "\n")
    except OSError:
        pass


def is_session(process_id):
    """TRUE if the process is an R session started for this RUN_ROOT (the
    system uses a process id again, so the id alone could be another
    program); on a system without /proc: FALSE"""
    try:
        with open("/proc/{}/environ".format(process_id), "rb") as text:
            variables = text.read().split(b"\0")
    except OSError:
        return False
    root = ("RUN_ROOT=" + run.run_root_r).encode()
    return (root in variables and
            any(v.startswith(b"RUN_SLOT=") for v in variables))


def stop_sessions(state_folder):
    """stops the sessions listed in the sessions.csv of a state folder that
    still run on this computer (left by a launcher that was killed). The
    sessions of a PBS job that has ended are gone with it"""
    file = os.path.join(state_folder, "sessions.csv")
    if not os.path.exists(file):
        return
    try:
        with open(file, "r", newline="") as text:
            lines = list(csv.DictReader(text))
    except (OSError, csv.Error) as error:
        lines = []
        write_log("sessions.csv not readable, left aside: {}".format(error))
    for line in lines:
        process_id = str(line.get("pid", ""))
        if not process_id.isdigit() or not is_session(process_id):
            continue
        signal_tree(int(process_id), False)
        time.sleep(2)
        signal_tree(int(process_id), True)
        time.sleep(1)
        if is_session(process_id):
            raise RuntimeError(
                "An R session of an earlier launcher is still running and "
                "could not be stopped (process {} of {}). Stop it (kill -9 "
                "{}), then start the launcher again. Nothing was started "
                "and no lock was removed.".format(process_id, file,
                                                  process_id))
        write_log("stopped the session of an earlier launcher: {} slot {} "
                  "pid {}".format(line.get("id"), line.get("slot"),
                                  process_id))
    os.remove(file)


def write_summary():
    """the state of the tasks in one line, with the sessions that have been
    quiet for long (contract 7.: a session that hangs would keep its slot
    for ever; it is named, not stopped)"""
    tasks = run.tasks
    queues = [t for t in tasks if t.kind == "queue"]
    running = {}
    for s in run.sessions.values():
        running[s.task.id] = running.get(s.task.id, 0) + 1
    line = ("progress tasks {} of {} done, {} failed, {} blocked; runs {} of "
            "{}; sessions {} of {}: {}".format(
                sum(t.done for t in tasks),
                len(tasks),
                sum(t.failed for t in tasks),
                sum(t.blocked for t in tasks),
                sum(min(t.files, t.n_runs) for t in queues),
                sum(t.n_runs for t in queues),
                len(run.sessions),
                run.opt.slots,
                ", ".join("{} x{}".format(k, running[k])
                          for k in sorted(running))))
    quiet = []
    now = time.time()
    for slot in sorted(run.sessions):
        s = run.sessions[slot]
        size = get_size(s.log)
        if size != s.sign_size or s.task.files != s.sign_files:
            s.sign = now
            s.sign_size = size
            s.sign_files = s.task.files
        elif now - s.sign >= run.opt.quiet_hours * 3600:
            quiet.append("{} slot {} pid {}".format(s.task.id, slot,
                                                    s.process.pid))
    if quiet:
        line += ("; quiet for {} h (no output, no new run file): {}"
                 .format(run.opt.quiet_hours, ", ".join(quiet)))
    write_log(line)


def read_tasks(file, run_profile):
    """reads and checks the task table; the rows in (stage, row) order with
    the fields the loop keeps for each task"""
    with open(file, "r", newline="", encoding="utf-8-sig") as text:
        reader = csv.DictReader(text)
        present = reader.fieldnames or []
        lines = list(reader)
    if not lines:
        raise RuntimeError("the task table {} has no rows".format(file))
    missing = [c for c in COLUMNS if c not in present]
    if missing:
        raise RuntimeError("the task table {} lacks the columns {}"
                           .format(file, ", ".join(missing)))

    def field(line, name):
        # NA is R's missing value
        value = (line.get(name) or "").strip()
        return "" if value == "NA" else value

    tasks = []
    wrong = []
    for row, line in enumerate(lines, start=1):
        task = Record(
            row=row,
            id=field(line, "id"),
            stage=0,
            dataset=field(line, "dataset"),
            unit=field(line, "unit"),
            profile=field(line, "profile"),
            validation=field(line, "validation"),
            final_fit=field(line, "final_fit"),
            script=field(line, "script"),
            args=field(line, "args"),
            kind=field(line, "kind"),
            sessions=1,
            max_runs=field(line, "max_runs"),
            n_runs=0,
            run_dir=field(line, "run_dir"),
            pattern=field(line, "pattern"),
            regex=None,
            needs=[n.strip() for n in field(line, "needs").split(";")
                   if n.strip() != ""],
            # kept by the loop
            done=False,
            failed=False,
            blocked=False,
            blocked_by="",
            fails=0,
            last_fail=0.0,
            retry_after=0.0,
            files=0,
            locks=0,
            locks_live=0,
            warned=False)
        try:
            task.stage = int(field(line, "stage"))
        except ValueError:
            wrong.append("row {}: the stage is not a whole number"
                         .format(row))
        if not re.match(r"^[A-Za-z0-9._-]+$", task.id):
            wrong.append("row {}: the id '{}' is not a file name"
                         .format(row, task.id))
        script_file = task.script
        if not os.path.isabs(script_file):
            script_file = os.path.join(run.root, script_file)
        if task.script == "" or not os.path.isfile(script_file):
            # Linux tells upper from lower case in file names
            wrong.append("row {}: no script '{}'".format(row, task.script))
        if task.kind == "queue":
            try:
                task.sessions = int(field(line, "sessions"))
                task.n_runs = int(field(line, "n_runs"))
            except ValueError:
                task.sessions = 0
            if (task.sessions < 1 or task.n_runs < 1 or
                    task.run_dir == "" or task.pattern == ""):
                wrong.append("row {}: a queue task needs sessions, n_runs, "
                             "run_dir and pattern".format(row))
            try:
                task.regex = re.compile(task.pattern)
            except re.error:
                task.regex = re.compile("$^")
                wrong.append("row {}: the pattern '{}' is not a regular "
                             "expression".format(row, task.pattern))
            if re.search(r"\[:[a-z]+:\]", task.pattern):
                wrong.append("row {}: the pattern '{}' has a POSIX class of "
                             "R; write [0-9], [a-z] (contract 2.)"
                             .format(row, task.pattern))
        elif task.kind != "single":
            wrong.append("row {}: kind '{}' is not single or queue"
                         .format(row, task.kind))
        tasks.append(task)
    ids = [t.id for t in tasks]
    if len(set(ids)) != len(ids):
        wrong.append("the ids are not unique")
    for task in tasks:
        for need in task.needs:
            if need not in ids:
                wrong.append("task {} needs the unknown task {}"
                             .format(task.id, need))
    if wrong:
        raise RuntimeError("the task table {} is wrong:\n  {}"
                           .format(file, "\n  ".join(wrong)))
    # a quick run leaves out the rows of a profile that is not a quick one
    # and, one after the other, the rows that need them (contract 2.)
    if run_profile != "":
        out = [t.id for t in tasks
               if t.profile != "" and not t.profile.startswith(run_profile)]
        more = True
        while more:
            more = False
            for task in tasks:
                if task.id not in out and any(n in out for n in task.needs):
                    out.append(task.id)
                    more = True
        if out:
            write_log("left out of the {} run (another profile): {}"
                      .format(run_profile, ", ".join(out)))
            tasks = [t for t in tasks if t.id not in out]
    return sorted(tasks, key=lambda t: (t.stage, t.row))


def session_ended(slot, s, code, done_folder, failed_folder):
    """a session that ended: its task is done, goes on, or has a failure
    (contract 7.)"""
    t = s.task
    seconds = int(time.time() - s.started)
    reason = ""
    if t.kind == "single":
        write_log("end     {} slot {}: {}, {} s"
                  .format(t.id, slot, exit_text(code), seconds))
        if code == 0:
            t.done = True
            t.fails = 0
            with open(os.path.join(done_folder, t.id + ".done"), "w") as out:
                out.write("{}, {} s\n".format(stamp(), seconds))
            write_log("done    " + t.id)
        else:
            reason = exit_text(code)
    else:
        files_before = t.files
        update_count(t, False)
        write_log("end     {} slot {}: {}, {} s; run files {} of {}"
                  .format(t.id, slot, exit_text(code), seconds, t.files,
                          t.n_runs))
        if t.done and files_before < t.n_runs:
            write_log("done    " + t.id)
        if code != 0:
            reason = exit_text(code)
        elif t.files <= s.files and not t.done:
            reason = "ended without a new run file"
    if reason == "":
        return
    if code != 0 and get_size(s.log) <= s.log_size:
        reason += ", nothing reached its log (Rscript not started?)"

    ## a failure: the locks of the slot go; it counts if the session was
    ## started after the last counted failure
    lock_folder = run.run_root
    if t.run_dir != "":
        lock_folder = os.path.join(run.run_root, t.run_dir)
    remove_locks(lock_folder, slot, None)
    if s.started <= t.last_fail:
        write_log("failure {} slot {}: {} (started before the last failure: "
                  "not counted)".format(t.id, slot, reason))
        return
    t.fails += 1
    t.last_fail = time.time()
    if t.fails < MAX_FAILS:
        wait = run.retry_waits[min(t.fails, len(run.retry_waits)) - 1]
        t.retry_after = time.time() + wait
        write_log("failure {} slot {}: {} (failure {} of {}; next try after "
                  "{} s)".format(t.id, slot, reason, t.fails, MAX_FAILS,
                                 wait))
        return
    if t.done:
        return
    t.failed = True
    marker = os.path.join(failed_folder, t.id + ".failed")
    text = ["task {} failed {} times in a row: {}".format(t.id, MAX_FAILS,
                                                          reason),
            "time: " + stamp(),
            "the last lines of {}:".format(s.log),
            ""] + tail(s.log, 30)
    with open(marker, "w") as out:
        out.write("\n".join(text) + "\n")
    write_log("FAILED  {}: {}, {} times in a row; see {}"
              .format(t.id, reason, MAX_FAILS, marker))


def next_task(tasks, by_id):
    """the task a free slot gets (contract 6.), None if there is none now"""
    now = time.time()
    for t in tasks:
        if t.done or t.failed or t.blocked or t.retry_after > now:
            continue
        if any(not by_id[n].done for n in t.needs):
            continue
        running = sum(s.task is t for s in run.sessions.values())
        if t.kind == "single":
            if running == 0:
                return t
            continue
        if running >= t.sessions:
            continue
        update_count(t, True)
        if t.done:
            continue
        if running == 0 and t.locks > 0:
            # no session of the task is running: its locks are left-overs
            remove_locks(os.path.join(run.run_root, t.run_dir), 0, t.regex)
            update_count(t, True)
        # the runs still to be saved, without those under a lock that no
        # running session holds: one session each at the most
        to_save = t.n_runs - t.files - (t.locks - t.locks_live)
        if running < min(t.sessions, to_save):
            return t
    return None


def start_session(slot, t, run_profile, logs):
    """a session of a task in a slot (contract 4.)"""
    log = os.path.join(logs, "{}_slot{}.log".format(t.id, slot))
    try:
        with open(log, "a") as out:
            out.write("==== {} start {} slot {}\n".format(stamp(), t.id,
                                                          slot))
    except OSError:
        pass
    log_size = get_size(log)
    variables = {
        "DATASET": t.dataset,
        "UNIT": t.unit,
        "R_CONFIG_ACTIVE": t.profile if t.profile != "" else run_profile,
        "VALIDATION": t.validation,
        "FINAL_FIT": t.final_fit,
        "RUN_ROOT": run.run_root_r,
        "RUN_SLOT": str(slot),
        "RUN_MAX": t.max_runs if t.kind == "queue" else "",
        "RUN_WORKERS": str(run.opt.slots),
        "RUN_DIR": "",
        "OMP_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
        "OPENBLAS_NUM_THREADS": "1",
        "TF_NUM_INTRAOP_THREADS": "1",
        "TF_NUM_INTEROP_THREADS": "1",
        "TF_CPP_MIN_LOG_LEVEL": "2",
    }
    variables.update(run.python_variables)
    command = [run.rscript, t.script] + shlex.split(t.args)
    process = start_logged(command, log, run.root, variables)
    started = time.time()
    run.sessions[slot] = Record(task=t,
                                process=process,
                                started=started,
                                files=t.files,
                                log=log,
                                log_size=log_size,
                                # the last sign of life (write_summary)
                                sign=started,
                                sign_size=log_size,
                                sign_files=t.files)
    write_sessions()
    write_log("start   {} slot {} pid {}".format(t.id, slot, process.pid))


def invoke_run(name, run_profile, state_folder, given_table):
    """one run of the task table: under a profile ("" or "quick"), in its
    state folder; given_table: a table to use instead of a generated one.
    Leaves the tasks in run.tasks"""
    opt = run.opt
    run.state = state_folder
    run.tasks = []
    run.sessions = {}
    logs = os.path.join(state_folder, "logs")
    done_folder = os.path.join(state_folder, "done")
    failed_folder = os.path.join(state_folder, "failed")
    for folder in [state_folder, logs, done_folder, failed_folder]:
        os.makedirs(folder, exist_ok=True)
    run.log_file = os.path.join(state_folder, "launch.log")
    write_log("==== {}: {} slots, RUN_ROOT {}, parts {}".format(
        name, opt.slots, run.run_root, "+".join(run.parts) or "all"))

    ## a task given up by an earlier launch is tried again
    for marker in os.listdir(failed_folder):
        if marker.endswith(".failed"):
            os.remove(os.path.join(failed_folder, marker))

    ## the task table: the given one, or written now by the tasks script
    table = os.path.join(state_folder, "tasks.csv")
    if given_table != "":
        if os.path.abspath(given_table) != os.path.abspath(table):
            shutil.copyfile(given_table, table)
    else:
        script_file = opt.tasks_script
        if not os.path.isabs(script_file):
            script_file = os.path.join(run.root, script_file)
        if not os.path.isfile(script_file):
            raise RuntimeError("the script that writes the task table is "
                               "not there: " + script_file)
        if os.path.exists(table):
            os.remove(table)
        variables = {"RUN_ROOT": run.run_root_r,
                     "R_CONFIG_ACTIVE": run_profile,
                     "FINAL_RUN_PARTS": "+".join(run.parts),
                     "DATASET": "", "UNIT": "", "VALIDATION": "",
                     "FINAL_FIT": "", "RUN_SLOT": "", "RUN_MAX": "",
                     "RUN_DIR": ""}
        table_log = os.path.join(logs, "tasks_table.log")
        process = start_logged([run.rscript, opt.tasks_script], table_log,
                               run.root, variables)
        code = wait_logged(process, 3600)
        if code != 0 or not os.path.exists(table):
            raise RuntimeError(
                "the task table was not written: Rscript \"{}\" ended with "
                "exit code {}; the end of {} :\n{}"
                .format(opt.tasks_script, code, table_log,
                        "\n".join(tail(table_log, 30))))
    tasks = read_tasks(table, run_profile)
    run.tasks = tasks
    by_id = dict((t.id, t) for t in tasks)
    stages = sorted(set(t.stage for t in tasks))

    ## what is done already: markers of the single tasks, run files of the
    ## queue tasks
    for t in tasks:
        if t.kind == "single":
            t.done = os.path.exists(os.path.join(done_folder, t.id + ".done"))
        else:
            update_count(t, False)
    stages_done = set(k for k in stages
                      if all(t.done for t in tasks if t.stage == k))
    write_summary()

    errors = 0
    next_summary = time.time() + opt.summary_minutes * 60
    while True:
        try:
            ## sessions that ended
            for slot in sorted(run.sessions):
                s = run.sessions[slot]
                code = s.process.poll()
                if code is None:
                    continue
                del run.sessions[slot]
                write_sessions()
                session_ended(slot, s, code, done_folder, failed_folder)

            ## the run files of the queue tasks with running sessions
            for t in set(s.task for s in run.sessions.values()):
                if t.kind == "queue":
                    update_count(t, True)
            ## blocked: a task that needs a failed or a blocked task
            before = [t.id for t in tasks if t.blocked]
            for t in tasks:
                t.blocked = False
            more = True
            while more:
                more = False
                for t in tasks:
                    if t.done or t.failed or t.blocked:
                        continue
                    for need in t.needs:
                        n = by_id[need]
                        if not n.done and (n.failed or n.blocked):
                            t.blocked = True
                            t.blocked_by = need
                            more = True
            for t in tasks:
                if t.blocked and t.id not in before:
                    write_log("blocked {}: it needs {}".format(t.id,
                                                               t.blocked_by))

            ## sessions for the free slots
            for slot in range(1, opt.slots + 1):
                if slot in run.sessions:
                    continue
                t = next_task(tasks, by_id)
                if t is None:
                    break
                start_session(slot, t, run_profile, logs)

            ## stages, the end, the summary
            for k in stages:
                if k not in stages_done and all(t.done for t in tasks
                                                if t.stage == k):
                    stages_done.add(k)
                    write_log("stage   {} complete".format(k))
            if not run.sessions:
                left = [t for t in tasks
                        if not t.done and not t.failed and not t.blocked]
                if not left:
                    break
                if not any(t.retry_after > time.time() for t in left):
                    # nothing runs, nothing waits for another try, nothing
                    # can start: the needs of these tasks cannot be met
                    for t in left:
                        t.blocked = True
                        t.blocked_by = ";".join(t.needs)
                        write_log("blocked {}: it cannot start, needs {}"
                                  .format(t.id, t.blocked_by))
                    break
            if time.time() >= next_summary:
                write_summary()
                next_summary = time.time() + opt.summary_minutes * 60
            errors = 0
        except Exception as error:
            # an error in one round (a file that cannot be read now, say)
            # must not end the run; the same trouble 20 rounds in a row does
            errors += 1
            write_log("ERROR   in the launcher, line {}: {}".format(
                sys.exc_info()[2].tb_lineno, error))
            if errors >= 20:
                raise
        nap(opt.poll_seconds)
    write_sessions()
    write_summary()


def get_not_done():
    """the tasks of the last invoke_run that are not done, with the reason,
    as lines of text"""
    lines = []
    for t in run.tasks:
        if t.done:
            continue
        if t.failed:
            marker = os.path.join(run.state, "failed", t.id + ".failed")
            lines.append("failed:  {}  ({})".format(t.id, marker))
        else:
            lines.append("blocked: {}  (it needs {})".format(t.id,
                                                             t.blocked_by))
    return lines


def other_launcher():
    """TRUE if another launcher holds this RUN_ROOT (11.)"""
    first = file_time(run.pid_file)
    if first is None:
        return False
    try:
        with open(run.pid_file, "r") as text:
            fields = text.readline().strip().split(",")
    except OSError:
        fields = []
    process_id = fields[0] if fields else ""
    host = fields[2] if len(fields) > 2 else ""
    if host == HOST and os.path.isdir("/proc") and process_id.isdigit():
        # of this computer: is that launcher still there?
        try:
            with open("/proc/{}/cmdline".format(process_id), "rb") as text:
                return (b"launch.py" in text.read() and
                        int(process_id) != os.getpid())
        except OSError:
            return False
    # of another computer: a launcher that lives touches the file. The age
    # of the file by the clock of the file server, not by this computer's
    probe = run.pid_file + ".probe"
    try:
        with open(probe, "w") as out:
            out.write("")
        now = file_time(probe)
        os.remove(probe)
    except OSError:
        now = None
    if now is not None and now - first > 10 * run.opt.beat_seconds:
        return False
    print("launcher.pid of {} is {} s old: looking for up to {} s whether "
          "that launcher lives".format(
              host or "another launcher",
              "?" if now is None else int(now - first),
              5 * run.opt.beat_seconds), flush=True)
    end = time.time() + 5 * run.opt.beat_seconds
    while time.time() < end:
        time.sleep(min(5, run.opt.beat_seconds))
        latest = file_time(run.pid_file)
        if latest is None:
            return False
        if latest != first:
            return True
    return False


def computer():
    """processor, its flags and the memory of this computer (Linux)"""
    processor = "unknown"
    flags = []
    memory = "unknown"
    try:
        with open("/proc/cpuinfo", "r") as text:
            for line in text:
                if line.startswith("model name") and processor == "unknown":
                    processor = line.split(":", 1)[1].strip()
                if line.startswith("flags") and not flags:
                    flags = line.split(":", 1)[1].split()
        with open("/proc/meminfo", "r") as text:
            for line in text:
                if line.startswith("MemTotal"):
                    memory = str(round(int(line.split()[1]) / 1024 ** 2))
    except (OSError, ValueError, IndexError):
        pass
    return processor, flags, memory


def read_options():
    """the parameters of the launcher (the top of this file)"""
    slots = os.environ.get("NCPUS", "")
    slots = int(slots) if slots.isdigit() else (os.cpu_count() or 1)
    p = argparse.ArgumentParser(description="final run: the launcher")
    p.add_argument("--slots", type=int, default=slots)
    p.add_argument("--run-root", default="")
    p.add_argument("--profile", default="", choices=["", "quick"])
    p.add_argument("--skip-smoke", action="store_true")
    p.add_argument("--parts", default="")
    p.add_argument("--rounds", type=int, default=2)
    p.add_argument("--rscript", default="")
    p.add_argument("--python", default="")
    p.add_argument("--quiet-hours", type=float, default=6)
    p.add_argument("--tasks-file", default="")
    p.add_argument("--tasks-script",
                   default="analysis/06_final-run/final run tasks.R")
    p.add_argument("--poll-seconds", type=float, default=5)
    p.add_argument("--summary-minutes", type=float, default=5)
    p.add_argument("--retry-seconds", default="60,600")
    p.add_argument("--beat-seconds", type=float, default=30)
    return p.parse_args()


##########################################
#########  the launch
##########################################


def launch():
    """R, Python, the left-overs of an earlier launcher, the smoke test and
    the run; returns the exit code"""
    opt = run.opt
    state_final = os.path.join(run.run_root, "final-run")
    state_quick = os.path.join(state_final, "quick")
    write_log("==== launcher started, process {} on {}".format(os.getpid(),
                                                              HOST))

    ## R: the Rscript of the PATH (module load app/R/...)
    run.rscript = opt.rscript or shutil.which("Rscript") or ""
    if run.rscript == "" or shutil.which(run.rscript) is None:
        raise RuntimeError("Rscript not found: load the R module before the "
                           "launcher (module load app/R/4.5.1) or give "
                           "--rscript <path of Rscript>.")
    try:
        r_version = subprocess.check_output(
            [run.rscript, "-e", "cat(R.version.string)"],
            stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            universal_newlines=True).strip()
    except (OSError, subprocess.CalledProcessError):
        r_version = "unknown"

    ## the Python of the sessions (10.): the environment that setup_hpc.sh
    ## built, named to reticulate in every session
    python_exe = opt.python
    run.python_variables = {}
    if python_exe != "uv":
        if python_exe == "":
            python_exe = os.path.join(
                run.root, "..", "Masters-Research-R-python", "env",
                "Scripts" if WINDOWS else "bin",
                "python.exe" if WINDOWS else "python")
        # the path as it is, not what its links point to: the program of
        # an environment is a link to the Python it rests on
        python_exe = os.path.abspath(python_exe)
        if not os.path.isfile(python_exe):
            raise RuntimeError(
                "The Python environment of the fits is not there: {}. Run "
                "setup_hpc.sh first (it builds it), or give --python <path "
                "of its python>. --python uv lets every R session resolve "
                "its Python packages with uv instead (that needs the "
                "internet at every session start).".format(python_exe))
        run.python_variables = {
            "RETICULATE_PYTHON": python_exe,
            "RETICULATE_USE_MANAGED_VENV": "no",
            "RETICULATE_CHECK_REQUIRED_PACKAGES": "false",
            "KERAS_PYTHON": "",
        }

    ## R reads the file .Renviron of the project root (if there is none: of
    ## the home folder) at the start of every session and lets it win over
    ## the variables the launcher sets or removes (contract 4.): it must
    ## not name one of them
    session_names = (["DATASET", "UNIT", "R_CONFIG_ACTIVE", "VALIDATION",
                      "FINAL_FIT", "RUN_ROOT", "RUN_SLOT", "RUN_MAX",
                      "RUN_WORKERS", "RUN_DIR", "OMP_NUM_THREADS",
                      "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
                      "TF_NUM_INTRAOP_THREADS", "TF_NUM_INTEROP_THREADS",
                      "TF_CPP_MIN_LOG_LEVEL"] +
                     list(run.python_variables))
    for file in [os.path.join(run.root, ".Renviron"),
                 os.path.join(os.path.expanduser("~"), ".Renviron")]:
        if not os.path.isfile(file):
            continue
        with open(file, "r", errors="replace") as text:
            names = [line.split("=")[0].strip() for line in text
                     if "=" in line]
        names = [n for n in names if n in session_names]
        if names:
            raise RuntimeError(
                "The file {} sets {}: R reads it at the start of every "
                "session and would use its values instead of those of the "
                "launcher. Take these lines out of the file and start the "
                "launcher again.".format(file, ", ".join(names)))
        break                  # R reads the first of the two only

    ## the code commit, for run_info.txt
    code_commit = "unknown"
    if shutil.which("git") is not None:
        try:
            code_commit = subprocess.check_output(
                ["git", "-C", run.root, "rev-parse", "--short", "HEAD"],
                stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                universal_newlines=True).strip() or "unknown"
            changes = subprocess.check_output(
                ["git", "-C", run.root, "status", "--porcelain"],
                stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                universal_newlines=True).strip()
            if changes != "":
                code_commit += " with uncommitted changes"
        except (OSError, subprocess.CalledProcessError):
            pass

    ## left-overs of an earlier launcher: its sessions that still run on
    ## this computer are stopped, then no session is running and every lock
    ## directory and temporary file under RUN_ROOT is a left-over
    stop_sessions(state_final)
    stop_sessions(state_quick)
    remove_locks(run.run_root, 0, None)
    for folder in get_folders(run.run_root):
        if folder.endswith(".lock"):
            continue
        try:
            for name in os.listdir(folder):
                file = os.path.join(folder, name)
                if name.endswith(".tmp") and os.path.isfile(file):
                    os.remove(file)
                    write_log("removed " + file)
        except OSError as error:
            write_log("could not clear {}: {}".format(folder, error))

    ## this launch
    processor, flags, memory = computer()
    text = ["launch: " + stamp(),
            "computer: " + HOST,
            "PBS job: " + os.environ.get("PBS_JOBID", ""),
            "processor: " + processor,
            "logical processors: {}".format(os.cpu_count()),
            "memory (GB): " + memory,
            "R: " + r_version,
            "Rscript: " + run.rscript,
            "Python: " + python_exe,
            "code commit: " + code_commit,
            "slots: {}".format(opt.slots),
            "profile: '{}', skip smoke: {}, tasks file: '{}'".format(
                opt.profile, opt.skip_smoke, opt.tasks_file),
            "parts: " + ("+".join(run.parts) or "all"),
            ""]
    with open(os.path.join(state_final, "run_info.txt"), "a") as out:
        out.write("\n".join(text) + "\n")
    write_log("R: {}; Python: {}; code commit: {}".format(r_version,
                                                          python_exe,
                                                          code_commit))
    if flags and "avx" not in flags:
        write_log("WARNING the processor of this node ({}) has no AVX: "
                  "TensorFlow will end with an illegal instruction. Ask "
                  "for another node.".format(processor))

    ## the smoke test (contract 9.); of some parts (--parts) it has a
    ## marker of its own, and the marker of the whole table stands for it
    smoke_all = os.path.join(state_quick, "smoke.done")
    smoke_done = smoke_all
    if run.parts:
        smoke_done = os.path.join(
            state_quick, "smoke.{}.done".format("-".join(run.parts)))
    smoke_failed = os.path.join(state_quick, "smoke_failed.txt")
    if (not opt.skip_smoke and opt.profile == "" and opt.tasks_file == "" and
            not os.path.exists(smoke_done) and not os.path.exists(smoke_all)):
        write_log("smoke test: every task under the quick profile first")
        problem = ""
        try:
            invoke_run("smoke test", "quick", state_quick, "")
        except Exception as error:
            problem = str(error)
        not_done = get_not_done()
        run.log_file = os.path.join(state_final, "launch.log")
        if problem == "" and not not_done:
            with open(smoke_done, "w") as out:
                out.write("{}, code commit {}\n".format(stamp(), code_commit))
            if os.path.exists(smoke_failed):
                os.remove(smoke_failed)
            write_log("smoke test passed")
        else:
            text = ["The smoke test (quick profile) failed; the final run "
                    "was not started.",
                    "time: {}, code commit: {}".format(stamp(), code_commit),
                    ""]
            if problem != "":
                text += [problem, ""]
            text += not_done
            for t in run.tasks:
                if t.failed:
                    marker = os.path.join(state_quick, "failed",
                                          t.id + ".failed")
                    text += ["", "-" * 45] + tail(marker, 200)
            os.makedirs(state_quick, exist_ok=True)
            with open(smoke_failed, "w") as out:
                out.write("\n".join(text) + "\n")
            write_log("SMOKE TEST FAILED: see " + smoke_failed)
            for line in not_done:
                write_log(line)
            if problem != "":
                write_log(problem)
            print("\nThe smoke test failed: the final run was NOT started.")
            print("Summary: " + smoke_failed)
            print("Logs:    " + os.path.join(state_quick, "logs"), flush=True)
            return 1

    ## the run: when all is done, failed or blocked, the failed tasks get
    ## another round (contract 7.): a cause that has passed by then (no
    ## memory left) costs no more than the wait
    turn = 1
    while True:
        if opt.profile == "quick":
            invoke_run("quick run", "quick", state_quick, opt.tasks_file)
        else:
            invoke_run("final run", "", state_final, opt.tasks_file)
        n_failed = sum(t.failed for t in run.tasks)
        if n_failed == 0 or turn >= opt.rounds:
            break
        turn += 1
        wait = run.retry_waits[-1]
        write_log("==== {} tasks failed: round {} of {} tries them again "
                  "after {} s".format(n_failed, turn, opt.rounds, wait))
        nap(wait)
    not_done = get_not_done()
    result = "{} of {} tasks done, {} failed, {} blocked".format(
        sum(t.done for t in run.tasks), len(run.tasks),
        sum(t.failed for t in run.tasks), sum(t.blocked for t in run.tasks))
    write_log("==== finished: " + result)
    for line in not_done:
        write_log(line)
    print("")
    if not not_done:
        print("ALL DONE: {}.".format(result))
    else:
        print("NOT ALL DONE: {}.".format(result))
        for line in not_done:
            print("  " + line)
        print("Start the launcher again to try the failed tasks once more.")
    print("Events: " + os.path.join(run.state, "launch.log"))
    print("Logs:   " + os.path.join(run.state, "logs"), flush=True)
    return 0 if not not_done else 1


def main():
    """folders, one launcher only, the launch; returns the exit code"""
    opt = read_options()
    run.opt = opt
    ## the project root (two folders above this script), RUN_ROOT and the
    ## state folder
    here = os.path.dirname(os.path.abspath(__file__))
    run.root = os.path.abspath(os.path.join(here, "..", ".."))
    run_root = opt.run_root
    if run_root == "":
        run_root = os.path.join(run.root, "..", "Masters-Research-R-results",
                                "results")
    run.run_root = os.path.abspath(run_root)
    run.run_root_r = run.run_root.replace("\\", "/")
    state_final = os.path.join(run.run_root, "final-run")
    run.state = state_final
    run.log_file = os.path.join(state_final, "launch.log")
    run.pid_file = os.path.join(state_final, "launcher.pid")
    try:
        run.retry_waits = [int(w) for w in opt.retry_seconds.split(",")]
    except ValueError:
        run.retry_waits = []
    ## the parts of the task table this computer runs (--parts); the tasks
    ## script knows the names and stops at one that is none
    names = set(re.split("[+,; ]+", opt.parts.lower())) - {""}
    run.parts = [] if "all" in names else sorted(names)
    if opt.slots < 1 or not run.retry_waits:
        print("--slots must be 1 or more and --retry-seconds numbers "
              "separated by commas.")
        return 3

    ## one launcher only for a RUN_ROOT (11.)
    os.makedirs(state_final, exist_ok=True)
    if other_launcher():
        print("Another launcher is running for {} (see {}).".format(
            run.run_root, run.pid_file))
        print("Stop it first: qdel <its PBS job>, or kill <its process>.")
        return 2
    own = "{},{},{},{}".format(os.getpid(), stamp(), HOST,
                               os.environ.get("PBS_JOBID", ""))
    with open(run.pid_file, "w") as out:
        out.write(own + "\n")
    run.last_beat = time.time()
    time.sleep(1)
    with open(run.pid_file, "r") as text:
        if text.readline().strip() != own:
            # two launchers started in the same moment: the other one has it
            print("Another launcher has just started for " + run.run_root)
            return 2

    def stop(number, frame):
        raise Stop(signal.Signals(number).name)

    names = ["SIGTERM", "SIGINT"] + ([] if WINDOWS else ["SIGHUP"])
    for name in names:
        signal.signal(getattr(signal, name), stop)

    exit_code = 3
    try:
        exit_code = launch()
    except Stop as stopped:
        write_log("==== stopped by {}: start the launcher again to resume"
                  .format(stopped))
    except Exception as error:
        write_log("FATAL   the launcher stopped, line {}: {}".format(
            sys.exc_info()[2].tb_lineno, error))
    finally:
        ## however the launcher ends: no session is left running and the
        ## next launcher may start. A second signal must not cut this short
        for name in names:
            signal.signal(getattr(signal, name), signal.SIG_IGN)
        sessions = list(run.sessions.values())
        stop_all([s.process for s in sessions])
        for s in sessions:
            write_log("stopped {} pid {}".format(s.task.id, s.process.pid))
        try:
            os.remove(run.pid_file)
        except OSError:
            pass
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
