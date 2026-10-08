##########################################
#########  final run: the launcher
#########  keeps R sessions busy with the tasks of the task table until all
#########  are done; own design (Windows PowerShell 5.1)
##########################################

## from the project root:
##   powershell -ExecutionPolicy Bypass -File "analysis\06_final-run\launch.ps1"
## stop it with stop.ps1 (or Ctrl+C in its window) and start it again to
## resume: finished runs and tasks are never repeated.
##
## parameters
##   -Slots        R sessions at once (default: the logical processors)
##   -RunRoot      RUN_ROOT of the sessions (default:
##                 ..\Masters-Research-R-results\results beside the project)
##   -Profile      "" the final run (default), "quick" only the quick profile
##   -SkipSmoke    no smoke test before the final run
##   -Parts        the parts of the task table this computer runs, for a
##                 run on two computers: names joined by "+", as
##                 -Parts data+bccnn_main+bootstrap+masking (the names and
##                 what a part brings with it: the top of
##                 "final run tasks.R"; default: all). The smoke test is
##                 then of these parts (contract 9.)
##   -NoPush       the results worktree is not committed and pushed
##   -PushHours    hours between two pushes (default 6)
##   -Rounds       times the final run goes over the task table while tasks
##                 fail (default 2: the failed tasks get a second round)
##   -Rscript      Rscript.exe to use instead of R 4.6.1 from the registry
##   -Python       python.exe of the Python environment of the fits (default:
##                 ..\Masters-Research-R-python\env\Scripts\python.exe beside
##                 the project, built by setup_vm.ps1), or "uv": every R
##                 session resolves its Python packages with uv (contract 10.)
##   -QuietHours   a session without output and without a new run file for
##                 so long is named in the progress line (default 6)
##   for tests:
##   -TasksFile    an existing task table, used instead of a generated one
##                 (then there is no smoke test)
##   -TasksScript  the R script that writes the task table
##   -PollSeconds, -SummaryMinutes, -RetrySeconds, -PushSeconds
##                 the waiting times below
##
## exit code: 0 every task done; 1 tasks failed or blocked, or the smoke test
## failed; 2 another launcher is running; 3 the launcher itself failed
##
## ---------------------------------------------------------------------
## THE CONTRACT between the launcher and the R side ("final run tasks.R",
## "final run status.R", "final run timings.R", R/runs.R, the fit scripts)
## ---------------------------------------------------------------------
##
## 1. Folders. RUN_ROOT is the folder the R scripts write under (config.yml
##    run_root). <state> is <RUN_ROOT>/final-run for the final run and
##    <RUN_ROOT>/final-run/quick for the quick profile (the smoke test).
##    In <state>:
##      tasks.csv             the task table (2.)
##      launch.log            the events, one line each: time
##                            (yyyy-MM-dd HH:mm:ss, in every regional format
##                            of Windows), two blanks, event, task.
##                            Events: start <id> slot <k> pid <p>; end <id>
##                            slot <k>: exit code <c>, <s> s[; run files <n>
##                            of <N>]; done <id>; failure <id> slot <k>: ...;
##                            FAILED <id>: ...; blocked <id>: ...; stage <n>
##                            complete; push ok|FAILED|left out ...;
##                            progress tasks <a> of <b> done, <c> failed, <d>
##                            blocked; runs <e> of <f>; sessions <g> of <h>:
##                            <id> x<n>, ... [; failed pushes in a row: <n>]
##                            [; quiet for <h> h (no output, no new run
##                            file): <id> slot <k> pid <p>, ...]; WARNING
##                            <id>: ...; unlock, removed, stopped
##                            (left-overs); ERROR, FATAL (the launcher)
##      sessions.csv          the running sessions: slot, id, pid, started,
##                            log (pid: the cmd.exe that runs Rscript); slot
##                            0, id git: the git command that is running
##      done/<id>.done        a single task that is done
##      failed/<id>.failed    a task given up: the reason and the last
##                            lines of its log; removed at the next round or
##                            launch, which tries the task again
##      logs/<id>_slot<k>.log output and messages of the sessions of task
##                            <id> in slot k, appended
##      logs/tasks_table.log  output of the script that writes the table
##      smoke.done            (quick) the smoke test passed: not repeated
##      smoke.<parts>.done    (quick) the same, of the parts of -Parts
##      smoke_failed.txt      (quick) the tasks that failed in the smoke test
##    in <RUN_ROOT>/final-run only:
##      launcher.pid          process id and start time of the launcher (for
##                            stop.ps1)
##      run_info.txt          computer, R, Python, code commit and slots, one
##                            block per launch
##      logs/git.log          output of git add, commit and push (a command
##                            that is running writes to its own file
##                            logs/git_<time>_<command>.log.tmp)
##
## 2. The task table <state>/tasks.csv is written by
##      Rscript "analysis/06_final-run/final run tasks.R"
##    run by the launcher at every start, with the project root as working
##    directory and the environment variables RUN_ROOT (absolute path,
##    forward slashes), FINAL_RUN_PARTS (the parts of -Parts joined by
##    "+"; not set: the whole table) and R_CONFIG_ACTIVE ("quick" for the
##    quick profile,
##    not set for the final run). A header line and one row per task; an
##    empty field and NA mean the same. Columns:
##      id          unique; letters, digits, ".", "_" and "-" only
##      stage       integer; a lower stage is earlier and goes first
##      dataset     DATASET of the session
##      unit        UNIT (may be empty)
##      profile     R_CONFIG_ACTIVE of the session; empty: the profile of
##                  the run ("quick" in the smoke test, none in the final
##                  run). A row with a profile of its own (age_numeric)
##                  keeps it in the final run. In a quick run a session has
##                  the quick settings only under a profile whose name
##                  begins with "quick" (a profile of config.yml that
##                  inherits quick, say quick_age_numeric): a row with any
##                  other profile is left out there, with the rows that
##                  need it
##      validation  VALIDATION (may be empty)
##      final_fit   FINAL_FIT (may be empty = the default)
##      script      the R script, relative to the project root; spaces are
##                  fine
##      args        further arguments, as typed on a command line
##      kind        single or queue
##      sessions    queue: the most R sessions that may run it at once
##      max_runs    queue: RUN_MAX of a session (empty = no limit)
##      n_runs      queue: the number of run files of the complete task. It
##                  must be the length of the run list the fit script
##                  itself loops over (take it from the same function, and
##                  test that): with a number too small the task counts as
##                  done while runs are missing and the tasks that need it
##                  start on an incomplete set (the launcher can only warn
##                  when it sees more files than n_runs); with a number too
##                  large the task fails after three tries
##      run_dir     queue: the folder of the run files, relative to RUN_ROOT
##      pattern     queue: regular expression (.NET syntax, case-sensitive:
##                  write [0-9] and [.], no [[:digit:]] or other POSIX
##                  class of R) that matches the names of the run files of
##                  this task and of no other file in run_dir; anchor it:
##                  ^bccnn_grid_fit_.*[.]rds$
##      needs       ids, separated by ";", of the tasks to be done first
##
## 3. Done. single: the marker <state>/done/<id>.done exists; the launcher
##    writes it when the session ends with exit code 0 (delete the marker to
##    have the task run again). queue: the files in run_dir whose name
##    matches pattern number n_runs or more (never counted: names that end
##    in .tmp, a run being saved, or .partial, an unfinished nagging block).
##
## 4. A session is one Rscript process, R_HOME\bin\x64\Rscript.exe (the
##    process that works; bin\Rscript.exe only starts it):
##      Rscript "<script>" <args>
##    working directory: the project root. Environment: DATASET, UNIT,
##    R_CONFIG_ACTIVE, VALIDATION, FINAL_FIT (set if not empty, removed
##    otherwise), RUN_ROOT, RUN_SLOT (the slot, 1 .. Slots), RUN_MAX (queue
##    tasks with max_runs, removed otherwise), RUN_WORKERS (= Slots),
##    OMP_NUM_THREADS, MKL_NUM_THREADS, OPENBLAS_NUM_THREADS,
##    TF_NUM_INTRAOP_THREADS and TF_NUM_INTEROP_THREADS = 1,
##    TF_CPP_MIN_LOG_LEVEL = 2, the Python variables of 10.; RUN_DIR is
##    removed (with it keras3 adds a TensorBoard callback to every fit);
##    everything else as in the launcher's own environment. Output and
##    messages are appended to <state>/logs/<id>_slot<k>.log. R lets the
##    file .Renviron of the project root (or of the user's R home) win over
##    these variables: the launcher stops at its start if that file names
##    one of them (RAW_DIR, say, is fine there).
##
## 5. Runs shared by sessions (R/runs.R). A session with RUN_SLOT takes a
##    run with claim_run(): the directory <run_file>.lock with the file
##    slot_<RUN_SLOT> in it; save_run() writes <run_file>.tmp, renames it
##    and removes the lock. After RUN_MAX runs a session takes no more and
##    its script ends with exit code 0; the launcher starts a fresh session
##    (the memory of an R session that fits Keras networks grows). A fit
##    script therefore ends with its loop over the runs. A session takes
##    only runs whose file names match the pattern of its own task: the
##    launcher removes the locks under the pattern of a task of which no
##    session is running.
##
## 6. Which task a free slot gets: the first in (stage, row) order that is
##    not done, not failed, whose needs are all done, and that can use
##    another session. single: no session of it is running. queue: its
##    running sessions < min(sessions, n_runs - run files - lock directories
##    in run_dir that no running session of the task holds), so a queue
##    never has more sessions than runs still to be saved.
##
## 7. Failures. A session that ends with another exit code than 0, or a
##    queue session after which the task has no more run files than at its
##    start (and is not done), is a failure of its task: the lock
##    directories of its slot (those with slot_<k>; in run_dir, or anywhere
##    under RUN_ROOT if run_dir is empty) are removed and the task is tried
##    again after a wait (-RetrySeconds: 60 s after the first failure, 600 s
##    after the second). A new run file sets the count back to 0. The third
##    failure in a row marks the task failed: it is not started again in
##    this round, and the tasks that need it are blocked. Only a session
##    started after the last counted failure counts, so that the sessions
##    of one task that die together are one failure. When every task is
##    done, failed or blocked and some failed, the launcher goes over the
##    task table a second time (-Rounds): the failed tasks get three new
##    tries, then it ends. A session is never stopped for taking long; one
##    without output and without a new run file of its task for -QuietHours
##    is named in the progress line.
##
## 8. The results. After every completed stage, every -PushHours hours and
##    at the end the launcher commits and pushes the results worktree: the
##    parent of RUN_ROOT if RUN_ROOT is a folder "results" in a git worktree
##    other than the project. git add, commit and push run beside the loop,
##    which goes on starting sessions (time limits: 1800 s add, 600 s
##    commit, -PushSeconds = 7200 s push); only the pushes at the end of
##    the smoke test and of the launcher are waited for. A file over 50 MB
##    is added to the .gitignore of the worktree first (GitHub refuses
##    files over 100 MB), and an index.lock left by a git command that was
##    cut off is removed. A failed push is logged, counted in the progress
##    line and tried again at the next occasion; the last lines of the
##    launcher say if the last one failed. Nothing else may push to the
##    branch during the run.
##
## 9. The smoke test. Without -SkipSmoke, -Profile and -TasksFile the
##    launcher first runs the tasks of the quick profile (<state> =
##    final-run/quick). If a task fails there it writes smoke_failed.txt,
##    pushes and stops with exit code 1; otherwise it writes smoke.done and
##    starts the final run. A later launch finds smoke.done and goes
##    straight to the final run. To repeat the smoke test delete
##    final-run/quick and data/processed/quick: with smoke.done alone gone
##    every quick task is still done and smoke.done is written again.
##    With -Parts the smoke test runs the quick table of these parts and
##    writes smoke.<parts>.done (the names sorted, joined by "-"); a launch
##    with other parts has its own smoke test, in which the quick tasks
##    done before are not repeated. smoke.done stands for every part.
##
## 10. Python. setup_vm.ps1 builds the Python environment of the fits once,
##    from requirements.txt, in ..\Masters-Research-R-python\env beside the
##    project, and "keras check.R" checks it (as a task of stage 0 it also
##    puts the versions into the pushed logs). Every session gets
##    RETICULATE_PYTHON = its python.exe, RETICULATE_USE_MANAGED_VENV = no
##    and RETICULATE_CHECK_REQUIRED_PACKAGES = false (KERAS_PYTHON is
##    removed): reticulate then starts this Python and nothing else, no
##    session needs the internet, and no release of a Python package
##    changes the run. The launcher stops at its start if the python.exe is
##    not there. -Python uv leaves these variables alone: each session then
##    resolves the packages keras3 and analysis/00_setup.R declare with uv,
##    which needs the internet at every session start (hence the waits and
##    the second round of 7.).
##
## 11. One launcher for a RUN_ROOT: Windows gives the named mutex
##    Global\final-run-<RUN_ROOT> to one process only; a second launcher
##    ends with exit code 2. At its start the launcher stops the sessions
##    and the git command an earlier launcher left running (sessions.csv)
##    and then removes every lock directory and .tmp file under RUN_ROOT;
##    if one of them cannot be stopped it ends with exit code 3 and removes
##    nothing.
## ---------------------------------------------------------------------

param(
  [int]$Slots = [Environment]::ProcessorCount,
  [string]$RunRoot = "",
  [string]$Profile = "",
  [switch]$SkipSmoke,
  [string]$Parts = "",
  [switch]$NoPush,
  [double]$PushHours = 6,
  [string]$Rscript = "",
  [string]$Python = "",
  [double]$QuietHours = 6,
  [string]$TasksFile = "",
  [string]$TasksScript = "analysis/06_final-run/final run tasks.R",
  [int]$PollSeconds = 5,
  [double]$SummaryMinutes = 5,
  [string]$RetrySeconds = "60,600",
  [int]$PushSeconds = 7200,
  [int]$Rounds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

## times and numbers are written the same way under every regional format
## of Windows (another one writes 16.02.36, or the year 2569)
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = $invariant

$max_fails = 3                 # failures in a row that fail a task
$max_file = 50MB               # larger files are not committed
$time_format = "yyyy-MM-dd HH:mm:ss"

##########################################
#########  functions
##########################################

## a time as text, for the logs and for comparing start times
function Get-Stamp($time) {
  return $time.ToString($time_format, $invariant)
}

## one line with the time to the console and to the launch log; a log that
## cannot be written at this moment (git or a virus scanner reads it) must
## not stop the launcher
function Write-Log($text) {
  $line = (Get-Stamp (Get-Date)) + "  " + $text
  Write-Host $line
  try {
    Add-Content -Path $script:log_file -Value $line -Encoding ASCII
  } catch { }
}

## the size of a file in bytes, -1 if it cannot be read
function Get-Size($file) {
  try {
    return (New-Object System.IO.FileInfo($file)).Length
  } catch {
    return -1
  }
}

## starts a program through cmd.exe, which appends its output and messages
## to a log file; variables: environment variables to set (a text) or to
## remove (""). Returns the process: cmd.exe, the program is its child
function Start-Logged($exe, $arguments, $log, $folder, $variables) {
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $env:ComSpec
  $info.Arguments = "/d /s /c `"`"$exe`" $arguments < NUL >> `"$log`" 2>&1`""
  $info.WorkingDirectory = $folder
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  foreach ($name in $variables.Keys) {
    if ($variables[$name] -eq "") {
      $info.EnvironmentVariables.Remove($name)
    } else {
      $info.EnvironmentVariables[$name] = $variables[$name]
    }
  }
  return [System.Diagnostics.Process]::Start($info)
}

## stops a process and the processes it started, and waits up to 10 s for
## it to go; TRUE if it is gone (FALSE: no right to stop it, say a process
## started as administrator)
function Stop-Tree($id) {
  & $env:ComSpec /d /c "taskkill /PID $id /T /F > NUL 2>&1"
  foreach ($try in 1..20) {
    if ($null -eq (Get-Process -Id $id -ErrorAction SilentlyContinue)) {
      return $true
    }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

## waits for a process of Start-Logged; one still running after the limit is
## stopped. Returns its exit code, -1 after the limit
function Wait-Logged($process, $seconds) {
  if (-not $process.WaitForExit([int]$seconds * 1000)) {
    Stop-Tree $process.Id | Out-Null
    return -1
  }
  return $process.ExitCode
}

## TRUE if the process with this id is the one started at this time: Windows
## uses a process id again, so the id alone could be another program. If the
## start time cannot be read (a process of an administrator or of another
## user) the name of the program decides: better one wrong "it is running"
## than a second set of sessions beside a living one
function Test-Process($id, $started, $name) {
  $process = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($null -eq $process) { return $false }
  try {
    return ((Get-Stamp $process.StartTime) -eq $started)
  } catch {
    return ($process.ProcessName -eq $name)
  }
}

## the folders under a folder, itself included; a lock directory is listed
## but not read, .git is left out, and a folder that disappears while it is
## read (the lock of a running session) is passed over
function Get-Folders($top) {
  $found = @()
  $stack = New-Object System.Collections.Stack
  $stack.Push($top)
  while ($stack.Count -gt 0) {
    $folder = $stack.Pop()
    if ($folder.EndsWith("\.git")) { continue }
    $found += $folder
    if ($folder.EndsWith(".lock")) { continue }
    try {
      foreach ($sub in [System.IO.Directory]::GetDirectories($folder)) {
        $stack.Push($sub)
      }
    } catch { }
  }
  return $found
}

## removes lock directories of claim_run() under a folder: those of one slot
## (the file slot_<k> in them; slot 0: of any slot) and of the run files
## that match a pattern ("": any). A directory that holds anything but slot
## files is not a lock of ours and stays
function Remove-Locks($top, $slot, $pattern) {
  if (-not (Test-Path $top)) { return }
  foreach ($folder in @(Get-Folders $top)) {
    if (-not $folder.EndsWith(".lock")) { continue }
    $name = [System.IO.Path]::GetFileName($folder)
    $run_file = $name.Substring(0, $name.Length - 5)
    if ($pattern -ne "" -and $run_file -cnotmatch $pattern) { continue }
    try {
      $inside = @([System.IO.Directory]::GetFileSystemEntries($folder))
      $other = @($inside | Where-Object {
        -not [System.IO.Path]::GetFileName($_).StartsWith("slot_")
      })
      $mine = ($slot -eq 0) -or
              [System.IO.File]::Exists((Join-Path $folder "slot_$slot"))
      if ($other.Count -eq 0 -and $mine) {
        Remove-Item -LiteralPath $folder -Recurse -Force
        Write-Log ("unlock  " + $folder)
      }
    } catch { }
  }
}

## a field of a row of the task table as text; NA is R's missing value
function Get-Field($line, $name) {
  $value = ([string]$line.$name).Trim()
  if ($value -eq "NA") { $value = "" }
  return $value
}

## counts the run files and the lock directories of a queue task (contract
## 3. and 6.; locks_live: those held by a session of the task that is
## running); a new run file sets the failures of the task back to 0, and
## with all run files the task is done
function Update-Count($task, $log_done) {
  $folder = Join-Path $run_root $task.run_dir
  $own_slots = @($script:sessions.Keys | Where-Object {
    $script:sessions[$_].task.id -eq $task.id
  })
  $files = 0
  $locks = 0
  $locks_live = 0
  try {
    if (Test-Path $folder) {
      foreach ($file in [System.IO.Directory]::GetFiles($folder)) {
        $name = [System.IO.Path]::GetFileName($file)
        if ($name -cmatch $task.pattern -and -not $name.EndsWith(".tmp") -and
            -not $name.EndsWith(".partial")) {
          $files += 1
        }
      }
      $lock_folders = [System.IO.Directory]::GetDirectories($folder, "*.lock")
      foreach ($lock in $lock_folders) {
        $name = [System.IO.Path]::GetFileName($lock)
        if ($name.Substring(0, $name.Length - 5) -cnotmatch $task.pattern) {
          continue
        }
        $locks += 1
        foreach ($slot in $own_slots) {
          if ([System.IO.File]::Exists((Join-Path $lock "slot_$slot"))) {
            $locks_live += 1
            break
          }
        }
      }
    }
  } catch {
    return                     # folder not readable now: keep the last count
  }
  if ($files -gt $task.files) { $task.fails = 0 }
  $task.files = $files
  $task.locks = $locks
  $task.locks_live = $locks_live
  if ($files -gt $task.n_runs -and -not $task.warned -and
      -not $task.id.EndsWith(".benchmark")) {
    # more run files than the task table says the task has (contract 2.);
    # not for a benchmark row, which shares the run files of its queue
    $task.warned = $true
    Write-Log ("WARNING {0}: {1} run files match its pattern, n_runs is {2}" -f
               $task.id, $files, $task.n_runs)
  }
  if ($files -ge $task.n_runs -and -not $task.done) {
    $task.done = $true
    if ($log_done) { Write-Log ("done    " + $task.id) }
    if ($task.failed) {
      # the sessions still running finished a task given up before
      $task.failed = $false
      $marker = Join-Path $script:state ("failed\" + $task.id + ".failed")
      Remove-Item -Path $marker -Force -ErrorAction SilentlyContinue
    }
  }
}

## the running sessions, and the git command that runs, to
## <state>/sessions.csv: a later launcher and stop.ps1 stop them from this
## file
function Write-Sessions() {
  $lines = @("slot,id,pid,started,log")
  foreach ($slot in @($script:sessions.Keys | Sort-Object)) {
    $s = $script:sessions[$slot]
    $lines += ("{0},{1},{2},{3},`"{4}`"" -f
               $slot, $s.task.id, $s.process.Id, $s.started_text, $s.log)
  }
  $p = $script:push
  if ($null -ne $p -and $null -ne $p.process) {
    $lines += ("0,git,{0},{1},`"{2}`"" -f
               $p.process.Id, $p.started_text, $git_log)
  }
  $file = Join-Path $script:state "sessions.csv"
  try {
    Set-Content -Path $file -Value $lines -Encoding ASCII
  } catch { }
}

## stops the sessions listed in the sessions.csv of a state folder (left by
## a launcher that was stopped or lost with a restart of the computer). A
## file cut off by a power cut is passed over. A session that cannot be
## stopped ends the launch: its locks must stay (contract 11.)
function Stop-Sessions($state_folder) {
  $file = Join-Path $state_folder "sessions.csv"
  if (-not (Test-Path $file)) { return }
  $alive = @()
  try {
    foreach ($line in @(Import-Csv -Path $file)) {
      $id = [string]$line.pid
      if ($id -notmatch "^[0-9]+$") { continue }
      if (-not (Test-Process $id ([string]$line.started) "cmd")) { continue }
      if (Stop-Tree $id) {
        Write-Log ("stopped the session of an earlier launcher: " + $line.id +
                   " slot " + $line.slot + " pid " + $id)
      } else {
        # no right to stop it: the same holds for the others
        $alive += $id
        break
      }
    }
  } catch {
    Write-Log ("sessions.csv not readable, left aside: " +
               $_.Exception.Message)
  }
  if ($alive.Count -gt 0) {
    throw ("R sessions of an earlier launcher are still running and could" +
           " not be stopped (process " + ($alive -join ", ") + " of " +
           $file + "). Stop them with stop.ps1 in a PowerShell opened as" +
           " administrator, then start launch.ps1 again. Nothing was" +
           " started and no lock was removed.")
  }
  Remove-Item -Path $file -Force
}

## starts the commit and push of the results worktree (contract 8.). The git
## commands run one after the other beside the loop: Step-Push looks at the
## one that runs and starts the next. A push asked for while one is running
## follows it. Never fatal: what fails is logged and tried again at the next
## occasion
function Start-Push($message) {
  if ($worktree -eq "") { return }
  if ($null -ne $script:push) {
    $script:push_next = $message
    return
  }
  $steps = New-Object System.Collections.Queue
  try {
    # a git command cut off by a stop, a time limit or a restart leaves
    # index.lock, and git then refuses every add; no git command of the
    # launcher is running at this point
    $index_lock = Join-Path $git_dir "index.lock"
    if (Test-Path $index_lock) {
      Remove-Item -Path $index_lock -Force
      Write-Log ("removed " + $index_lock)
    }
    # a file GitHub would refuse goes to .gitignore and out of the index
    $ignore_file = Join-Path $worktree ".gitignore"
    $ignored = @(Get-Content -Path $ignore_file)
    $ends_line = [System.IO.File]::ReadAllText($ignore_file).EndsWith("`n")
    foreach ($folder in @(Get-Folders $run_root)) {
      if ($folder.EndsWith(".lock")) { continue }
      $large = @()
      try {
        $large = @((New-Object System.IO.DirectoryInfo($folder)).GetFiles() |
                   Where-Object { $_.Length -gt $max_file })
      } catch { }
      foreach ($file in $large) {
        $path = $file.FullName.Substring($worktree.Length).Replace("\", "/")
        if ($ignored -notcontains $path) {
          if (-not $ends_line) {
            # the last line of .gitignore has no line end: give it one
            Add-Content -Path $ignore_file -Value "" -Encoding ASCII
            $ends_line = $true
          }
          Add-Content -Path $ignore_file -Value $path -Encoding ASCII
          $relative = $path.Substring(1)
          $steps.Enqueue(@{
            name = "rm"
            arguments = "rm --cached --quiet --ignore-unmatch -- `"" +
                        $relative + "`""
            seconds = 600
          })
          Write-Log ("push    left out, over 50 MB: " + $relative)
        }
      }
    }
  } catch {
    $script:push_fails += 1
    Write-Log ("push    FAILED: " + $_.Exception.Message +
               "; failed pushes in a row: " + $script:push_fails)
    return
  }
  $text = "final run: $message (code $code_commit, $env:COMPUTERNAME)"
  $steps.Enqueue(@{ name = "add"; arguments = "add -A"; seconds = 1800 })
  # exit code 1 of this diff: something is staged
  $steps.Enqueue(@{ name = "diff"; arguments = "diff --cached --quiet"
                    seconds = 600 })
  $steps.Enqueue(@{ name = "commit"; arguments = "commit --quiet -m `"$text`""
                    seconds = 600 })
  $steps.Enqueue(@{ name = "push"; arguments = "push --quiet origin HEAD"
                    seconds = $PushSeconds })
  $script:push = New-Object PSObject -Property @{
    message = $message
    steps = $steps
    step = $null
    process = $null
    started = Get-Date
    started_text = ""
    step_log = ""
  }
  Step-Push
}

## the push that is under way: nothing to do while its git command runs
## (one over its time limit is stopped); when it has ended the next one is
## started, and after the last one the push is complete. git must never wait
## for a password: without a stored credential it fails at once
function Step-Push() {
  $p = $script:push
  if ($null -eq $p) { return }
  try {
    if ($null -ne $p.process) {
      $code = -1
      if ($p.process.HasExited) {
        $code = $p.process.ExitCode
      } elseif (((Get-Date) - $p.started).TotalSeconds -lt $p.step.seconds) {
        return
      } else {
        Stop-Tree $p.process.Id | Out-Null
      }
      $name = $p.step.name
      $p.process = $null
      Write-Sessions
      # its output goes from its own file to git.log; the file stays if
      # that cannot be done now (the next launch removes it)
      try {
        $output = @(Get-Content -Path $p.step_log)
        if ($output.Count -gt 0) {
          Add-Content -Path $git_log -Value $output -Encoding ASCII
        }
        Remove-Item -LiteralPath $p.step_log -Force
      } catch { }
      if ($name -eq "diff" -and $code -eq 0) {
        # nothing is staged: the commit is left out
        $p.steps.Dequeue() | Out-Null
      } elseif ($code -ne 0 -and $name -ne "rm" -and
                -not ($name -eq "diff" -and $code -eq 1)) {
        $reason = "git $name, exit code $code"
        if ($code -eq -1) {
          $reason = "git $name, stopped after " + $p.step.seconds + " s"
        }
        Complete-Push $false $reason
        return
      }
    }
    if ($p.steps.Count -eq 0) {
      Complete-Push $true ""
      return
    }
    ## the next git command, with a file of its own for its output: a
    ## process left by an earlier git command (it would hold the file it
    ## wrote to) cannot stand in the way of this one. The name ends in
    ## .tmp: such files are never committed and go at the next launch
    $p.step = $p.steps.Dequeue()
    $now = Get-Date
    $line = "==== " + (Get-Stamp $now) + " git " + $p.step.arguments
    try { Add-Content -Path $git_log -Value $line -Encoding ASCII } catch { }
    $p.step_log = Join-Path (Split-Path $git_log -Parent) ("git_" +
      $now.ToString("yyyyMMdd_HHmmss_fff", $invariant) + "_" +
      $p.step.name + ".log.tmp")
    $variables = @{ GIT_TERMINAL_PROMPT = "0"; GCM_INTERACTIVE = "never" }
    $p.process = Start-Logged "git" $p.step.arguments $p.step_log $worktree `
      $variables
    $p.started = Get-Date
    $p.started_text = Get-Stamp $p.started
    try { $p.started_text = Get-Stamp $p.process.StartTime } catch { }
    Write-Sessions
  } catch {
    Complete-Push $false $_.Exception.Message
  }
}

## the end of a push: logged, counted if it failed (the progress line and
## the last lines of the launcher show the count), and the push asked for in
## the meantime is started
function Complete-Push($ok, $reason) {
  if ($null -eq $script:push) { return }
  $message = $script:push.message
  $script:push = $null
  Write-Sessions
  if ($ok) {
    $script:push_fails = 0
    Write-Log ("push    ok: " + $message)
  } else {
    $script:push_fails += 1
    Write-Log ("push    FAILED: " + $reason + " (logs\git.log); failed" +
               " pushes in a row: " + $script:push_fails)
  }
  if ($script:push_next -ne "") {
    $next = $script:push_next
    $script:push_next = ""
    Start-Push $next
  }
}

## commits and pushes the results worktree and waits for it (at the end of
## the smoke test and of the launcher; the loop uses Start-Push)
function Save-Results($message) {
  Start-Push $message
  while ($null -ne $script:push) {
    Start-Sleep -Seconds 1
    Step-Push
  }
}

## the state of the tasks in one line, with the failed pushes and the
## sessions that have been quiet for long (contract 7.: a session that
## hangs would keep its slot for ever; it is named, not stopped)
function Write-Summary() {
  $tasks = $script:tasks
  $runs = 0
  $runs_all = 0
  foreach ($t in @($tasks | Where-Object { $_.kind -eq "queue" })) {
    $runs += [Math]::Min($t.files, $t.n_runs)
    $runs_all += $t.n_runs
  }
  $running = @($script:sessions.Values | ForEach-Object { $_.task.id } |
               Group-Object | ForEach-Object { $_.Name + " x" + $_.Count })
  $format = "progress tasks {0} of {1} done, {2} failed, {3} blocked; " +
            "runs {4} of {5}; sessions {6} of {7}: {8}"
  $line = ($format -f
           @($tasks | Where-Object { $_.done }).Count,
           $tasks.Count,
           @($tasks | Where-Object { $_.failed }).Count,
           @($tasks | Where-Object { $_.blocked }).Count,
           $runs,
           $runs_all,
           $script:sessions.Count,
           $Slots,
           ($running -join ", "))
  if ($script:push_fails -gt 0) {
    $line = $line + "; failed pushes in a row: " + $script:push_fails
  }
  $quiet = @()
  foreach ($slot in @($script:sessions.Keys | Sort-Object)) {
    $s = $script:sessions[$slot]
    $size = Get-Size $s.log
    if ($size -ne $s.sign_size -or $s.task.files -ne $s.sign_files) {
      $s.sign = Get-Date
      $s.sign_size = $size
      $s.sign_files = $s.task.files
    } elseif (((Get-Date) - $s.sign).TotalHours -ge $QuietHours) {
      $quiet += ("{0} slot {1} pid {2}" -f $s.task.id, $slot, $s.process.Id)
    }
  }
  if ($quiet.Count -gt 0) {
    $line = $line + "; quiet for " + $QuietHours + " h (no output, no new" +
            " run file): " + ($quiet -join ", ")
  }
  Write-Log $line
}

## reads and checks the task table; the rows in (stage, row) order with the
## fields the loop keeps for each task
function Read-Tasks($file, $run_profile) {
  $lines = @(Import-Csv -Path $file)
  if ($lines.Count -eq 0) { throw "the task table $file has no rows" }
  $columns = @("id", "stage", "dataset", "unit", "profile", "validation",
               "final_fit", "script", "args", "kind", "sessions", "max_runs",
               "n_runs", "run_dir", "pattern", "needs")
  $present = @($lines[0].PSObject.Properties | ForEach-Object { $_.Name })
  $missing = @($columns | Where-Object { $present -notcontains $_ })
  if ($missing.Count -gt 0) {
    throw ("the task table $file lacks the columns " + ($missing -join ", "))
  }
  $tasks = @()
  $wrong = @()
  $row = 0
  foreach ($line in $lines) {
    $row += 1
    $task = New-Object PSObject -Property @{
      row = $row
      id = Get-Field $line "id"
      stage = [int](Get-Field $line "stage")
      dataset = Get-Field $line "dataset"
      unit = Get-Field $line "unit"
      profile = Get-Field $line "profile"
      validation = Get-Field $line "validation"
      final_fit = Get-Field $line "final_fit"
      script = Get-Field $line "script"
      args = Get-Field $line "args"
      kind = Get-Field $line "kind"
      sessions = 1
      max_runs = Get-Field $line "max_runs"
      n_runs = 0
      run_dir = Get-Field $line "run_dir"
      pattern = Get-Field $line "pattern"
      needs = @((Get-Field $line "needs") -split ";" |
                ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
      # kept by the loop
      done = $false
      failed = $false
      blocked = $false
      blocked_by = ""
      fails = 0
      last_fail = [datetime]::MinValue
      retry_after = [datetime]::MinValue
      files = 0
      locks = 0
      locks_live = 0
      warned = $false
    }
    if ($task.id -notmatch "^[A-Za-z0-9._-]+$") {
      $wrong += "row ${row}: the id '" + $task.id + "' is not a file name"
    }
    $script_file = $task.script
    if (-not [System.IO.Path]::IsPathRooted($script_file)) {
      $script_file = Join-Path $root $script_file
    }
    if ($task.script -eq "" -or -not (Test-Path $script_file)) {
      $wrong += "row ${row}: no script '" + $task.script + "'"
    }
    if ($task.kind -eq "queue") {
      $task.sessions = [int](Get-Field $line "sessions")
      $task.n_runs = [int](Get-Field $line "n_runs")
      if ($task.sessions -lt 1 -or $task.n_runs -lt 1 -or
          $task.run_dir -eq "" -or $task.pattern -eq "") {
        $wrong += "row ${row}: a queue task needs sessions, n_runs, " +
                  "run_dir and pattern"
      }
      try {
        "run_01.rds" -cmatch $task.pattern | Out-Null
      } catch {
        $wrong += "row ${row}: the pattern '" + $task.pattern + "' is not" +
                  " a regular expression"
      }
      if ($task.pattern -match "\[:[a-z]+:\]") {
        $wrong += "row ${row}: the pattern '" + $task.pattern + "' has a" +
                  " POSIX class of R; write [0-9], [a-z] (contract 2.)"
      }
    } elseif ($task.kind -ne "single") {
      $wrong += "row ${row}: kind '" + $task.kind + "' is not single or queue"
    }
    $tasks += $task
  }
  $ids = @($tasks | ForEach-Object { $_.id })
  if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) {
    $wrong += "the ids are not unique"
  }
  foreach ($task in $tasks) {
    foreach ($need in $task.needs) {
      if ($ids -notcontains $need) {
        $wrong += "task " + $task.id + " needs the unknown task " + $need
      }
    }
  }
  if ($wrong.Count -gt 0) {
    throw ("the task table $file is wrong:`r`n  " + ($wrong -join "`r`n  "))
  }
  # a quick run leaves out the rows of a profile that is not a quick one
  # and, one after the other, the rows that need them (contract 2., profile)
  if ($run_profile -ne "") {
    $out = @($tasks | Where-Object {
      $_.profile -ne "" -and -not $_.profile.StartsWith($run_profile)
    } | ForEach-Object { $_.id })
    $more = $true
    while ($more) {
      $more = $false
      foreach ($task in $tasks) {
        if ($out -contains $task.id) { continue }
        if (@($task.needs | Where-Object { $out -contains $_ }).Count -gt 0) {
          $out += $task.id
          $more = $true
        }
      }
    }
    if ($out.Count -gt 0) {
      Write-Log ("left out of the " + $run_profile + " run (another" +
                 " profile): " + ($out -join ", "))
      $tasks = @($tasks | Where-Object { $out -notcontains $_.id })
    }
  }
  return @($tasks | Sort-Object -Property stage, row)
}

## one run of the task table: under a profile ("" or "quick"), in its state
## folder; given_table: a table to use instead of a generated one. Leaves
## the tasks in $script:tasks
function Invoke-Run($name, $run_profile, $state_folder, $given_table,
                    $push_stages) {
  $script:state = $state_folder
  $script:tasks = @()
  $script:sessions = @{}                 # slot -> running session
  $logs = Join-Path $state_folder "logs"
  $done_folder = Join-Path $state_folder "done"
  $failed_folder = Join-Path $state_folder "failed"
  foreach ($folder in @($state_folder, $logs, $done_folder, $failed_folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
  }
  $script:log_file = Join-Path $state_folder "launch.log"
  Write-Log ("==== " + $name + ": " + $Slots + " slots, RUN_ROOT " +
             $run_root + ", parts " + $parts_text)

  ## a task given up by an earlier launch is tried again
  Remove-Item -Path (Join-Path $failed_folder "*.failed") -Force

  ## the task table: the given one, or written now by the tasks script
  $table = Join-Path $state_folder "tasks.csv"
  if ($given_table -ne "") {
    if ((Resolve-Path $given_table).Path -ne $table) {
      Copy-Item -Path $given_table -Destination $table -Force
    }
  } else {
    $script_file = $TasksScript
    if (-not [System.IO.Path]::IsPathRooted($script_file)) {
      $script_file = Join-Path $root $script_file
    }
    if (-not (Test-Path $script_file)) {
      throw ("the script that writes the task table is not there: " +
             $script_file)
    }
    Remove-Item -Path $table -Force -ErrorAction SilentlyContinue
    $variables = @{ RUN_ROOT = $run_root_r; R_CONFIG_ACTIVE = $run_profile;
                    FINAL_RUN_PARTS = ($part_names -join "+");
                    DATASET = ""; UNIT = ""; VALIDATION = ""; FINAL_FIT = "";
                    RUN_SLOT = ""; RUN_MAX = ""; RUN_DIR = "" }
    $table_log = Join-Path $logs "tasks_table.log"
    $arguments = "`"" + $TasksScript + "`""
    $process = Start-Logged $rscript $arguments $table_log $root $variables
    $code = Wait-Logged $process 3600
    if ($code -ne 0 -or -not (Test-Path $table)) {
      $tail = @(Get-Content -Path $table_log -Tail 30) -join "`r`n"
      throw ("the task table was not written: Rscript `"$TasksScript`" ended" +
             " with exit code $code; the end of $table_log :`r`n$tail")
    }
  }
  $tasks = @(Read-Tasks $table $run_profile)
  $script:tasks = $tasks
  $by_id = @{}
  foreach ($t in $tasks) { $by_id[$t.id] = $t }
  $stages = @($tasks | ForEach-Object { $_.stage } | Sort-Object -Unique)

  ## what is done already: markers of the single tasks, run files of the
  ## queue tasks; the stages complete at the start are not pushed again
  foreach ($t in $tasks) {
    if ($t.kind -eq "single") {
      $t.done = Test-Path (Join-Path $done_folder ($t.id + ".done"))
    } else {
      Update-Count $t $false
    }
  }
  $stages_done = @{}
  foreach ($stage in $stages) {
    $left = @($tasks | Where-Object { $_.stage -eq $stage -and -not $_.done })
    if ($left.Count -eq 0) { $stages_done[$stage] = $true }
  }
  Write-Summary

  $errors = 0
  $next_summary = (Get-Date).AddMinutes($SummaryMinutes)
  $next_push = (Get-Date).AddHours($PushHours)
  while ($true) {
    try {
      ##########################################
      #########  sessions that ended
      ##########################################
      foreach ($slot in @($script:sessions.Keys | Sort-Object)) {
        $s = $script:sessions[$slot]
        if (-not $s.process.HasExited) { continue }
        $script:sessions.Remove($slot)
        Write-Sessions
        $t = $s.task
        $code = $s.process.ExitCode
        $seconds = [int]((Get-Date) - $s.started).TotalSeconds
        $reason = ""
        if ($t.kind -eq "single") {
          Write-Log ("end     {0} slot {1}: exit code {2}, {3} s" -f
                     $t.id, $slot, $code, $seconds)
          if ($code -eq 0) {
            $t.done = $true
            $t.fails = 0
            $marker = Join-Path $done_folder ($t.id + ".done")
            $text = (Get-Stamp (Get-Date)) + ", " + $seconds + " s"
            Set-Content -Path $marker -Value $text -Encoding ASCII
            Write-Log ("done    " + $t.id)
          } else {
            $reason = "exit code $code"
          }
        } else {
          $format = "end     {0} slot {1}: exit code {2}, {3} s; " +
                    "run files {4} of {5}"
          $files_before = $t.files
          Update-Count $t $false
          Write-Log ($format -f
                     $t.id, $slot, $code, $seconds, $t.files, $t.n_runs)
          if ($t.done -and $files_before -lt $t.n_runs) {
            Write-Log ("done    " + $t.id)
          }
          if ($code -ne 0) {
            $reason = "exit code $code"
          } elseif ($t.files -le $s.files -and -not $t.done) {
            $reason = "ended without a new run file"
          }
        }
        if ($reason -eq "") { continue }
        if ($code -ne 0 -and (Get-Size $s.log) -le $s.log_size) {
          # cmd.exe could not open the log: Rscript was never started
          $reason = $reason + ", nothing reached its log (in use by" +
                    " another process?)"
        }

        ## a failure (contract 7.): the locks of the slot go; it counts if
        ## the session was started after the last counted failure
        $lock_folder = $run_root
        if ($t.run_dir -ne "") { $lock_folder = Join-Path $run_root $t.run_dir }
        Remove-Locks $lock_folder $slot ""
        if ($s.started -le $t.last_fail) {
          $format = "failure {0} slot {1}: {2} (started before the last " +
                    "failure: not counted)"
          Write-Log ($format -f $t.id, $slot, $reason)
          continue
        }
        $t.fails += 1
        $t.last_fail = Get-Date
        if ($t.fails -lt $max_fails) {
          $wait = $retry_waits[[Math]::Min($t.fails, $retry_waits.Count) - 1]
          $t.retry_after = (Get-Date).AddSeconds($wait)
          $format = "failure {0} slot {1}: {2} (failure {3} of {4}; next " +
                    "try after {5} s)"
          Write-Log ($format -f
                     $t.id, $slot, $reason, $t.fails, $max_fails, $wait)
          continue
        }
        if ($t.done) { continue }
        $t.failed = $true
        $tail = @()
        try { $tail = @(Get-Content -Path $s.log -Tail 30) } catch { }
        $marker = Join-Path $failed_folder ($t.id + ".failed")
        $text = @(("task " + $t.id + " failed " + $max_fails + " times in a" +
                   " row: " + $reason),
                  ("time: " + (Get-Stamp (Get-Date))),
                  ("the last lines of " + $s.log + ":"),
                  "") + $tail
        Set-Content -Path $marker -Value $text -Encoding ASCII
        Write-Log ("FAILED  {0}: {1}, {2} times in a row; see {3}" -f
                   $t.id, $reason, $max_fails, $marker)
      }

      ##########################################
      #########  what is done, what is blocked
      ##########################################
      ## the run files of the queue tasks with running sessions
      $running_ids = @($script:sessions.Values |
                       ForEach-Object { $_.task.id } | Sort-Object -Unique)
      foreach ($id in $running_ids) {
        if ($by_id[$id].kind -eq "queue") { Update-Count $by_id[$id] $true }
      }
      ## blocked: a task that needs a failed or a blocked task
      $before = @($tasks | Where-Object { $_.blocked } |
                  ForEach-Object { $_.id })
      foreach ($t in $tasks) { $t.blocked = $false }
      $more = $true
      while ($more) {
        $more = $false
        foreach ($t in $tasks) {
          if ($t.done -or $t.failed -or $t.blocked) { continue }
          foreach ($need in $t.needs) {
            $n = $by_id[$need]
            if (-not $n.done -and ($n.failed -or $n.blocked)) {
              $t.blocked = $true
              $t.blocked_by = $need
              $more = $true
            }
          }
        }
      }
      foreach ($t in $tasks) {
        if ($t.blocked -and $before -notcontains $t.id) {
          Write-Log ("blocked " + $t.id + ": it needs " + $t.blocked_by)
        }
      }

      ##########################################
      #########  sessions for the free slots (contract 6.)
      ##########################################
      foreach ($slot in 1..$Slots) {
        if ($script:sessions.ContainsKey($slot)) { continue }
        $next = $null
        foreach ($t in $tasks) {
          if ($t.done -or $t.failed -or $t.blocked) { continue }
          if ($t.retry_after -gt (Get-Date)) { continue }
          $waits_for = @($t.needs | Where-Object { -not $by_id[$_].done })
          if ($waits_for.Count -gt 0) { continue }
          $running = @($script:sessions.Values |
                       Where-Object { $_.task.id -eq $t.id }).Count
          if ($t.kind -eq "single") {
            if ($running -eq 0) { $next = $t; break }
            continue
          }
          if ($running -ge $t.sessions) { continue }
          Update-Count $t $true
          if ($t.done) { continue }
          if ($running -eq 0 -and $t.locks -gt 0) {
            # no session of the task is running: its locks are left-overs
            Remove-Locks (Join-Path $run_root $t.run_dir) 0 $t.pattern
            Update-Count $t $true
          }
          # the runs still to be saved, without those under a lock that no
          # running session holds: one session each at the most
          $to_save = $t.n_runs - $t.files - ($t.locks - $t.locks_live)
          if ($running -lt [Math]::Min($t.sessions, $to_save)) {
            $next = $t
            break
          }
        }
        if ($null -eq $next) { break }

        ## a session of task $next in this slot (contract 4.)
        $t = $next
        $log = Join-Path $logs ($t.id + "_slot" + $slot + ".log")
        $text = "==== " + (Get-Stamp (Get-Date)) + " start " +
                $t.id + " slot " + $slot
        try { Add-Content -Path $log -Value $text -Encoding ASCII } catch { }
        $log_size = Get-Size $log
        $session_profile = $t.profile
        if ($session_profile -eq "") { $session_profile = $run_profile }
        $max_runs = ""
        if ($t.kind -eq "queue") { $max_runs = $t.max_runs }
        $variables = @{
          DATASET = $t.dataset
          UNIT = $t.unit
          R_CONFIG_ACTIVE = $session_profile
          VALIDATION = $t.validation
          FINAL_FIT = $t.final_fit
          RUN_ROOT = $run_root_r
          RUN_SLOT = [string]$slot
          RUN_MAX = $max_runs
          RUN_WORKERS = [string]$Slots
          RUN_DIR = ""
          OMP_NUM_THREADS = "1"
          MKL_NUM_THREADS = "1"
          OPENBLAS_NUM_THREADS = "1"
          TF_NUM_INTRAOP_THREADS = "1"
          TF_NUM_INTEROP_THREADS = "1"
          TF_CPP_MIN_LOG_LEVEL = "2"
        }
        foreach ($name in $python_variables.Keys) {
          $variables[$name] = $python_variables[$name]
        }
        $arguments = "`"" + $t.script + "`" " + $t.args
        $process = Start-Logged $rscript $arguments $log $root $variables
        $started = Get-Date
        $started_text = Get-Stamp $started
        try { $started_text = Get-Stamp $process.StartTime } catch { }
        $script:sessions[$slot] = New-Object PSObject -Property @{
          task = $t
          process = $process
          started = $started
          started_text = $started_text
          files = $t.files
          log = $log
          log_size = $log_size
          # the last sign of life (Write-Summary)
          sign = $started
          sign_size = $log_size
          sign_files = $t.files
        }
        Write-Sessions
        Write-Log ("start   {0} slot {1} pid {2}" -f $t.id, $slot, $process.Id)
      }

      ##########################################
      #########  stages, the end, the summary, the pushes
      ##########################################
      ## a stage is complete when all its tasks are done: push
      foreach ($stage in $stages) {
        if ($stages_done.ContainsKey($stage)) { continue }
        $left = @($tasks | Where-Object { $_.stage -eq $stage -and
                                          -not $_.done })
        if ($left.Count -eq 0) {
          $stages_done[$stage] = $true
          Write-Log ("stage   " + $stage + " complete")
          if ($push_stages) {
            Start-Push ("stage " + $stage + " complete")
            $next_push = (Get-Date).AddHours($PushHours)
          }
        }
      }
      if ($script:sessions.Count -eq 0) {
        $left = @($tasks | Where-Object { -not $_.done -and -not $_.failed -and
                                          -not $_.blocked })
        if ($left.Count -eq 0) { break }
        $waiting = @($left | Where-Object { $_.retry_after -gt (Get-Date) })
        if ($waiting.Count -eq 0) {
          # nothing runs, nothing waits for another try, nothing can start:
          # the needs of these tasks cannot be met
          foreach ($t in $left) {
            $t.blocked = $true
            $t.blocked_by = ($t.needs -join ";")
            Write-Log ("blocked " + $t.id + ": it cannot start, needs " +
                       $t.blocked_by)
          }
          break
        }
      }
      if ((Get-Date) -ge $next_summary) {
        Write-Summary
        $next_summary = (Get-Date).AddMinutes($SummaryMinutes)
      }
      if ($push_stages -and (Get-Date) -ge $next_push) {
        Start-Push ("progress after " + $PushHours + " hours")
        $next_push = (Get-Date).AddHours($PushHours)
      }
      ## the push that is under way goes on beside the sessions
      Step-Push
      $errors = 0
    } catch {
      # an error in one round (a file in use, say) must not end the run;
      # the same trouble 20 rounds in a row does
      $errors += 1
      Write-Log ("ERROR   in the launcher, line " +
                 $_.InvocationInfo.ScriptLineNumber + ": " +
                 $_.Exception.Message)
      if ($errors -ge 20) { throw }
    }
    Start-Sleep -Seconds $PollSeconds
  }
  Write-Sessions
  Write-Summary
}

## the tasks of the last Invoke-Run that are not done, with the reason, as
## lines of text
function Get-NotDone() {
  $lines = @()
  foreach ($t in $script:tasks) {
    if ($t.done) { continue }
    if ($t.failed) {
      $marker = Join-Path $script:state ("failed\" + $t.id + ".failed")
      $lines += "failed:  " + $t.id + "  (" + $marker + ")"
    } else {
      $lines += "blocked: " + $t.id + "  (it needs " + $t.blocked_by + ")"
    }
  }
  return $lines
}

##########################################
#########  folders, one launcher only
##########################################

## the project root (two folders above this script), RUN_ROOT and the state
## folders
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$default_root = ($RunRoot -eq "")
if ($default_root) {
  $RunRoot = Join-Path $root "..\Masters-Research-R-results\results"
}
if (-not [System.IO.Path]::IsPathRooted($RunRoot)) {
  $RunRoot = Join-Path (Get-Location).Path $RunRoot
}
$run_root = [System.IO.Path]::GetFullPath($RunRoot).TrimEnd("\")
$run_root_r = $run_root.Replace("\", "/")
$state_final = Join-Path $run_root "final-run"
$state_quick = Join-Path $state_final "quick"
$script:log_file = Join-Path $state_final "launch.log"
$script:state = $state_final
$script:tasks = @()
$script:sessions = @{}
$script:push = $null           # the push that is under way
$script:push_next = ""         # the push asked for in the meantime
$script:push_fails = 0         # pushes that failed in a row

if ($Slots -lt 1 -or ($Profile -ne "" -and $Profile -ne "quick")) {
  Write-Host "-Slots must be 1 or more and -Profile `"`" or `"quick`"."
  exit 3
}
$retry_waits = @($RetrySeconds -split "," | ForEach-Object { [int]$_ })
## the parts of the task table this computer runs (-Parts); the tasks
## script knows the names and stops at one that is none
$part_names = @($Parts.ToLowerInvariant() -split "[+,; ]+" |
                  Where-Object { $_ -ne "" } | Sort-Object -Unique)
if ($part_names -contains "all") { $part_names = @() }
$parts_text = "all"
if ($part_names.Count -gt 0) { $parts_text = $part_names -join "+" }

## the default RUN_ROOT is the results worktree that setup_vm.ps1 makes:
## without it this launcher would make a plain folder in its place, push
## nothing, and the setup could no longer make the worktree there
$parent = Split-Path $run_root -Parent
if ($default_root -and -not $NoPush -and
    -not (Test-Path (Join-Path $parent ".git"))) {
  Write-Host ("The results worktree is not there: " + $parent)
  Write-Host "Run setup_vm.ps1 first (it makes it). For a run whose results"
  Write-Host "are not pushed give -NoPush, or -RunRoot <another folder>."
  exit 3
}

## one launcher only for a RUN_ROOT (contract 11.): Windows gives a named
## mutex to one process, also when two launchers start in the same moment
## (the scheduled task and a start by hand). It is free again when the
## launcher ends, however it ends
$mutex_name = "Global\final-run-" +
              ($run_root.ToLower() -replace "[^a-z0-9]", "_")
if ($mutex_name.Length -gt 240) {
  $mutex_name = "Global\final-run-" +
                $mutex_name.Substring($mutex_name.Length - 220)
}
$mutex = $null
$mine = $false
try {
  $mutex = New-Object System.Threading.Mutex($false, $mutex_name)
  try {
    $mine = $mutex.WaitOne(0)
  } catch {
    # its launcher was stopped while another process looked at it: free
    $base = $_.Exception.GetBaseException()
    $mine = ($base -is [System.Threading.AbandonedMutexException])
  }
} catch {
  # no access: the mutex of a launcher started as administrator or by
  # another user
}
if (-not $mine) {
  Write-Host ("Another launcher is running for " + $run_root + ".")
  Write-Host "Stop it with stop.ps1 first (in a PowerShell opened as"
  Write-Host "administrator if it was started in one)."
  exit 2
}

## launcher.pid holds the process id and start time of this launcher, for
## stop.ps1
New-Item -ItemType Directory -Path $state_final -Force | Out-Null
$pid_file = Join-Path $state_final "launcher.pid"
$own_start = Get-Stamp (Get-Process -Id $PID).StartTime
Set-Content -Path $pid_file -Value ("$PID," + $own_start) -Encoding ASCII

$exit_code = 3
$worktree = ""
$git_dir = ""
$code_commit = "unknown"
try {
  Write-Log ("==== launcher started, process " + $PID)

  ## two settings of Windows for a program nobody watches. (1) An R session
  ## that crashes must end at once: by default Windows first writes an error
  ## report (half a minute) and may show a "has stopped working" window that
  ## waits for a click. The error mode set here passes to the sessions.
  ## (2) Clicking in a console window selects text and holds every program
  ## that writes to it: this launcher would stand still, unnoticed. The
  ## selection by mouse (QuickEdit) is switched off
  try {
    $import = '[DllImport("kernel32.dll")] public static extern '
    $signature = $import + 'uint SetErrorMode(uint mode); ' +
                 $import + 'IntPtr GetStdHandle(int handle); ' +
                 $import + 'bool GetConsoleMode(IntPtr handle, out uint mode); ' +
                 $import + 'bool SetConsoleMode(IntPtr handle, uint mode);'
    $windows = Add-Type -MemberDefinition $signature -Name "Windows" `
      -Namespace "FinalRun" -PassThru
    # SEM_FAILCRITICALERRORS (1) and SEM_NOGPFAULTERRORBOX (2)
    $windows::SetErrorMode(3) | Out-Null
    $handle = $windows::GetStdHandle(-10)          # the console input
    [uint32]$mode = 0
    if ($windows::GetConsoleMode($handle, [ref]$mode)) {
      # ENABLE_QUICK_EDIT_MODE (64) off, ENABLE_EXTENDED_FLAGS (128) on
      [uint32]$new_mode = ($mode -band 4294967231) -bor 128
      $windows::SetConsoleMode($handle, $new_mode) | Out-Null
    }
  } catch {
    Write-Log ("note: the error mode and QuickEdit were not set: " +
               $_.Exception.Message)
  }
  Write-Host "Do not select text in this window (it would hold the launcher;"
  Write-Host "Esc releases it). Progress: launch.log, `"final run status.R`"."

  ##########################################
  #########  R, Python, git
  ##########################################

  ## R 4.6.1: the registry entry of its installer, else the default folder;
  ## bin\x64\Rscript.exe is the process that works
  $rscript = $Rscript
  if ($rscript -eq "") {
    $r_home = "C:\Program Files\R\R-4.6.1"
    foreach ($key in @("HKLM:\SOFTWARE\R-core\R\4.6.1",
                       "HKLM:\SOFTWARE\R-core\R64\4.6.1",
                       "HKCU:\SOFTWARE\R-core\R\4.6.1",
                       "HKCU:\SOFTWARE\R-core\R64\4.6.1")) {
      try {
        $r_home = (Get-ItemProperty -Path $key).InstallPath
        break
      } catch { }
    }
    $rscript = Join-Path $r_home "bin\x64\Rscript.exe"
  }
  if (-not (Test-Path $rscript)) {
    throw ("Rscript not found: " + $rscript + ". Install R 4.6.1 or give" +
           " -Rscript <path of bin\x64\Rscript.exe>.")
  }
  $r_version = (& $rscript -e "cat(R.version.string)") -join " "

  ## the Python of the sessions (contract 10.): the environment that
  ## setup_vm.ps1 built, named to reticulate in every session
  $python_exe = $Python
  $python_variables = @{}
  if ($python_exe -ne "uv") {
    if ($python_exe -eq "") {
      $python_exe = Join-Path $root `
        "..\Masters-Research-R-python\env\Scripts\python.exe"
    }
    if (-not [System.IO.Path]::IsPathRooted($python_exe)) {
      $python_exe = Join-Path (Get-Location).Path $python_exe
    }
    $python_exe = [System.IO.Path]::GetFullPath($python_exe)
    if (-not (Test-Path $python_exe)) {
      throw ("The Python environment of the fits is not there: " + $python_exe +
             ". Run setup_vm.ps1 first (it builds it), or give -Python" +
             " <path of its python.exe>. -Python uv lets every R session" +
             " resolve its Python packages with uv instead (that needs the" +
             " internet at every session start).")
    }
    $python_variables = @{
      RETICULATE_PYTHON = $python_exe
      RETICULATE_USE_MANAGED_VENV = "no"
      RETICULATE_CHECK_REQUIRED_PACKAGES = "false"
      KERAS_PYTHON = ""
    }
  }

  ## R reads the file .Renviron of the project root (if there is none: of
  ## the user's R home) at the start of every session and lets it win over
  ## the variables the launcher sets or removes (contract 4.): it must not
  ## name one of them
  $session_names = @("DATASET", "UNIT", "R_CONFIG_ACTIVE", "VALIDATION",
                     "FINAL_FIT", "RUN_ROOT", "RUN_SLOT", "RUN_MAX",
                     "RUN_WORKERS", "RUN_DIR", "OMP_NUM_THREADS",
                     "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS",
                     "TF_NUM_INTRAOP_THREADS", "TF_NUM_INTEROP_THREADS",
                     "TF_CPP_MIN_LOG_LEVEL") + @($python_variables.Keys)
  $r_user = (& $rscript -e "cat(path.expand('~'))") -join ""
  foreach ($file in @((Join-Path $root ".Renviron"),
                      (Join-Path $r_user ".Renviron"))) {
    if (-not (Test-Path $file)) { continue }
    $set = @()
    foreach ($line in @(Get-Content -Path $file)) {
      $name = ($line -split "=")[0].Trim()
      if ($line -match "=" -and $session_names -contains $name) {
        $set += $name
      }
    }
    if ($set.Count -gt 0) {
      throw ("The file " + $file + " sets " + ($set -join ", ") + ": R" +
             " reads it at the start of every session and would use its" +
             " values instead of those of the launcher. Take these lines" +
             " out of the file and start launch.ps1 again.")
    }
    break                      # R reads the first of the two only
  }

  ## the code commit, for the commit messages and run_info.txt
  $code_commit = "unknown"
  $has_git = ($null -ne (Get-Command git -ErrorAction SilentlyContinue))
  if ($has_git) {
    $code_commit = (& git -C $root rev-parse --short HEAD) -join ""
    if ($code_commit -eq "") {
      $code_commit = "unknown"
      Write-Log ("note: git cannot read the project; try: git -C `"" +
                 $root + "`" status")
    }
    if (@(& git -C $root status --porcelain).Count -gt 0) {
      $code_commit = $code_commit + " with uncommitted changes"
    }
  }

  ## the results worktree (contract 8.); without one nothing is pushed
  $git_log = Join-Path $state_final "logs\git.log"
  if ($has_git -and -not $NoPush -and
      (Split-Path $run_root -Leaf) -eq "results") {
    if ((Test-Path (Join-Path $parent ".git")) -and $parent -ne $root) {
      $worktree = $parent
    }
  }
  if ($worktree -eq "") {
    Write-Log ("the results are NOT committed and pushed (-NoPush, no" +
               " git, or RUN_ROOT is not the folder results of a git" +
               " worktree)")
  } else {
    Write-Log ("results worktree: " + $worktree)
    # git must be able to read it: it refuses a folder that was made as
    # administrator ("dubious ownership") until it is named a safe one
    $git_dir = (& git -C $worktree rev-parse --absolute-git-dir) -join ""
    if ($git_dir -eq "") {
      $refused = $worktree
      $worktree = ""
      throw ("git cannot read the results worktree " + $refused + ". Try:" +
             " git -C `"" + $refused + "`" status . If it reports dubious" +
             " ownership (the folder was made as administrator), run: git" +
             " config --global --add safe.directory `"" +
             $refused.Replace("\", "/") + "`" , then start launch.ps1 again.")
    }
  }

  ##########################################
  #########  left-overs of an earlier launcher
  ##########################################

  ## its sessions that still run are stopped, then no session is running:
  ## every lock directory and temporary file under RUN_ROOT is a left-over
  Stop-Sessions $state_final
  Stop-Sessions $state_quick
  Remove-Locks $run_root 0 ""
  foreach ($folder in @(Get-Folders $run_root)) {
    try {
      foreach ($file in [System.IO.Directory]::GetFiles($folder, "*.tmp")) {
        if ($file.EndsWith(".tmp")) {
          Remove-Item -LiteralPath $file -Force
          Write-Log ("removed " + $file)
        }
      }
    } catch {
      Write-Log ("could not clear " + $folder + ": " + $_.Exception.Message)
    }
  }
  if ($worktree -ne "") {
    New-Item -ItemType Directory -Path (Split-Path $git_log -Parent) -Force |
      Out-Null
    # the .gitignore and .gitattributes of the results branch, if it has
    # none: without them locks and models would be committed
    foreach ($name in @("gitignore", "gitattributes")) {
      $file = Join-Path $worktree ("." + $name)
      $template = Join-Path $PSScriptRoot ("results_" + $name + ".txt")
      if (-not (Test-Path $file)) {
        Copy-Item -Path $template -Destination $file
        Write-Log ("wrote " + $file)
      }
    }
  }

  ##########################################
  #########  this launch
  ##########################################

  $processor = "unknown"
  $memory = "unknown"
  try {
    $processor = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $bytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $memory = [Math]::Round($bytes / 1GB)
  } catch { }
  $text = @(("launch: " + (Get-Stamp (Get-Date))),
            ("computer: " + $env:COMPUTERNAME),
            ("processor: " + $processor),
            ("logical processors: " + [Environment]::ProcessorCount),
            ("memory (GB): " + $memory),
            ("R: " + $r_version),
            ("Rscript: " + $rscript),
            ("Python: " + $python_exe),
            ("code commit: " + $code_commit),
            ("slots: " + $Slots),
            ("profile: '" + $Profile + "', skip smoke: " + $SkipSmoke +
             ", tasks file: '" + $TasksFile + "'"),
            ("parts: " + $parts_text),
            "")
  Add-Content -Path (Join-Path $state_final "run_info.txt") -Value $text `
    -Encoding ASCII
  Write-Log ("R: " + $r_version + "; Python: " + $python_exe +
             "; code commit: " + $code_commit)

  ##########################################
  #########  smoke test (contract 9.)
  ##########################################

  ## of some parts (-Parts) it has a marker of its own, and the marker of
  ## the whole table stands for it
  $smoke_all = Join-Path $state_quick "smoke.done"
  $smoke_done = $smoke_all
  if ($part_names.Count -gt 0) {
    $smoke_done = Join-Path $state_quick `
      ("smoke." + ($part_names -join "-") + ".done")
  }
  $smoke_failed = Join-Path $state_quick "smoke_failed.txt"
  $smoke_ok = $true
  if (-not $SkipSmoke -and $Profile -eq "" -and $TasksFile -eq "" -and
      -not (Test-Path $smoke_done) -and -not (Test-Path $smoke_all)) {
    Write-Log "smoke test: every task under the quick profile first"
    $problem = ""
    try {
      Invoke-Run "smoke test" "quick" $state_quick "" $false
    } catch {
      $problem = $_.Exception.Message
    }
    $not_done = @(Get-NotDone)
    $script:log_file = Join-Path $state_final "launch.log"
    if ($problem -eq "" -and $not_done.Count -eq 0) {
      $text = (Get-Stamp (Get-Date)) + ", code commit " + $code_commit
      Set-Content -Path $smoke_done -Value $text -Encoding ASCII
      Remove-Item -Path $smoke_failed -Force -ErrorAction SilentlyContinue
      Write-Log "smoke test passed"
      Save-Results "smoke test passed"
    } else {
      $smoke_ok = $false
      $text = @(("The smoke test (quick profile) failed; the final run was" +
                 " not started."),
                ("time: " + (Get-Stamp (Get-Date)) +
                 ", code commit: " + $code_commit),
                "")
      if ($problem -ne "") { $text += @($problem, "") }
      $text += $not_done
      foreach ($t in @($script:tasks | Where-Object { $_.failed })) {
        $marker = Join-Path $state_quick ("failed\" + $t.id + ".failed")
        $text += @("", "---------------------------------------------")
        $text += @(Get-Content -Path $marker)
      }
      Set-Content -Path $smoke_failed -Value $text -Encoding ASCII
      Write-Log ("SMOKE TEST FAILED: see " + $smoke_failed)
      foreach ($line in $not_done) { Write-Log $line }
      if ($problem -ne "") { Write-Log $problem }
      Save-Results "smoke test FAILED"
      Write-Host ""
      Write-Host "The smoke test failed: the final run was NOT started."
      Write-Host ("Summary: " + $smoke_failed)
      Write-Host ("Logs:    " + (Join-Path $state_quick "logs"))
      $exit_code = 1
    }
  }

  ##########################################
  #########  the run
  ##########################################

  if ($smoke_ok) {
    ## when all is done, failed or blocked, the failed tasks get another
    ## round (contract 7.): a cause that has passed by then (no network, no
    ## memory left) costs no more than the wait
    $round = 1
    while ($true) {
      if ($Profile -eq "quick") {
        Invoke-Run "quick run" "quick" $state_quick $TasksFile $true
      } else {
        Invoke-Run "final run" "" $state_final $TasksFile $true
      }
      $n_failed = @($script:tasks | Where-Object { $_.failed }).Count
      if ($n_failed -eq 0 -or $round -ge $Rounds) { break }
      $round += 1
      $wait = $retry_waits[$retry_waits.Count - 1]
      Write-Log ("==== " + $n_failed + " tasks failed: round " + $round +
                 " of " + $Rounds + " tries them again after " + $wait + " s")
      Start-Sleep -Seconds $wait
    }
    $not_done = @(Get-NotDone)
    $result = ("{0} of {1} tasks done, {2} failed, {3} blocked" -f
               @($script:tasks | Where-Object { $_.done }).Count,
               $script:tasks.Count,
               @($script:tasks | Where-Object { $_.failed }).Count,
               @($script:tasks | Where-Object { $_.blocked }).Count)
    Write-Log ("==== finished: " + $result)
    foreach ($line in $not_done) { Write-Log $line }
    Save-Results ("finished, " + $result)
    Write-Host ""
    if ($not_done.Count -eq 0) {
      Write-Host ("ALL DONE: " + $result + ".")
      $exit_code = 0
    } else {
      Write-Host ("NOT ALL DONE: " + $result + ".")
      foreach ($line in $not_done) { Write-Host ("  " + $line) }
      Write-Host "Start launch.ps1 again to try the failed tasks once more."
      $exit_code = 1
    }
    Write-Host ("Events: " + (Join-Path $script:state "launch.log"))
    Write-Host ("Logs:   " + (Join-Path $script:state "logs"))
  }
  ## where the results are: the last push tells
  if ($worktree -eq "") {
    Write-Host "Results: not committed and pushed (see the start of the log)."
  } elseif ($script:push_fails -gt 0) {
    Write-Host ("The results are NOT all on GitHub: the last push failed" +
                " (" + $git_log + ").")
    Write-Host "Start launch.ps1 again to push them."
    Write-Log "==== the results are NOT all on GitHub: the last push failed"
  } else {
    Write-Host "Results: committed and pushed."
  }
} catch {
  $exit_code = 3
  Write-Log ("FATAL   the launcher stopped, line " +
             $_.InvocationInfo.ScriptLineNumber + ": " + $_.Exception.Message)
  Save-Results "the launcher stopped with an error"
} finally {
  ## however the launcher ends (the end, an error, Ctrl+C): no session and
  ## no git command is left running and the next launcher may start
  foreach ($s in @($script:sessions.Values)) {
    Stop-Tree $s.process.Id | Out-Null
    Write-Log ("stopped " + $s.task.id + " pid " + $s.process.Id)
  }
  if ($null -ne $script:push -and $null -ne $script:push.process) {
    Stop-Tree $script:push.process.Id | Out-Null
    Write-Log ("stopped git pid " + $script:push.process.Id)
  }
  Remove-Item -Path $pid_file -Force -ErrorAction SilentlyContinue
  try { $mutex.ReleaseMutex() } catch { }
}
exit $exit_code
