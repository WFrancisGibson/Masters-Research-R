##########################################
#########  final run: setup of a new Windows computer (the VM)
#########  run once, as administrator; own design (Windows PowerShell 5.1)
##########################################

## before it: install R 4.6.1, Rtools 4.5 and Git for Windows (pages below)
## and clone the repository, all under the Windows account that will run the
## final run. Then, in a PowerShell opened with "Run as administrator", from
## the project root:
##   powershell -ExecutionPolicy Bypass -File "analysis\06_final-run\setup_vm.ps1"
## It can be run again: every step looks first at what is there.
##   -WhatIf           prints every step and the commands it would run,
##                     changes nothing
##   -Rscript          Rscript.exe to use instead of R 4.6.1 from the registry
##   -Python uv        no Python environment is built: every R session
##                     resolves its Python packages with uv through
##                     reticulate (needs the internet at every session start;
##                     the way out if the environment cannot be built). The
##                     launcher is then started with -Python uv as well
##   -LaunchArguments  further arguments of launch.ps1 for the scheduled
##                     task, in one text: "-Slots 12 -PushHours 3"
## It does not start the run; the next steps are printed at the end.

param(
  [switch]$WhatIf,
  [string]$Rscript = "",
  [string]$Python = "",
  [string]$LaunchArguments = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$r_page = "https://cran.r-project.org/bin/windows/base/"
$rtools_page = "https://cran.r-project.org/bin/windows/Rtools/"
$git_page = "https://git-scm.com/download/win"
$branch = "results/final-run"
$task_name = "Masters final run"

##########################################
#########  functions
##########################################

## the heading of a step
function Write-Step($text) {
  Write-Host ""
  Write-Host ("== " + $text)
}

## runs a program with its arguments; under -WhatIf it only prints the
## command. A required step that fails stops the setup, another one is
## reported and left to be done by hand
function Invoke-Step($exe, $arguments, $required) {
  $shown = @($arguments | ForEach-Object {
    if ($_ -match " ") { "`"" + $_ + "`"" } else { $_ }
  })
  Write-Host ("   > " + $exe + " " + ($shown -join " "))
  if ($WhatIf) { return }
  & $exe $arguments
  if ($LASTEXITCODE -eq 0) { return }
  if ($required) {
    Write-Host ""
    Write-Host ("FAILED (exit code " + $LASTEXITCODE + "). The setup stops" +
                " here: mend this step and run setup_vm.ps1 again.")
    exit 1
  }
  Write-Host ("   failed (exit code " + $LASTEXITCODE + "): do this step by" +
              " hand")
}

##########################################
#########  administrator, R 4.6.1, Rtools, Git
##########################################

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root
if ($WhatIf) {
  Write-Host "-WhatIf: the steps and their commands are printed, nothing is changed."
}
if ($Python -ne "" -and $Python -ne "uv") {
  Write-Host "-Python must be `"uv`" or left out."
  exit 1
}

Write-Step "administrator rights (for the power settings)"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$admin = $principal.IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("   user " + $identity.Name + ", administrator: " + $admin)
if (-not $admin -and -not $WhatIf) {
  Write-Host "Open PowerShell with `"Run as administrator`" and run setup_vm.ps1 again."
  exit 1
}

## R 4.6.1: the registry entry of its installer, else the default folder;
## bin\x64\Rscript.exe is the process that works (launch.ps1 uses the same)
Write-Step "R 4.6.1, Rtools 4.5, Git"
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
$missing = @()
if (Test-Path $rscript) {
  Write-Host ("   " + ((& $rscript -e "cat(R.version.string)") -join " ") +
              ": " + $rscript)
} else {
  $missing += "R 4.6.1 (not found: " + $rscript + "): " + $r_page +
              " (when a later R is out: under old/4.6.1 there)"
}
## Rtools 4.5 is the Rtools of R 4.6: packages of renv.lock that CRAN has
## replaced by a later version in the meantime are built from their sources
$rtools = $env:RTOOLS45_HOME
if ($null -eq $rtools -or $rtools -eq "") { $rtools = "C:\rtools45" }
if (Test-Path (Join-Path $rtools "usr\bin\make.exe")) {
  Write-Host ("   Rtools 4.5: " + $rtools)
} else {
  $missing += "Rtools 4.5 (not found in " + $rtools + "): " + $rtools_page
}
if ($null -ne (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host ("   " + ((& git --version) -join " "))
} else {
  $missing += "Git for Windows (git is not on the PATH): " + $git_page
}
if ($missing.Count -gt 0) {
  Write-Host ""
  Write-Host "Install first, with the default options, then open a new PowerShell"
  Write-Host "and run setup_vm.ps1 again:"
  foreach ($line in $missing) { Write-Host ("   " + $line) }
  if (-not $WhatIf) { exit 1 }
}

##########################################
#########  R packages, unit tests
##########################################

## the packages of renv.lock (the versions of the laptop) go into the user
## library; renv is not activated in the project (no renv folder, .Rprofile
## as it is), so the scripts run as on the laptop. Without the cache renv
## installs the packages themselves, not links into its cache
Write-Step "R packages of renv.lock into the user library"
$env:RENV_CONFIG_CACHE_ENABLED = "FALSE"
$env:RENV_CONFIG_SANDBOX_ENABLED = "FALSE"
$make_library = "dir.create(Sys.getenv('R_LIBS_USER'), recursive = TRUE, " +
                "showWarnings = FALSE)"
$install_renv = "if (!requireNamespace('renv', quietly = TRUE)) " +
                "install.packages('renv', repos = 'https://cloud.r-project.org')"
$restore = "renv::restore(lockfile = 'renv.lock', library = .libPaths()[1], " +
           "prompt = FALSE)"
Invoke-Step $rscript @("-e", $make_library) $true
Invoke-Step $rscript @("-e", $install_renv) $true
Invoke-Step $rscript @("-e", $restore) $true

Write-Step "unit tests (no Keras)"
Invoke-Step $rscript @("tests/testthat.R") $true

##########################################
#########  Python environment, Keras
##########################################

## the Python of the fits is built here once, from requirements.txt (the
## complete package list of the laptop), in its own folder beside the
## project: env is the environment, python the Python it rests on. The
## launcher names its python.exe to reticulate in every session
## (launch.ps1, contract 10.), so no session needs the internet and no
## release of a Python package changes the run. It is built with uv, the
## program reticulate itself uses (reticulate downloads it at the first
## call); the files are copied, so the environment does not hang on a cache.
## Left alone, reticulate would resolve the packages again at every session
## start: that is -Python uv
$python_home = Join-Path (Split-Path $root -Parent) "Masters-Research-R-python"
$python_env = Join-Path $python_home "env"
$python_exe = Join-Path $python_env "Scripts\python.exe"
$python_built = Join-Path $python_home "built.txt"
$python_version = "3.12"
foreach ($line in @(Get-Content (Join-Path $root "requirements.txt"))) {
  if ($line -cmatch "^# python ([0-9.]+)") { $python_version = $Matches[1] }
}
Write-Step ("Python " + $python_version + " environment of requirements.txt: " +
            $python_env)
if ($Python -eq "uv") {
  Write-Host "   -Python uv: not built; every R session resolves its packages with uv"
} elseif (Test-Path $python_built) {
  Write-Host ("   it is there already (to build it again delete the folder " +
              $python_home + ")")
} else {
  Write-Host "   (if these steps cannot be made to work: setup_vm.ps1 -Python uv)"
  Write-Host "   > Rscript -e `"cat(reticulate:::uv_binary())`""
  $uv = "uv.exe"
  if (-not $WhatIf) {
    $uv = (& $rscript -e "cat(reticulate:::uv_binary())") -join ""
    if ($uv -eq "" -or -not (Test-Path $uv)) {
      Write-Host ""
      Write-Host "FAILED: reticulate found and downloaded no uv. The setup stops"
      Write-Host "here: mend this step and run setup_vm.ps1 again."
      exit 1
    }
  }
  $env:UV_PYTHON_INSTALL_DIR = Join-Path $python_home "python"
  $env:UV_PYTHON_PREFERENCE = "only-managed"
  Write-Host ("   UV_PYTHON_INSTALL_DIR = " + $env:UV_PYTHON_INSTALL_DIR)
  if (-not $WhatIf) {
    New-Item -ItemType Directory -Path $python_home -Force | Out-Null
  }
  if (-not (Test-Path $python_exe)) {
    Invoke-Step $uv @("venv", "--python", $python_version, $python_env) $true
  }
  Invoke-Step $uv @("pip", "install", "--python", $python_exe, "--link-mode",
                    "copy", "-r", "requirements.txt") $true
  Write-Host ("   > write " + $python_built)
  if (-not $WhatIf) {
    Set-Content -Path $python_built -Encoding ASCII `
      -Value ("built " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") +
              " with " + $uv)
  }
}

## the first Keras session of this computer, with the variables the
## launcher gives its sessions: the versions are compared with
## requirements.txt and a small network is trained. RUN_DIR must not be
## set: with it keras3 adds a TensorBoard callback to every fit
Write-Step "Keras: the Python packages against requirements.txt, a small network"
$env:RUN_DIR = $null
if ($Python -ne "uv") {
  $env:RETICULATE_PYTHON = $python_exe
  $env:RETICULATE_USE_MANAGED_VENV = "no"
  $env:RETICULATE_CHECK_REQUIRED_PACKAGES = "false"
  $env:KERAS_PYTHON = $null
  Write-Host ("   RETICULATE_PYTHON = " + $python_exe)
}
Invoke-Step $rscript @("analysis/06_final-run/keras check.R") $true

##########################################
#########  results worktree, git
##########################################

## the branch results/final-run is checked out beside the project; RUN_ROOT
## of the final run is its folder results. If GitHub has no such branch yet
## it is made here: an empty branch with the .gitignore, .gitattributes and
## README.md of the templates in this folder
$results = Join-Path (Split-Path $root -Parent) "Masters-Research-R-results"
Write-Step ("results worktree " + $results)
if (Test-Path (Join-Path $results ".git")) {
  Write-Host "   it is there already"
} else {
  Invoke-Step "git" @("fetch", "origin") $true
  $on_github = $false
  if (-not $WhatIf) {
    & git ls-remote --exit-code --heads origin $branch | Out-Null
    $on_github = ($LASTEXITCODE -eq 0)
  }
  if ($WhatIf) { Write-Host "   if GitHub has the branch $branch :" }
  if ($on_github -or $WhatIf) {
    Invoke-Step "git" @("worktree", "add", $results, $branch) $true
  }
  if ($WhatIf) { Write-Host "   if it has not:" }
  if (-not $on_github) {
    Invoke-Step "git" @("worktree", "add", "--orphan", "-b", $branch,
                        $results) $true
    foreach ($pair in @(@("results_gitignore.txt", ".gitignore"),
                        @("results_gitattributes.txt", ".gitattributes"),
                        @("results_readme.md", "README.md"))) {
      Write-Host ("   > copy " + $pair[0] + " to " + $pair[1])
      if (-not $WhatIf) {
        Copy-Item -Path (Join-Path $PSScriptRoot $pair[0]) `
          -Destination (Join-Path $results $pair[1])
      }
    }
  }
}

## a folder made in this administrator PowerShell belongs to the group
## Administrators, and git refuses such a folder in a normal PowerShell
## ("dubious ownership"), where the launcher and the scheduled task run:
## the project and the results worktree are named safe folders of this user
Write-Step "git safe.directory: the project and the results worktree"
$safe = @(& git config --global --get-all safe.directory)
foreach ($folder in @($root, $results)) {
  $path = $folder.Replace("\", "/")
  if ($safe -contains $path) {
    Write-Host ("   safe.directory has " + $path)
  } else {
    Invoke-Step "git" @("config", "--global", "--add", "safe.directory",
                        $path) $true
  }
}

## git needs a name and an e-mail address for the commits of the results
Write-Step "git user.name and user.email"
foreach ($field in @("user.name", "user.email")) {
  $value = (& git config $field) -join ""
  if ($value -ne "") {
    Write-Host ("   " + $field + " = " + $value)
  } elseif ($WhatIf) {
    Write-Host ("   " + $field + " is not set: would ask for it and run")
    Write-Host ("   > git config --global " + $field + " <answer>")
  } else {
    $value = Read-Host ("   " + $field + " is not set; type it")
    Invoke-Step "git" @("config", "--global", $field, $value) $true
  }
}

## the first commit of a branch made here, then the push access: the first
## push opens the sign-in window of the Git Credential Manager once (sign in
## with the GitHub account that may push to the repository); the launcher
## later uses the stored credential and never asks
Write-Step "push access to GitHub (sign in if a window opens)"
if ($WhatIf) {
  Write-Host "   if the branch was made here:"
  Write-Host "   > git -C $results add -A"
  Write-Host "   > git -C $results commit -m `"Results of the final run: empty branch`""
  Write-Host "   > git -C $results push -u origin $branch"
  Write-Host "   always:"
  Write-Host "   > git -C $results push --dry-run origin HEAD"
} else {
  & git -C $results rev-parse --verify --quiet HEAD | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Invoke-Step "git" @("-C", $results, "add", "-A") $true
    Invoke-Step "git" @("-C", $results, "commit", "-m",
                        "Results of the final run: empty branch") $true
    Invoke-Step "git" @("-C", $results, "push", "-u", "origin", $branch) $true
  }
  Invoke-Step "git" @("-C", $results, "push", "--dry-run", "origin",
                      "HEAD") $true
}

##########################################
#########  power settings, scheduled task
##########################################

## the high-performance plan, and on mains power never sleep, hibernate or
## switch the disk off
Write-Step "power settings: high performance, never sleep on mains power"
Invoke-Step "powercfg" @("/setactive", "SCHEME_MIN") $false
Invoke-Step "powercfg" @("/change", "standby-timeout-ac", "0") $false
Invoke-Step "powercfg" @("/change", "hibernate-timeout-ac", "0") $false
Invoke-Step "powercfg" @("/change", "disk-timeout-ac", "0") $false

## the launcher starts again when this user logs on (one minute later, for
## the network), so the run resumes after a restart of the computer once you
## have logged on. Not "at startup": the push needs the GitHub credential
## that Windows keeps for the logged-on user, and a task at startup runs
## without that user. Until somebody logs on after a restart the run stands
## still: the sign is that the pushes stop. Task Scheduler's defaults would
## stop the task after 3 days and run it at low priority: no time limit,
## normal priority (4). The task starts launch.ps1 with -LaunchArguments
## (and -Python uv if the setup was run with it): a run that is started by
## hand with other arguments needs them here too, or it resumes without
Write-Step ("scheduled task `"" + $task_name + "`": launch.ps1 at logon")
$launch = Join-Path $PSScriptRoot "launch.ps1"
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $launch + "`""
$launch_extra = $LaunchArguments.Trim()
if ($Python -eq "uv" -and $launch_extra -notmatch "-Python ") {
  $launch_extra = ($launch_extra + " -Python uv").Trim()
}
if ($launch_extra -ne "") { $arguments = $arguments + " " + $launch_extra }
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument $arguments -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$trigger.Delay = "PT1M"
$task_user = New-ScheduledTaskPrincipal -UserId $identity.Name `
  -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries -StartWhenAvailable -Priority 4 `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
Write-Host ("   > powershell.exe " + $arguments)
Write-Host ("   at logon of " + $identity.Name + ", in " + $root)
if (-not $WhatIf) {
  Register-ScheduledTask -TaskName $task_name -Action $action `
    -Trigger $trigger -Principal $task_user -Settings $settings -Force |
    Out-Null
  Write-Host "   registered"
}

##########################################
#########  next steps
##########################################

$start = "powershell -ExecutionPolicy Bypass -File " +
         "`"analysis\06_final-run\launch.ps1`""
if ($launch_extra -ne "") { $start = $start + " " + $launch_extra }
Write-Host ""
if ($WhatIf) {
  Write-Host "-WhatIf: nothing was changed. After the real setup:"
} else {
  Write-Host "Setup finished. Next:"
}
Write-Host " 1. Windows Update: Settings > Windows Update > Pause updates, for"
Write-Host "    as long as it lets you (a restart stops the run until you log"
Write-Host "    on again)."
Write-Host " 2. Start the run, in a normal PowerShell (not this administrator"
Write-Host "    one), from the project root:"
Write-Host ("      " + $start)
Write-Host "    It first runs every task under the quick profile (the smoke"
Write-Host "    test) and stops if one fails; then the final run."
Write-Host " 3. Leave the computer: close the Remote Desktop window (disconnect)."
Write-Host "    Do NOT sign out: signing out ends the launcher and its R sessions."
Write-Host " 4. Watch: the branch $branch on GitHub (a push after every stage"
Write-Host "    and every 6 hours), or on this computer"
Write-Host "      Get-Content `"..\Masters-Research-R-results\results\final-run\launch.log`" -Tail 20"
Write-Host "    No push for more than 6 hours although the run is not finished:"
Write-Host "    the computer was restarted or the run has stopped. Log on (the"
Write-Host "    launcher starts by itself one minute later) and read launch.log."
Write-Host " 5. Stop:   powershell -ExecutionPolicy Bypass -File `"analysis\06_final-run\stop.ps1`""
Write-Host "    Resume: the command of step 2."
Write-Host " 6. From now on the launcher also starts by itself one minute after"
Write-Host "    you log on (scheduled task `"$task_name`"), so the run resumes"
Write-Host "    after a restart of the computer once you have logged on. To switch"
Write-Host "    that off:  Disable-ScheduledTask -TaskName `"$task_name`""
Write-Host "    Without a logon nothing resumes. If the run must resume with"
Write-Host "    nobody there, set up the automatic logon of this account"
Write-Host "    yourself (Microsoft's Sysinternals Autologon keeps the Windows"
Write-Host "    password on this computer: your decision, not done here)."
