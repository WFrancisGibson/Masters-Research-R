#!/usr/bin/env python3
##########################################
#########  final run: checks of the launcher for Linux (launch.py)
#########  no R, no Keras, no data: Python itself stands in for Rscript and
#########  this file for the scripts of the tasks; own design
##########################################

## from the project root (setup_hpc.sh runs it on the cluster, about a
## minute):
##   python3 analysis/06_final-run/launch_test.py
## Each check writes a small task table, runs the launcher on it in a
## temporary RUN_ROOT (--tasks-file, --rscript <this Python>, --python uv)
## and looks at its exit code, markers, run files and launch.log. Exit code
## 0: all checks passed.
##
## As the script of a task (first argument "task") this file does what the
## next argument says:
##   single <name>         writes <RUN_ROOT>/out/<name>.txt with the
##                         environment of the session
##   fail_unless <file>    exit code 1 unless <RUN_ROOT>/<file> is there
##   queue <prefix> <n>    the runs <prefix>_1 .. <prefix>_<n> in
##                         <RUN_ROOT>/runs, shared through lock directories
##                         as claim_run() and save_run() of R/runs.R do
##   queue_crash <prefix> <n>  as queue, but the first session takes a run
##                         and ends with exit code 1, leaving its lock
##   hang                  sleeps for ten minutes

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCHER = os.path.join(HERE, "launch.py")
WINDOWS = os.name == "nt"
HEADER = ("id,stage,dataset,unit,profile,validation,final_fit,script,args,"
          "kind,sessions,max_runs,n_runs,run_dir,pattern,needs")
KEPT = ["DATASET", "UNIT", "R_CONFIG_ACTIVE", "VALIDATION", "FINAL_FIT",
        "RUN_SLOT", "RUN_MAX", "RUN_WORKERS", "RUN_DIR", "OMP_NUM_THREADS",
        "TF_NUM_INTRAOP_THREADS", "RETICULATE_PYTHON"]

##########################################
#########  the script of a task
##########################################


def task(args):
    """what a session of the launcher does in these checks"""
    run_root = os.environ["RUN_ROOT"]
    mode = args[0]
    if mode == "single":
        os.makedirs(os.path.join(run_root, "out"), exist_ok=True)
        with open(os.path.join(run_root, "out", args[1] + ".txt"), "w") as f:
            for name in KEPT:
                f.write("{}={}\n".format(name, os.environ.get(name, "<none>")))
        print("single " + args[1])
        return 0
    if mode == "fail_unless":
        print("fail_unless " + args[1])
        return 0 if os.path.exists(os.path.join(run_root, args[1])) else 1
    if mode == "hang":
        print("hang", flush=True)
        time.sleep(600)
        return 0
    ## a queue: claim_run() and save_run() of R/runs.R
    folder = os.path.join(run_root, "runs")
    os.makedirs(folder, exist_ok=True)
    slot = os.environ["RUN_SLOT"]
    run_max = float(os.environ.get("RUN_MAX", "inf"))
    taken = 0
    for k in range(1, int(args[2]) + 1):
        run_file = os.path.join(folder, "{}_{}.rds".format(args[1], k))
        if os.path.exists(run_file) or taken >= run_max:
            continue
        lock = run_file + ".lock"
        try:
            os.mkdir(lock)
        except OSError:
            continue
        with open(os.path.join(lock, "slot_" + slot), "w") as f:
            f.write("")
        taken += 1
        crashed = os.path.join(run_root, "crashed")
        if mode == "queue_crash" and not os.path.exists(crashed):
            with open(crashed, "w") as f:
                f.write("")
            print("crash with the lock of run {}".format(k))
            return 1
        time.sleep(0.2)
        with open(run_file + ".tmp", "w") as f:
            f.write("run {} slot {}\n".format(k, slot))
        os.rename(run_file + ".tmp", run_file)
        shutil.rmtree(lock)
        print("run {}".format(k), flush=True)
    return 0


##########################################
#########  functions of the checks
##########################################

failures = []


def expect(condition, text):
    """one check: counted and printed if it fails"""
    if not condition:
        failures.append(text)
        print("  FAILED: " + text)


def row(id, stage, args, needs="", profile="", n_runs="", sessions="",
        max_runs="", pattern="", validation=""):
    """a row of a task table (launch.ps1, contract 2.)"""
    queue = n_runs != ""
    fields = [id, stage, "baseline", "", profile, validation, "",
              '"' + __file__.replace("\\", "/") + '"', "task " + args,
              "queue" if queue else "single", sessions, max_runs, n_runs,
              "runs" if queue else "", '"' + pattern + '"', needs]
    return ",".join(str(f) for f in fields)


def command(run_root, rows, more):
    """the task table of a check and the command of the launcher on it"""
    os.makedirs(run_root, exist_ok=True)
    table = os.path.join(run_root, "table.csv")
    with open(table, "w") as f:
        f.write("\n".join([HEADER] + rows) + "\n")
    return [sys.executable, LAUNCHER, "--run-root", run_root,
            "--tasks-file", table, "--rscript", sys.executable,
            "--python", "uv", "--poll-seconds", "0.2",
            "--retry-seconds", "1,1", "--beat-seconds", "1"] + more


def launch(run_root, rows, more=None):
    """runs the launcher on a task table; its exit code"""
    result = subprocess.run(command(run_root, rows, more or []),
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True)
    if "Traceback" in result.stdout:
        print(result.stdout)
    return result.returncode


def state_file(run_root, *parts):
    return os.path.join(run_root, "final-run", *parts)


def read(file):
    try:
        with open(file, "r") as f:
            return f.read()
    except OSError:
        return ""


def locks(run_root):
    """the lock directories and temporary files left under a RUN_ROOT"""
    left = []
    for folder, folders, files in os.walk(run_root):
        left += [f for f in folders if f.endswith(".lock")]
        left += [f for f in files if f.endswith(".tmp")]
    return left


def most_sessions(log):
    """the most sessions running at once, by the events of launch.log"""
    now = 0
    most = 0
    for line in log.splitlines():
        event = line[21:28]
        if event == "start  ":
            now += 1
        if event == "end    ":
            now -= 1
        most = max(most, now)
    return most


##########################################
#########  the checks
##########################################


def check_run(top):
    print("a run: needs, a queue shared by sessions, the environment")
    root = os.path.join(top, "run")
    rows = [row("a", 0, "single a"),
            row("b", 0, "single b", needs="a"),
            row("q", 1, "queue q 12", needs="b", n_runs=12, sessions=4,
                max_runs=2, pattern="^q_[0-9]+[.]rds$"),
            row("c", 2, "single c", needs="q;a", profile="age_numeric",
                validation="claims_split")]
    # a lock and a temporary file left by a launcher that was killed
    os.makedirs(os.path.join(root, "runs", "q_3.rds.lock"))
    with open(os.path.join(root, "runs", "q_3.rds.lock", "slot_9"), "w"):
        pass
    with open(os.path.join(root, "runs", "q_4.rds.tmp"), "w"):
        pass
    expect(launch(root, rows, ["--slots", "3"]) == 0, "run: exit code 0")
    log = read(state_file(root, "launch.log"))
    for id in ["a", "b", "c"]:
        expect(os.path.exists(state_file(root, "done", id + ".done")),
               "run: done marker of " + id)
    runs = [f for f in os.listdir(os.path.join(root, "runs"))]
    expect(len(runs) == 12 and all(f.endswith(".rds") for f in runs),
           "run: 12 run files and nothing else: {}".format(sorted(runs)))
    expect(not locks(root), "run: no lock or temporary file left")
    expect(most_sessions(log) == 3, "run: at most 3 sessions at once")
    expect(log.count("start   q slot") >= 6,
           "run: a fresh session after RUN_MAX = 2 runs")
    expect(log.find("start   b slot") > log.find("done    a"),
           "run: b waits for a")
    expect("stage   2 complete" in log, "run: the stages are logged")
    c = read(os.path.join(root, "out", "c.txt"))
    for line in ["DATASET=baseline", "UNIT=<none>",
                 "R_CONFIG_ACTIVE=age_numeric", "VALIDATION=claims_split",
                 "FINAL_FIT=<none>", "RUN_MAX=<none>", "RUN_WORKERS=3",
                 "RUN_DIR=<none>", "OMP_NUM_THREADS=1",
                 "TF_NUM_INTRAOP_THREADS=1"]:
        expect(line + "\n" in c, "run: session of c has " + line)
    expect("R_CONFIG_ACTIVE=<none>" in read(os.path.join(root, "out",
                                                         "a.txt")),
           "run: no profile in the final run")
    # a second launch has nothing to do
    expect(launch(root, rows, ["--slots", "3"]) == 0, "run again: exit code 0")
    log2 = read(state_file(root, "launch.log"))
    expect(log2.count("start   ") == log.count("start   "),
           "run again: no session is started")


def check_failures(top):
    print("failures: three tries, blocked tasks, a later launch")
    root = os.path.join(top, "failures")
    rows = [row("f", 0, "fail_unless mended"),
            row("g", 0, "single g", needs="f"),
            row("h", 0, "single h"),
            row("q", 1, "queue_crash q 6", n_runs=6, sessions=2,
                pattern="^q_[0-9]+[.]rds$")]
    expect(launch(root, rows, ["--slots", "2", "--rounds", "1"]) == 1,
           "failures: exit code 1")
    log = read(state_file(root, "launch.log"))
    expect(os.path.exists(state_file(root, "failed", "f.failed")),
           "failures: the failed marker of f")
    expect(log.count("start   f slot") == 3, "failures: f is tried 3 times")
    expect("blocked g: it needs f" in log, "failures: g is blocked")
    expect(os.path.exists(state_file(root, "done", "h.done")),
           "failures: h is done")
    expect("failure q slot" in log and "done    q" in log,
           "failures: the queue goes on after a session that crashed")
    expect(len(os.listdir(os.path.join(root, "runs"))) == 6 and
           not locks(root), "failures: 6 run files, the lock is gone")
    with open(os.path.join(root, "mended"), "w"):
        pass
    expect(launch(root, rows, ["--slots", "2"]) == 0,
           "failures: exit code 0 once f is mended")
    expect(os.path.exists(state_file(root, "done", "g.done")) and
           not os.path.exists(state_file(root, "failed", "f.failed")),
           "failures: g is done, the failed marker is gone")


def check_quick(top):
    print("a quick run: the rows of another profile are left out")
    root = os.path.join(top, "quick")
    rows = [row("a", 0, "single a"),
            row("n", 0, "single n", profile="age_numeric"),
            row("m", 1, "single m", needs="n"),
            row("k", 1, "single k", profile="quick_age_numeric")]
    expect(launch(root, rows, ["--slots", "2", "--profile", "quick"]) == 0,
           "quick: exit code 0")
    done = sorted(os.listdir(state_file(root, "quick", "done")))
    expect(done == ["a.done", "k.done"],
           "quick: a and k are done, n and m left out: {}".format(done))
    expect("R_CONFIG_ACTIVE=quick\n" in read(os.path.join(root, "out",
                                                          "a.txt")),
           "quick: a runs under the quick profile")
    expect("R_CONFIG_ACTIVE=quick_age_numeric\n" in
           read(os.path.join(root, "out", "k.txt")),
           "quick: k keeps its own profile")


def check_table(top):
    print("a wrong task table stops the launcher")
    root = os.path.join(top, "table")
    rows = [row("a", 0, "single a", needs="nobody"),
            row("q", 0, "queue q 2", n_runs=2, sessions=1,
                pattern="^q_[[:digit:]]+[.]rds$")]
    expect(launch(root, rows, ["--slots", "1"]) == 3, "table: exit code 3")
    log = read(state_file(root, "launch.log"))
    expect("needs the unknown task nobody" in log and "POSIX class" in log,
           "table: the log names what is wrong")


def check_stop(top):
    print("one launcher for a RUN_ROOT; a signal stops the sessions")
    root = os.path.join(top, "stop")
    rows = [row("x", 0, "hang")]
    first = subprocess.Popen(command(root, rows, ["--slots", "1"]),
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    log_file = state_file(root, "launch.log")
    end = time.time() + 30
    while "start   x slot" not in read(log_file) and time.time() < end:
        time.sleep(0.2)
    expect("start   x slot" in read(log_file), "stop: the session started")
    session = read(state_file(root, "sessions.csv")).splitlines()[-1]
    process_id = int(session.split(",")[2])
    expect(launch(root, rows, ["--slots", "1"]) == 2,
           "stop: a second launcher ends with exit code 2")
    if WINDOWS:
        # no SIGTERM there: the launcher is cut off, its session stopped
        first.kill()
        subprocess.call(["taskkill", "/PID", str(process_id), "/T", "/F"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        first.wait()
        return
    first.send_signal(signal.SIGTERM)
    expect(first.wait(30) == 3, "stop: exit code 3 after SIGTERM")
    log = read(log_file)
    expect("stopped by SIGTERM" in log and "stopped x pid" in log,
           "stop: the log tells")
    expect(not os.path.exists(state_file(root, "launcher.pid")),
           "stop: launcher.pid is removed")
    time.sleep(0.5)
    expect(not os.path.exists("/proc/{}".format(process_id)),
           "stop: the session is gone")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "task":
        return task(sys.argv[2:])
    top = tempfile.mkdtemp(prefix="launch_test_")
    try:
        for check in [check_run, check_failures, check_quick, check_table,
                      check_stop]:
            check(top)
    finally:
        shutil.rmtree(top, ignore_errors=True)
    if failures:
        print("{} checks FAILED".format(len(failures)))
        return 1
    print("launch_test: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
