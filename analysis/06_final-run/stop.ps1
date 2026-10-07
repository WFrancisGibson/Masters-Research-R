##########################################
#########  final run: stops the launcher and its R sessions
#########  own design (Windows PowerShell 5.1)
##########################################

## from the project root:
##   powershell -ExecutionPolicy Bypass -File "analysis\06_final-run\stop.ps1"
## -RunRoot as for launch.ps1 (default: ..\Masters-Research-R-results\results
## beside the project). Nothing is lost but the runs being fitted at this
## moment: the state stays, and launch.ps1 resumes where the run stood.
## A launcher that was started in a PowerShell opened as administrator can
## only be stopped from one: stop.ps1 then says so and ends with exit code 1.
##
## exit code: 0 nothing of the run is running any more; 1 a process could
## not be stopped

param(
  [string]$RunRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

## times are written as launch.ps1 writes them, under every regional format
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
[System.Threading.Thread]::CurrentThread.CurrentCulture = $invariant
$time_format = "yyyy-MM-dd HH:mm:ss"

## TRUE if the process with this id is the one started at this time (Windows
## uses a process id again). If the start time cannot be read (a process of
## an administrator or of another user) the name of the program decides
function Test-Process($id, $started, $name) {
  $process = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($null -eq $process) { return $false }
  try {
    return ($process.StartTime.ToString($time_format, $invariant) -eq $started)
  } catch {
    return ($process.ProcessName -eq $name)
  }
}

## stops a process and the processes it started, and waits up to 10 s for
## it to go; TRUE if it is gone
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

## RUN_ROOT and the state folders, as in launch.ps1
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($RunRoot -eq "") {
  $RunRoot = Join-Path $root "..\Masters-Research-R-results\results"
}
if (-not [System.IO.Path]::IsPathRooted($RunRoot)) {
  $RunRoot = Join-Path (Get-Location).Path $RunRoot
}
$run_root = [System.IO.Path]::GetFullPath($RunRoot).TrimEnd("\")
$state_final = Join-Path $run_root "final-run"
$state_quick = Join-Path $state_final "quick"
$stopped = 0
$alive = @()

## the launcher first, so that it starts no new session: launcher.pid holds
## its process id and start time. Its sessions are its children and stop
## with it. The file stays while the launcher is running
$pid_file = Join-Path $state_final "launcher.pid"
if (Test-Path $pid_file) {
  $old = @(([string](Get-Content -Path $pid_file -TotalCount 1)) -split ",")
  if ($old.Count -eq 2 -and $old[0] -match "^[0-9]+$" -and
      (Test-Process $old[0] $old[1] "powershell")) {
    if (Stop-Tree $old[0]) {
      Write-Host ("Stopped the launcher (process " + $old[0] + ").")
      $stopped += 1
    } else {
      $alive += $old[0]
    }
  }
  if ($alive.Count -eq 0) { Remove-Item -Path $pid_file -Force }
}

## then the sessions (and the git command, slot 0) listed in sessions.csv
## that still run: a launcher that was closed by hand leaves them. Not while
## the launcher runs on: it would start them again. A file cut off by a
## power cut is passed over
foreach ($state in @($state_final, $state_quick)) {
  $file = Join-Path $state "sessions.csv"
  if ($alive.Count -gt 0 -or -not (Test-Path $file)) { continue }
  try {
    foreach ($line in @(Import-Csv -Path $file)) {
      $id = [string]$line.pid
      if ($id -notmatch "^[0-9]+$") { continue }
      if (-not (Test-Process $id ([string]$line.started) "cmd")) { continue }
      if (Stop-Tree $id) {
        if ($line.id -eq "git") {
          Write-Host ("Stopped the git command (process " + $id + ").")
        } else {
          Write-Host ("Stopped the R session of task " + $line.id +
                      " (slot " + $line.slot + ", process " + $id + ").")
        }
        $stopped += 1
      } else {
        # no right to stop it: the same holds for the others
        $alive += $id
        break
      }
    }
  } catch {
    Write-Host ("Not readable, left aside: " + $file)
  }
}

if ($alive.Count -gt 0) {
  Write-Host ""
  Write-Host ("COULD NOT stop process " + ($alive -join ", ") + ": the run" +
              " is still going.")
  Write-Host "Run stop.ps1 again from a PowerShell opened as administrator"
  Write-Host "(the launcher was started in one)."
  exit 1
}
if ($stopped -eq 0) {
  Write-Host ("No launcher and no R session of the final run is running for " +
              $run_root + ".")
} else {
  $line = (Get-Date).ToString($time_format, $invariant) +
          "  ==== stopped by stop.ps1"
  Add-Content -Path (Join-Path $state_final "launch.log") -Value $line `
    -Encoding ASCII
}
Write-Host ""
Write-Host "The state is kept: finished runs and tasks stay as they are, the"
Write-Host "runs that were being fitted are fitted again. To resume:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"analysis\06_final-run\launch.ps1`""
Write-Host "The scheduled task `"Masters final run`" also starts the launcher at"
Write-Host "your next logon; to prevent that:"
Write-Host "  Disable-ScheduledTask -TaskName `"Masters final run`""
exit 0
