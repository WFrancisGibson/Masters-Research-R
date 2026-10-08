# Results of the final run (branch `results/final-run`)

This branch holds the results of the final run of the thesis code: every model on every data
set, fitted unattended on a Windows VM. It has no code and shares no history with `main`. The
code that produced a commit is named in its message (`code <commit of main>`). The template of
this file is `analysis/06_final-run/results_readme.md` on `main`.

## How it is written

On the VM the branch is checked out in its own worktree, `..\Masters-Research-R-results` beside
the project, and the launcher (`analysis/06_final-run/launch.ps1` on `main`) sets `RUN_ROOT` to
its folder `results`. The R scripts then write their interim files, run files, tables, figures
and logs straight into this worktree. The launcher commits and pushes it after every completed
stage, every six hours and at the end; the commit message names the stage, the code commit and
the computer. Nothing else should push to this branch while the run is going: the push of the
VM would be refused.

## What is where

Everything is under `results/` (= `RUN_ROOT`), in the folders of `config.yml`, one folder per
data set (`baseline`, `si_calendar`, `long_reporting`; a data set with units has one folder per
unit below it):

| Folder | Content |
|---|---|
| `results/data/interim/<dataset>[/<unit>]/` | prepared inputs: `triangles.rds`, the cells of the NN chain ladder on SynthETIC |
| `results/data/processed/<dataset>[/<unit>]/` | the fits: one `.rds` file per run (network, seed, bootstrap chunk), with its training times |
| `results/output/tables`, `figures`, `logs` `/<dataset>[/<unit>]/` | tables (`.csv`), figures (`.png`), `sessionInfo.txt` (of the session that writes the task table, `baseline` only), `python_packages.txt` and `r_packages.txt` (every Python and R package of the fits, written by `keras check.R`) |
| `results/data/processed/quick/`, `results/output/quick/` | the same under the `quick` profile: the smoke test before the run |
| `results/final-run/` | the launcher: `tasks.csv` (the task table), `status.csv` and `status_stages.csv` (progress and the estimated end, written by `final run status.R`), `launch.log` (events), `run_info.txt` (computer, R, Python, code commit and slots of every launch), `done/`, `failed/`, `logs/` (output of every R session, `git.log`), `quick/` (the same for the smoke test) |

Not in the branch (see `.gitignore`): the Keras models (`*.keras`), the cells and network
inputs of the machine data (`nncl_cells.rds`, `nncl_inputs.rds`), the CL factors of the main
runs of the NN chain ladder on the machine data (`nncl_factors_<run>.rds`; their losses,
reserves and times are in `nncl_fit_<run>.rds`, which is kept), lock and temporary files of
running sessions, and any file over 50 MB (the launcher lists those at the end of `.gitignore`;
GitHub refuses files over 100 MB). They stay on the VM.

The Python packages of the fits are those of `requirements.txt` at the code commit: the setup
of the VM builds one Python environment from that file, the launcher names it to every R
session (`RETICULATE_PYTHON`), and `keras check.R` stops if Python reports another program or
other versions.

## Reading the results on the laptop

From the project folder (on `main`), once:

```
git fetch origin
git worktree add ..\Masters-Research-R-results results/final-run
```

and later, for the newest push of the VM:

```
git -C ..\Masters-Research-R-results pull
```

If the pull stops because `status.csv` or `status_stages.csv` were changed on this computer
(the status script run by hand rewrites them), discard that local copy first and pull again:

```
git -C ..\Masters-Research-R-results restore .
```

Every analysis script without Keras then runs on these results when `RUN_ROOT` points to the
folder `results` of the worktree (PowerShell; use the path of your own computer):

```
$env:RUN_ROOT = "C:/Users/frang/Projects/Masters-Research-R-results/results"
$env:DATASET = "baseline"
Rscript "analysis/03_bCCNN/bCCNN grid analysis.R"
```

`DATASET`, `UNIT`, `VALIDATION`, `FINAL_FIT` and `R_CONFIG_ACTIVE` choose the data set, unit,
variant and profile as for the fits (README of `main`). The scripts write their tables and
figures into the worktree; `git -C ..\Masters-Research-R-results status` shows them. Commit and
push them only after the run on the VM has finished.

A script that needs a file that is not in the branch (the cells of the machine data) needs the
script that writes it run first, with the same `RUN_ROOT` and the raw data of the laptop.

## Progress of a run

`results/final-run/launch.log` has one line per event (start and end of every R session with
its exit code and seconds, failures, finished tasks and stages, pushes) and a progress line
every few minutes, which also counts the pushes that failed in a row and names a session that
has been quiet for hours. A task that failed three times in a row has a file in
`results/final-run/failed/` with the reason and the last lines of its log; the tasks that need
it are reported as blocked. `analysis/06_final-run/final run status.R` on `main` prints the
progress and an estimate of the time left.

The VM pushes after every stage and at least every six hours. No new commit on this branch for
longer than that, while the run is not finished, means that the VM was restarted or the run
has stopped: log on to the VM (the launcher starts by itself one minute after the logon and
resumes) and read `launch.log`.
