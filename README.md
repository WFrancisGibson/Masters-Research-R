# Masters-Research-R

Research compendium for the masters thesis (R strands). The code follows the style of
Gabrielli (2020, PhD thesis, Paper C listings) and the *AI Tools for Actuaries* course code:
short scripts that run from top to bottom, a few small functions, base R.

Contents: [Strands](#strands), [Layout](#layout),
[Data sets and environment variables](#data-sets-and-environment-variables),
[Running the scripts](#running-the-scripts), [The fits of the final run](#the-fits-of-the-final-run),
[The final run on the VM](#the-final-run-on-the-vm),
[How the results reach GitHub](#how-the-results-reach-github),
[Reading the results on the laptop](#reading-the-results-on-the-laptop),
[Training times](#training-times), [What has been executed](#what-has-been-executed),
[Tests and lint](#tests-and-lint), [Branches](#branches), [Setup of a computer](#setup-of-a-computer),
[Notes on the strands](#notes-on-the-strands)

## Strands

| Strand | What | Scripts |
|---|---|---|
| Simulations | Synthetic claims with SynthETIC (Avanzi, Taylor, Wang & Wong 2021; environment 1 of Al-Mudafer et al. 2021 with five claim covariates), annual 20 x 20, in three scenarios: `baseline`, `si_calendar` (15% p.a. superimposed inflation by calendar year), `long_reporting` (mean notification delay of 2 years). A fingerprint of every data set, its triangles, and two description scripts | `analysis/00_claim-simulation/` |
| Mack | Mack (1993) chain ladder with standard errors | `analysis/01_Mack model/Mack chainladder fit.R` |
| ODP GLM | Over-dispersed Poisson GLM; dispersion by Pearson's statistic and by Paper C eq. (5); RMSEP by seven methods (formula and bootstraps) | `analysis/02_ODP glm model/ODP glm fit plot.R` |
| bCCNN | The network of Paper C (Gabrielli, Richman & Wuthrich 2020) on the triangle. **Main fit** under three early-stopping variants: rolling origin (Al-Mudafer et al. 2021) with a refit, rolling origin with the network of the final partition, Paper C's 50/50 claims split with a refit. **Bootstrap** of each variant (Paper C Section 3.3.4, 1,000 refits). **Masking study** under the claims split (periods without payments in the training half masked or scored, 20 seeds). **Grid** of 144 architectures and settings x 20 seeds, every run finished under four stopping rules (minimum, fixed, moving average, patience). **Search**: hyperparameters chosen on the rolling-origin folds | `analysis/03_bCCNN/` |
| NN chain ladder | The CL factor networks of Wuthrich (2018) on the SynthETIC claims. **Main runs** (Listing 2 with q = 5, 10, 20; S1 Adam, S2 early stopping, S3 chain-ladder start, S4 balance correction). **Random-start grid** (3 hidden-layer settings x 10 optimisers x trainings `paper`, `early_stop` x 20 seeds) and **chain-ladder-start grid** (the same with trainings `cl_paper`, `cl_start`). Everything under **two codings of Age of Claimant** (four dummies; one ordinal score). **Search** per training mode on rolling-origin folds | `analysis/04_nn-chain-ladder/trackA_wuthrich2018/NN chain ladder SynthETIC *.R` |
| Six lines of business | Paper C Appendix A (the data of Harkonen 2021): simulated and described only (data set `lob6`). No model is fitted on it and it is not part of the final run | `analysis/00_claim-simulation/lines-of-business/` |
| The paper's NN chain ladder | Wuthrich (2018) on its own four LoBs of the Gabrielli & Wuthrich (2018) machine (data set `machine4`); not part of the final run | `analysis/00_claim-simulation/individual_claims_simulation_machine.R`, `.../trackA_wuthrich2018/NN chain ladder fit.R`, `NN chain ladder analysis.R`, `NN chain ladder learning cells.R`, `simulated data description.R` |
| Final run | Every fit of the three SynthETIC data sets, unattended on a Windows VM: launcher, task table, status, training times | `analysis/06_final-run/` |

`analysis/05_TabM ODP model/` is to come.

## Layout

- `analysis/00_setup.R`: sourced first by every script (packages, `config.yml`, paths, seed, the
  functions in `R/`)
- `R/`: functions only
  - `triangles.R`: claims triangles, 50/50 claims split, rolling-origin partitions, masked periods
  - `loss functions.R`: Poisson deviance
  - `reserves.R`: reserve tables, back-test against the true reserves, RMSEP table
  - `fit ODP GLM.R`: ccODP model (Paper C Section 2), both dispersion estimates, ODP sample,
    parametric bootstrap, chain ladder, England & Verrall (1999) bootstrap
  - `nn_models.R`: bCCNN network, fit, rolling origin, stopping rules, bootstrap, grid runs
  - `nn_chain_ladder.R`: CL factor networks, optimisers, run lists (`nncl_runs()`), zero claims
    factors, reserves, Mack
  - `tuning.R`, `bccnn_tuning.R`, `nncl_tuning.R`: hyperparameter search on rolling-origin folds
  - `runs.R`: runs shared by several R sessions (`claim_run()`, `save_run()`, `run_info()`)
  - `data_fingerprint.R`: fingerprint of a simulated data set
  - `claims_description.R`, `lob_simulation.R`: descriptions, the six lines of business
  - `plots.R`, `plots_claims_description.R`, `plots_lob_simulation.R`, `plots_nn_chain_ladder.R`:
    figures
- `config.yml`: seed, data sets, hyper-parameters, paths (read with `config::get()`); profiles
  `quick`, `age_numeric`, `quick_age_numeric` (below)
- `tests/`: checks of the functions in `R/` and of the scripts (`tests/testthat.R`)
- `requirements.txt`: the Python packages of the fits (TensorFlow, Keras), pinned; `renv.lock`:
  the R packages
- `.lintr`: lintr settings (default linters: snake_case names, lines up to 80 characters; `%>%`
  as the only pipe)
- `reviews/`: paper-critique .Rmd files; `thesis/`: chapters, explainers, `references.bib`

Data and outputs, never edited by hand and not in git on `main` (`.gitignore`):

| Folder | Content |
|---|---|
| `data/raw/<dir>/` | the simulated claims of a data set (`dir` of its block in `config.yml`); another place with `RAW_DIR` |
| `data/interim/<dataset>[/<unit>]/` | prepared inputs: `triangles.rds`, the cells of the NN chain ladder |
| `data/processed/<dataset>[/<unit>]/` | the fits: one `.rds` file per run, with its training times |
| `models/<dataset>[/<unit>]/` | Keras models (`.keras`) |
| `output/tables`, `output/figures`, `output/logs` `/<dataset>[/<unit>]/` | tables (`.csv`), figures (`.png`); in the logs `sessionInfo.txt` (the R packages of the last script run by hand on that data set) and, under `baseline`, `python_packages.txt` and `r_packages.txt` (every Python and R package of the fits, written by `keras check.R`) |
| `data/processed/quick/`, `models/quick/`, `output/quick/` | the same under the `quick` profiles (`data/interim` is shared) |

A unit is the triangle of one LoB of a machine data set (`lob1`, ..., `lob_all`); the SynthETIC
data sets have one triangle and no unit. With `RUN_ROOT` all these folders except `data/raw` are
below that folder instead of the project folder.

## Data sets and environment variables

| `DATASET` | Raw folder `data/raw/...` | What |
|---|---|---|
| `baseline` (default) | `claim-simulation-annual` | SynthETIC, environment 1, annual 20 x 20 |
| `si_calendar` | `claim-simulation-annual-SI-calendar` | baseline with 15% p.a. superimposed inflation by calendar year |
| `long_reporting` | `claim-simulation-annual-long-reporting` | baseline with a mean notification delay of 2 years |
| `lob6` | `claim-simulation-lob` | six LoBs of Paper C Appendix A, 12 x 12; data only |
| `machine4` | `claim-simulation-machine` | four LoBs of Wuthrich (2018), 12 x 12; the paper's NN chain ladder only |

| Variable | Values | Meaning |
|---|---|---|
| `DATASET` | see above | the data set of the R session |
| `UNIT` | empty, `lob1` ... `lob6`, `lob_all` | machine data sets only: the triangle of one LoB |
| `R_CONFIG_ACTIVE` | empty, `quick`, `age_numeric`, `quick_age_numeric` | profile of `config.yml`. `quick`: small settings for a fast check, outputs apart. `age_numeric`: the NN chain ladder SynthETIC scripts with Age of Claimant as an ordinal score, its fits and outputs apart. `quick_age_numeric`: both |
| `VALIDATION` | `rolling_origin` (default), `claims_split` | early stopping of the bCCNN |
| `FINAL_FIT` | `refit` (default), `partition` | final bCCNN network: refitted on the whole triangle, or the network of the final rolling-origin partition (rolling origin only) |
| `RUN_ROOT` | a folder (default: the project folder) | where interim files, fits and outputs go; relative to the project folder or absolute |
| `RAW_DIR` | a folder (default `data/raw`) | the simulated claims of all data sets |

Never define a variable `RUN_DIR`: with it keras3 adds a TensorBoard callback to every fit.
A file `.Renviron` in the project folder (not in git) may set `RAW_DIR`; R lets that file win
over the shell.

bash:

```
DATASET=si_calendar VALIDATION=claims_split Rscript "analysis/03_bCCNN/bCCNN fit.R"
R_CONFIG_ACTIVE=quick Rscript "analysis/02_ODP glm model/ODP glm fit plot.R"
```

PowerShell (a variable stays set for the window: remove it afterwards):

```
$env:DATASET = "si_calendar"
$env:VALIDATION = "claims_split"
Rscript "analysis/03_bCCNN/bCCNN fit.R"
Remove-Item Env:DATASET, Env:VALIDATION
```

`Rscript` stands for the Rscript of R 4.6.1. Where R's folder is not on the PATH, write
`& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" "<script>"` in PowerShell and
`"/c/Program Files/R/R-4.6.1/bin/Rscript.exe" "<script>"` in Git Bash.

## Running the scripts

Every script runs from the project folder, top to bottom, for the data set (and variant,
profile) of its environment. A fit script saves every run in its own file under
`data/processed/<dataset>/` and leaves out the saved ones, so a stopped script resumes; delete
a file to fit it again. Fit scripts need Keras; the analysis scripts read the saved runs and do
not. The order within a strand:

**Simulations** (per SynthETIC data set):

1. `analysis/00_claim-simulation/SynthETIC claims simulation.R`: writes `claims.csv`,
   `transactions.csv` and the design of the covariates to `data/raw/<dir>/`
2. `analysis/00_claim-simulation/data fingerprint.R`: counts and sums of the claims against
   `analysis/00_claim-simulation/fingerprints/<dataset>.csv` (in git); stops at a difference.
   Without that file it writes it; with the argument `check` a missing file is an error
3. `analysis/00_claim-simulation/claims triangles.R`: `data/interim/<dataset>/triangles.rds`
   (full square, observed triangle, true outstanding, the two halves of the claims split, tail)
4. `analysis/00_claim-simulation/SynthETIC claims description.R` and
   `SynthETIC feature impact.R`: tables and figures in
   `output/tables|figures/<dataset>/00_claim-simulation/data-description/` and
   `.../feature-impact/`

**Mack, ODP GLM** (after step 3): `analysis/01_Mack model/Mack chainladder fit.R`
(`output/tables/<dataset>/01_Mack/`), `analysis/02_ODP glm model/ODP glm fit plot.R`
(`output/tables|figures/<dataset>/02_ODP-glm/`).

**bCCNN** (`analysis/03_bCCNN/`, after step 3):

1. `bCCNN fit.R`, once per variant (`VALIDATION`, `FINAL_FIT`): saves
   `bccnn_fit_<validation>_<final_fit>.rds` and writes its tables
   (`output/tables/<dataset>/03_bCCNN/bccnn_<variant>_*.csv`) and figures
   (`output/figures/<dataset>/03_bCCNN/<variant>/`). `bCCNN partitions.R` draws the partitions
2. `bCCNN bootstrap fit.R` (same variant; the refits in `bccnn_bootstrap_<variant>_c<k>.rds`),
   then `bCCNN bootstrap analysis.R` (RMSEP tables and figures)
3. `bCCNN masking fit.R` (`bccnn_masking_fit_s<seed>.rds`), then `bCCNN masking analysis.R`
4. `bCCNN grid fit.R` (`bccnn_grid_fit_<run>.rds`), after `bCCNN fit.R` under the rolling origin
   with the refit (the defaults): the stopping rule "fixed" reads its steps off that fit. Then
   `bCCNN grid analysis.R` (`bccnn_grid_*.csv`, `bCCNN grid *.png`)
5. `bCCNN hyperparameter search.R` (`bccnn_tuning_search.rds`, the scored sets in
   `bccnn_tuning/`; tables `bccnn_tuning_*.csv`)

**NN chain ladder on SynthETIC** (`analysis/04_nn-chain-ladder/trackA_wuthrich2018/`, after
step 1; every script once per coding: no profile for the dummy coding,
`R_CONFIG_ACTIVE=age_numeric` for the numeric one):

1. `NN chain ladder SynthETIC cells.R`, for both codings, one after the other, before any fit
   (the two write the same shared files): cells, network inputs, homogeneous model, zero claims
2. `NN chain ladder SynthETIC fit.R` with the argument `main`, `grid` or `cl_grid` (no argument:
   all three; another word is an error): `<tag>_fit_<run>.rds` with `<tag>` =
   `nncl_synthetic` or `nncl_synthetic_age_numeric`
3. `NN chain ladder SynthETIC analysis.R` (after `main`; it takes in of each grid the blocks of
   10 seeds fitted in full): `output/tables|figures/<dataset>/04_NN-chain-ladder/synthetic/` or
   `.../synthetic-age-numeric/`. `NN chain ladder SynthETIC partition.R` draws the training,
   validation and test cells
4. `NN chain ladder SynthETIC hyperparameter search.R` with the argument `cl_start`, `paper` or
   `early_stop`: scored sets in `nncl_tuning/<tag>/<mode>/`, final fits
   `<tag>_fit_tuned_<mode>_s<seed>.rds`, tables `nncl_tuning_<mode>_*.csv`
5. `NN chain ladder SynthETIC age coding.R` (no profile), when main runs and both grids are
   fitted under both codings: `.../04_NN-chain-ladder/synthetic-age-coding/`

```
Rscript "analysis/04_nn-chain-ladder/trackA_wuthrich2018/NN chain ladder SynthETIC fit.R" main
```

**Six lines of business** and **the paper's NN chain ladder**: see
[Notes on the strands](#notes-on-the-strands).

## The fits of the final run

Three data sets (`baseline`, `si_calendar`, `long_reporting`), one triangle each. The numbers
are those of `config.yml` and of the functions that build the run lists (`bccnn_grid_runs()`,
`nncl_runs()`); `analysis/06_final-run/final run tasks.R` prints the runs of its table. A run is
one file; the networks are the Keras fits in it.

bCCNN, per data set and over the three:

| Fit | Runs per data set | Networks per data set | Runs in all | Networks in all |
|---|---|---|---|---|
| Main fit: rolling origin + refit, rolling origin + partition, claims split + refit | 3 | 6 + 3 + 2 = 11 | 9 | 33 |
| Bootstrap of each variant: 1,000 refits in 20 chunk files | 60 chunks | 3,000 | 180 chunks | 9,000 |
| Masking study, claims split: 20 seeds | 20 | 40 to 60 (2 or 3 a seed) | 60 | 120 to 180 |
| Grid: 4 hidden x 2 activations x 3 dropouts x 3 optimisers x 2 batch sizes = 144 settings x 20 seeds; each run is 3 validation runs of 3,000 steps plus one refit per partition and distinct number of steps of the 4 stopping rules | 2,880 (11,520 results) | 8,640 to 43,200 (3 to 15 a run) | 8,640 (34,560 results) | 25,920 to 129,600 |
| Search: successive over dropout, hidden layers, activation, learning rate; 3 seeds | 1 search, at most 11 sets | at most 144 | 3 searches | at most 432 |

NN chain ladder, per data set and coding of Age of Claimant, and over 3 data sets x 2 codings
(a run is 19 networks, one per development period):

| Fit | Runs per data set and coding | Networks | Runs in all | Networks in all |
|---|---|---|---|---|
| Main runs: paper_q5, paper_q10, paper_q20, s1_adam, s2_early_stop, s3_cl_start (S4 is saved with S3, no fit) | 6 | 114 | 36 | 684 |
| Random-start grid: 3 hidden x 10 optimisers x 2 trainings (`paper`, `early_stop`) x 20 seeds | 1,200 | 22,800 | 7,200 | 136,800 |
| Chain-ladder-start grid: 3 hidden x 10 optimisers x 2 trainings (`cl_paper`, `cl_start`) x 20 seeds | 1,200 | 22,800 | 7,200 | 136,800 |
| Search `cl_start`: at most 11 sets of 93 networks, 10 final fits | 1 search | at most 1,213 | 6 | at most 7,278 |
| Search `paper`: 27 sets, 10 final fits | 1 search | 2,701 | 6 | 16,206 |
| Search `early_stop`: at most 11 sets, 10 final fits | 1 search | at most 1,213 | 6 | at most 7,278 |

The task table of the final run has 171 tasks; its 33 queues hold 23,316 runs (per data set
12 main runs, 4,800 grid runs of the NN chain ladder, 60 bootstrap chunks, 20 masking seeds and
2,880 runs of the bCCNN grid). The main fits and the searches are tasks of one R session.

## The final run on the VM

The scripts of the VM are in `analysis/06_final-run/` (those of the HPC, in the same folder,
are in the next section): `setup_vm.ps1`, `launch.ps1` and
`stop.ps1` (Windows PowerShell 5.1), `keras check.R`, and `final run tasks.R`,
`final run status.R` and `final run timings.R`. The launcher (`launch.ps1`) keeps one R session
per processor busy with the tasks of the task table until all are done; it can be stopped and
started again at any time, finished runs and tasks are never repeated. The VM: Windows, 14
processors, 330 GB of memory. Do every step under the one Windows account that will run the
final run.

Before the first step, on the laptop: the VM clones the branch `main` from GitHub, so `main`
there must hold the code of the final run (this README and `analysis/06_final-run/`). After
the push, `git fetch origin` and then

```
git ls-tree --name-only origin/main analysis/06_final-run/launch.ps1
```

print the path of the launcher if it is there, and nothing if it is not.

1. **Install**, with the default options:
   R 4.6.1 (<https://cran.r-project.org/bin/windows/base/>, later under `old/4.6.1` there),
   Rtools 4.5 (<https://cran.r-project.org/bin/windows/Rtools/>) and
   Git for Windows (<https://git-scm.com/download/win>).
2. **Clone**, in a normal PowerShell, into a folder with a short path (say `C:\work`: the
   folder of the results may have at most 125 characters, or the longest figure names are cut):

   ```
   git clone https://github.com/WFrancisGibson/Masters-Research-R.git
   cd Masters-Research-R
   ```

3. **Setup**, once, in a PowerShell opened with "Run as administrator", from the project
   folder:

   ```
   powershell -ExecutionPolicy Bypass -File "analysis\06_final-run\setup_vm.ps1"
   ```

   It checks R, Rtools and Git; installs the R packages of `renv.lock` into the user library;
   runs the unit tests; builds the Python environment of the fits from `requirements.txt` in
   `..\Masters-Research-R-python` beside the project (`env`: the environment, `python`: the
   Python it rests on, `built.txt`: written when the build succeeded); checks Keras
   (`keras check.R`: the versions against `requirements.txt`, a small network); checks out the
   results branch `results/final-run` as a worktree in `..\Masters-Research-R-results` (a new,
   empty branch if GitHub has none); names the project and that worktree as `safe.directory` of
   git; asks for `user.name` and `user.email` of git if they are not set; pushes once, which
   opens the sign-in window of the Git Credential Manager (sign in with the GitHub account that
   may push to the repository); sets the power plan to high performance without sleep; and
   registers the scheduled task "Masters final run", which starts the launcher one minute after
   every logon of this account. It can be run again: every step looks first at what is there.
   - `-WhatIf` prints every step and its commands and changes nothing.
   - `-Python uv` is the way out if the Python environment cannot be built: no environment,
     every R session resolves its Python packages with uv (internet at every session start).
     The launcher then needs `-Python uv` too; the scheduled task gets it by itself.
   - `-LaunchArguments "-Slots 12"` gives the scheduled task further arguments of `launch.ps1`.

   Then pause Windows Update (Settings > Windows Update > Pause updates) for as long as it lets
   you: a restart stops the run until you log on.
4. **Start**, in a normal PowerShell (not the administrator one), from the project folder:

   ```
   powershell -ExecutionPolicy Bypass -File "analysis\06_final-run\launch.ps1"
   ```

   Do not select text in its window (that holds the launcher; Esc releases it). It first runs
   the **smoke test**: every task of the table under the `quick` profile (small settings, own
   folders `results\data\processed\quick`, `results\output\quick`, state in
   `results\final-run\quick`). This is the first time the model scripts run (see
   [What has been executed](#what-has-been-executed)). If a task fails there, the launcher
   writes `results\final-run\quick\smoke_failed.txt` (the failed tasks with the last lines of
   their logs), pushes and stops with exit code 1: the final run is not started. Otherwise it
   goes on to the final run; a later launch goes straight to it. The claims are simulated in
   the smoke test and again in the final run (the two have separate done markers): identical
   data, about half an hour.
5. **Leave**: close the Remote Desktop window (disconnect). Never sign out: signing out ends
   the launcher and its R sessions.
6. **Watch**:
   - the branch `results/final-run` on GitHub: a commit after every completed stage, at least
     every six hours, and at the end;
   - the events, on the VM. During the smoke test they go to the log of the quick profile,
     after it to that of the final run:

     ```
     Get-Content "..\Masters-Research-R-results\results\final-run\quick\launch.log" -Tail 20
     Get-Content "..\Masters-Research-R-results\results\final-run\launch.log" -Tail 20
     ```

     One line per start and end of an R session, finished task and stage, failure and push, and
     a progress line every five minutes. While the smoke test runs, the second file stands
     still at `smoke test: every task under the quick profile first`. A later stage can complete
     before an earlier one: a stage is a priority, what a task waits for is in its needs;
   - the status script, in a second PowerShell from the project folder: per task the runs done
     and to do, the seconds of a run and the hours left; per stage and for the whole run the
     hours left and the earliest end. Also written to `results\final-run\status.csv` (tasks)
     and `results\final-run\status_stages.csv` (stages, whole run, estimated end):

     ```
     $env:RUN_ROOT = "../Masters-Research-R-results/results"
     & "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" "analysis/06_final-run/final run status.R"
     Remove-Item Env:RUN_ROOT
     ```

     (`$env:R_CONFIG_ACTIVE = "quick"` before it shows the smoke test; then
     `Remove-Item Env:R_CONFIG_ACTIVE`.) It reckons with the processors the launcher uses: the
     slots of the last launch in `results\final-run\run_info.txt`; `$env:RUN_WORKERS = "12"`
     before it gives another number. The run itself runs this script after the benchmark stage
     (`status.benchmark`), when the first queue of each grid is done (`status.nncl.grid`,
     `status.nncl.cl_grid`, `status.bccnn.grid`) and as its last task (`status.final`); what
     it printed is in `results\final-run\logs\status.*_slot*.log`.
7. **Stop** and **resume**:

   ```
   powershell -ExecutionPolicy Bypass -File "analysis\06_final-run\stop.ps1"
   ```

   stops the launcher and its R sessions; only the runs being fitted at that moment are lost.
   The start command of step 4 resumes. If it answers `COULD NOT stop process ...` (exit code
   1), the launcher was started as administrator: run `stop.ps1` from an administrator
   PowerShell.
8. **After a restart of the VM** nothing runs until somebody logs on: log on, and the
   scheduled task starts the launcher one minute later, which resumes. No new commit on
   `results/final-run` for more than six hours while the run is not finished means: log on to
   the VM and read `launch.log`. To switch the automatic start off:
   `Disable-ScheduledTask -TaskName "Masters final run"`.

The stages (a lower stage goes first when a processor is free). The times are estimates from
fits on the laptop; stage 2 replaces them by the VM's own:

| Stage | Tasks | Time |
|---|---|---|
| 0 | Keras check, simulation, fingerprint check, triangles, cells of the NN chain ladder (both codings), data description, Mack, ODP GLM | stages 0 to 3: about a day |
| 1 | bCCNN main fit under its three variants; NN chain ladder main runs and analysis, both codings; partition figures | |
| 2 | benchmark: one run of every queue of the later stages, then `final run status.R`: the estimate of the whole run from the VM's own times, pushed with the stage | |
| 3 | bCCNN search, bootstrap of each variant and its analysis, masking study and its analysis; `final run timings.R` for what is there | |
| 4, 5 | NN chain ladder, dummy coding: the two grids, the analysis again after each, the status again after each grid of the first data set (4); the three searches (5) | stages 4 to 7: about 8 days |
| 6, 7 | NN chain ladder, numeric coding: the two grids and the analysis, then the two codings compared (6); the three searches (7) | |
| 8 | bCCNN grid and its analysis; the status again after the grid of the first data set | about 13 days |
| 9 | `final run timings.R` for everything, then `final run status.R` as the last task | minutes |

About three weeks in all. The status script reckons with every processor busy to the end and
gives the earliest end. It leaves out the tasks that have no time yet (a search before any
search has finished) and says how many those are. **After stage 2 its hours for the grids are
too low**: the benchmark run of a grid is its first and cheapest run. The grids of the NN chain
ladder start with one hidden layer, SGD and the 100 epochs of the paper: in the earlier
random-start grid on the laptop that run took 260 and 390 s (two seeds) against a mean of about
1,000 s (a few runs over 5,000 s left aside; an early-stopping run took about 1,800 s), a
third of the mean run. The bCCNN grid starts with one hidden layer and the full batch, and half
its runs use batches of 64 (several steps an epoch). The column `seconds_runs` of `status.csv`
tells on how many run files a time rests, and the script counts the queues timed from less than
5% of their runs. A queue with fewer runs than that is timed by the runs of the same grid on
the other data sets and coding. The estimate of each of the two NN chain ladder grids is
therefore firm once its first queue has fitted one seed (60 runs: every setting once), and the
run writes it with `status.nncl.grid` and `status.nncl.cl_grid`, within the first two days of
stage 4. The bCCNN grid goes setting by setting (20 seeds each, the largest networks last), so
its estimate keeps moving through stage 8.

**If the fingerprint check fails** (`<dataset>.fingerprint.failed` in `results\final-run\failed\`;
in the smoke test, where it runs first, in `results\final-run\quick\failed\` and in
`results\final-run\quick\smoke_failed.txt`): the claims simulated on the VM are not those of
the laptop, and every task of that data set is blocked. Copy the claims from the laptop and
tell the launcher that the simulation is done:

1. Copy the folders `claim-simulation-annual`, `claim-simulation-annual-SI-calendar` and
   `claim-simulation-annual-long-reporting` (data sets `baseline`, `si_calendar`,
   `long_reporting`; all their files) from `data\raw` of the laptop into `data\raw` of the
   project folder on the VM, over the folders there.
2. In a PowerShell, from the project folder, write the done markers of the simulations of the
   final run, so that it does not simulate over the copies (those of the smoke test are there
   already if it got that far):

   ```
   $done = "..\Masters-Research-R-results\results\final-run\done"
   New-Item -ItemType Directory -Force $done
   foreach ($d in "baseline", "si_calendar", "long_reporting") {
     Set-Content "$done\$d.simulation.done" "copied from the laptop, 0 s"
   }
   ```

3. Start the launcher again (step 4).

**If a task fails**: a session that ends with an error is tried again after 60 s and after
10 minutes; after three failures in a row the task is given up for this round and the tasks
that need it are reported as blocked. The reason and the last lines of its log are in
`results\final-run\failed\<task>.failed`, the whole output of its sessions in
`results\final-run\logs\<task>_slot<k>.log` (smoke test: `results\final-run\quick\...`). When
everything else is done the launcher tries the failed tasks once more, then ends with exit
code 1 and lists them. Mend the cause (pull the corrected code with `git pull` in the project
folder) and start the launcher again: it tries the failed tasks and goes on with the rest. A
queue waits for its benchmark task: a failed `<queue>.benchmark` blocks all runs of that queue
(and `status.benchmark`, and with it the later status tasks) until it succeeds, in the second
round or at a later launch; the queue then goes on. To have a finished task of one R session
run again, delete its marker `results\final-run\done\<task>.done`; to have a run fitted again,
delete its file.

**Variants of the launch command**: `-Slots 12` (R sessions at once; default: the processors),
`-SkipSmoke` (no smoke test), `-Profile quick` (only the smoke-test table), `-NoPush` (nothing
is committed and pushed), `-PushHours 3` (hours between two pushes; default 6), `-Rounds 1` (no
second round for the failed tasks), `-QuietHours 12` (a session without output and without a
new run file for so long is named in the progress line; default 6), `-RunRoot <folder>`,
`-Rscript <path of bin\x64\Rscript.exe>`, `-Python uv` or `-Python <python.exe>`.

**To repeat the smoke test** (after a change of the code, say) delete its state and its fits,
with the launcher stopped, from the project folder:

```
Remove-Item -Recurse "..\Masters-Research-R-results\results\final-run\quick"
Remove-Item -Recurse "..\Masters-Research-R-results\results\data\processed\quick"
```

Deleting `smoke.done` alone repeats nothing: the done markers and run files of the quick
profile are still there, the launcher finds every task done and writes `smoke.done` again.
`results\data\interim` is shared with the final run and stays (the smoke test simulates the
same claims and writes the same triangles and cells again).

**Exit codes** of `launch.ps1`: 0 every task done; 1 tasks failed or blocked, or the smoke test
failed; 2 another launcher is running for the same folder; 3 the launcher itself failed (its
last lines say why: R, the Python environment or the results worktree not found, a wrong task
table, a `.Renviron` that sets one of the launcher's variables such as `DATASET` or `RUN_ROOT`;
`RAW_DIR` is fine there).

The task table is written by `final run tasks.R` at every launch
(`results\final-run\tasks.csv`; its columns are the contract at the top of `launch.ps1`). A
queue is a fit script whose runs several R sessions share; a session fits a number of runs
(`max_runs` at the top of `final run tasks.R`: 8 for the NN chain ladder, 20 for the bCCNN
grid, 1 bootstrap chunk, 5 masking seeds) and ends, and the launcher starts a fresh one.

## The final run on the HPC (Linux, PBS)

A second way to run the same task table, written on 2026-10-08 for the cluster of Stellenbosch
University (`hpc1.sun.ac.za`, `hpc2.sun.ac.za`; PBS): in `analysis/06_final-run/`

- `setup_hpc.sh`: once on the login node: the R module of the cluster, the R packages of
  `renv.lock` built from their sources, the unit tests, the Python environment of
  `requirements.txt` in `../Masters-Research-R-python/env`, the checks of the launcher and
  `keras check.R`;
- `hpc_job.sh`: the PBS job (one node, 48 processors, 120 GB, 168 hours); its header has the
  resources, the variables and the commands to watch, stop and fetch the results;
- `launch.py`: the launcher for Linux, the counterpart of `launch.ps1` under the same contract
  (Python 3.6 or later, standard library only), and `launch_test.py`, its checks with Python
  standing in for Rscript.

**They have never run on Linux.** On the laptop (Windows) `launch_test.py` passes and
`launch.py` completed the quick task table with the stand-in of the rehearsal; the parts that
only exist on Linux (process groups, the signals of PBS, the two bash scripts, the R module,
the build of the R packages and of the Python environment on the cluster) get their first run
there. What differs from the VM:

- the results are not pushed to GitHub: they stay under `../Masters-Research-R-results/results`
  on the cluster and are copied to the laptop when the run is done (the commands are in the
  header of `hpc_job.sh`);
- the cluster's R is 4.5.1 and the laptop's 4.6.1. A simulation under R 4.5 on Linux gave
  another portfolio before, so the fingerprint check may stop the run there: then copy the
  folders of `data/raw` from the laptop, as under "If the fingerprint check fails" in the
  section on the VM;
- the repository is private: the clone on the cluster asks for the GitHub user name and a
  personal access token.

From the login node, after the clone, in the project folder:

```
bash analysis/06_final-run/setup_hpc.sh
qsub -v FINAL_RUN_ARGS="--profile quick" -l walltime=12:00:00 analysis/06_final-run/hpc_job.sh
qsub analysis/06_final-run/hpc_job.sh
```

The second line is a first try with the quick profile only; the third is the final run (the
smoke test first, then every task). A job that ends before all is done is submitted again with
the same command and resumes. `qstat -u $USER` shows the job, `qdel <job id>` stops it, and
`tail -n 20 ../Masters-Research-R-results/results/final-run/launch.log` shows the events.

## How the results reach GitHub

The results are on the branch `results/final-run`: an orphan branch (no code, no history shared
with `main`) that is checked out on the VM in its own worktree, `..\Masters-Research-R-results`
beside the project. The launcher sets `RUN_ROOT` to its folder `results`, so the R scripts write
their interim files, run files, tables, figures and logs straight into that worktree, and the
launcher commits and pushes it after every completed stage, every six hours and at the end. The
commit message names the stage, the code commit and the computer. A failed push is logged and
tried again at the next occasion; the last lines of the launcher say if the last one failed.

- **Pushed**: tables, figures and logs (`results/output/`), the run files with their training
  times (`results/data/processed/`), `triangles.rds` and the cells and network inputs of the NN
  chain ladder on SynthETIC (`results/data/interim/`), the state of the launcher
  (`results/final-run/`: `tasks.csv`, `launch.log`, `status.csv`, `status_stages.csv`,
  `run_info.txt`, `done/`, `failed/`, `logs/`), the same of the smoke test (`quick` folders).
  The versions of the run: `run_info.txt` (computer, R, Python, code commit and slots of every
  launch), `results/output/logs/baseline/python_packages.txt` and `r_packages.txt` (every Python
  package, and the R session with keras3 loaded, from `keras check.R`) and `renv.lock` at the
  code commit (the R packages the setup installs). No fit session writes a `sessionInfo.txt`
  in the final run; the one in `results/output/logs/baseline/` is of the session that writes
  the task table (no Keras).
- **Stays on the VM**: the simulated claims (`data\raw` of the project folder), the Keras models
  (`*.keras`), the other interim files, lock and temporary files of running sessions, and any
  file over 50 MB (the launcher lists those at the end of the `.gitignore` of the worktree;
  GitHub refuses files over 100 MB).
- **Sign-in**: once, in the setup, through the Git Credential Manager; the launcher uses the
  stored credential and never asks.
- Nothing else may push to `results/final-run` while the run is going: the push of the VM would
  be refused. On the laptop only fetch and read until the run has finished.

`analysis/06_final-run/results_readme.md` is the README of that branch.

## Reading the results on the laptop

From the project folder, once (PowerShell, then bash):

```
git fetch origin
git worktree add ..\Masters-Research-R-results results/final-run
```

```
git fetch origin
git worktree add ../Masters-Research-R-results results/final-run
```

and later, for the newest push of the VM:

```
git -C ../Masters-Research-R-results pull
```

While the run is going, the laptop only reads that worktree. A script run on it (below) writes
there: its tables and figures, `status.csv` and `status_stages.csv`, `sessionInfo.txt`. Such a
file stands in the way of a later pull as soon as the VM pushes the same file: git names the
files and stops. Then

```
git -C ../Masters-Research-R-results status --short
git -C ../Masters-Research-R-results restore .
```

show what the laptop changed in the worktree and put the changed files back as the VM pushed
them (the scripts can be run again; a file the laptop added and git names is deleted by hand).
Pull again.

With `RUN_ROOT` on the folder `results` of that worktree, every analysis script without Keras,
the timings script and the status script run on the results of the VM, with `DATASET`,
`VALIDATION`, `FINAL_FIT` and `R_CONFIG_ACTIVE` as for the fits. The status script takes the
processors of the VM from `results/final-run/run_info.txt` (the slots of its last launch), not
those of the laptop. PowerShell:

```
$env:RUN_ROOT = "../Masters-Research-R-results/results"
$env:DATASET = "baseline"
Rscript "analysis/03_bCCNN/bCCNN grid analysis.R"
Rscript "analysis/06_final-run/final run timings.R"
Rscript "analysis/06_final-run/final run status.R"
Remove-Item Env:RUN_ROOT, Env:DATASET
```

bash:

```
export RUN_ROOT=../Masters-Research-R-results/results
DATASET=baseline Rscript "analysis/03_bCCNN/bCCNN grid analysis.R"
DATASET=si_calendar R_CONFIG_ACTIVE=age_numeric Rscript \
  "analysis/04_nn-chain-ladder/trackA_wuthrich2018/NN chain ladder SynthETIC analysis.R"
DATASET=baseline Rscript "analysis/06_final-run/final run timings.R"
unset RUN_ROOT
```

The analysis scripts: `bCCNN bootstrap analysis.R` (with the variant), `bCCNN masking
analysis.R`, `bCCNN grid analysis.R`, `bCCNN partitions.R`, `NN chain ladder SynthETIC
analysis.R`, `... partition.R`, `... age coding.R`. They write their tables and figures into the
worktree (`git -C ../Masters-Research-R-results status` shows them); commit and push them only
after the run on the VM has finished.

## Training times

Every saved run carries its wall-clock training times and where it was fitted (`info`: computer,
its processors, the R sessions fitting at the same time, the threads of each, the time):

| Run file | Seconds of the run and of its fits | Per epoch |
|---|---|---|
| `bccnn_fit_<variant>.rds` | `time` (early stopping, final fit, total, by the clock), `time_fit` (their Keras fits), `rolling_origin` (per partition: build, early-stopping run, test refit) | `history_validation`, `history_fit`, `epoch_time`: seconds of every step and of the prediction after it |
| `bccnn_bootstrap_<variant>_c<k>.rds` | `time` and `time_fit` of every refit | no |
| `bccnn_masking_fit_s<seed>.rds` | `run_time`, `time_fit` | `epoch_time`, milliseconds |
| `bccnn_grid_fit_<run>.rds` | `run_time`, `time_fit`, `rolling_origin` (per partition and rule) | `epoch_blocks` (mean milliseconds per 100 epochs) for every run, `epoch_time` (every epoch) for the first seed |
| `bccnn_tuning_search.rds`, `bccnn_tuning/<set>.rds` | per set `run_time`, `time_fit`; per fit in `runs` | `epoch_time`, `final_epoch_time` |
| `<tag>_fit_<run>.rds` (NN chain ladder) | per network: `run_time` (its epochs), `time_build`, `time_predict` | `history$time` of every network |
| `nncl_tuning/<tag>/<mode>/<set>.rds` | `run_time` of the set, `runs$time` per seed and valuation date | no |

`analysis/06_final-run/final run timings.R` (no Keras; per data set; a task of stages 3 and 9,
and by hand at any moment) collects them in `output/tables/<dataset>/06_final-run/`:

- `timings_runs.csv`: one row per fit: model, task, run, fit (network or partition), epochs,
  seconds of the fit, of the build and in total, seconds per epoch, seconds of the run, computer,
  processors, R sessions at once, threads, time;
- `timings_epochs.csv.gz`: one row per epoch (seconds of the step, and of the prediction for the
  bCCNN) of the fits kept in full: the bCCNN main fits, masking study, search and the first seed
  of its grid; the main runs of the NN chain ladder and the first seed of its grids and of the
  final fits of its searches (its run files keep every epoch of every run: tens of millions of
  rows a data set; of the other seeds `timings_runs.csv` has the totals per network);
- `timings_epoch_blocks.csv.gz`: the bCCNN grid, every run: mean milliseconds per block of 100
  epochs.

`final run status.R` reads the same seconds for its estimate (`results/final-run/status.csv`,
`status_stages.csv`).

## What has been executed

No model is fitted on the laptop (a decision of 2026-10-07: the networks are fitted on the VM
only). The fit and model scripts were refactored on 2026-10-07 for the data sets, the shared
runs, the stopping rules and the two NN chain ladder grids, and **have not been executed since**:
every script that loads Keras, the Mack and the ODP GLM script, the bootstrap, grid, masking
and NN chain ladder analysis scripts on real fits, `final run status.R` and
`final run timings.R` on real fits (they have only read run files that the fit scripts wrote
with stand-ins in place of Keras), the two description scripts after their last edits,
`keras check.R`, `setup_vm.ps1` (previewed with `-WhatIf` only), the build of the Python
environment (also the lines of `analysis/00_setup.R` that declare the Python packages, with a
real load of keras3) and the pushes to GitHub. They are covered by unit tests (functions, and
copies of the fit scripts run with stand-ins in place of Keras) and get their first execution
in the smoke test of the final run, which stops the run if one of them fails.

Executed on the laptop, according to the work log of 2026-10-07 and 2026-10-08:

- the simulations: the three SynthETIC data sets and the six lines of business, simulated
  again with the refactored scripts, byte-identical to the earlier data (md5 of the raw files);
- the fingerprints of all five data sets (written, and compared again: identical);
- `claims triangles.R`, and the cells script of the NN chain ladder for the three SynthETIC
  data sets under both codings of Age of Claimant (the zero claims factors of all three are
  finite; the pooled ones follow a first factor of 0);
- the seed study of the six lines of business under the `quick` profile (seeds 1, 2 and 75)
  and its analysis script;
- the unit tests and lint;
- the launcher with stand-in tasks: a rehearsal through `launch.ps1` as the VM starts it (the
  smoke test, then the final run; both task tables written by `final run tasks.R`), in which
  the script of every task but the status script was `tests/testthat/final_run_stand_in.R` (no
  Keras, no model: it checks that the files its script reads are there and writes stand-ins of
  what it writes). The quick table ran in full; the final table ran with the runs of its grids
  divided by 10 (2,580 of its 23,316 runs: the full numbers are checked by the unit tests, not
  by a launch). The results went to a git repository on the laptop, not to GitHub. Also
  `stop.ps1`, and the launcher's failures and restarts on small tables of stand-in tasks.

Not executed either: the seed study of the six lines of business with its 100 seeds, the
simulation of `machine4` under the present `config.yml`, and the scripts of the paper's NN
chain ladder (they are outside the final run). The thesis explainers in `thesis/` read tables
at the paths of before the data sets had folders of their own (`output/tables/...` without
`<dataset>`); their paths need updating before they are knitted again.

## Tests and lint

```
Rscript tests/testthat.R
Rscript -e "print(lintr::lint('R/nn_models.R'))"
```

All tests must pass and lint must print no lints (`.lintr`). The tests use no Keras. Three test
files run copies of the fit scripts with stand-ins for Keras in R sessions of their own and
take the most time (`test-bccnn_scripts.R`, `test-nncl_scripts.R`, `test-final_run_scripts.R`:
the status and timings scripts on the run files the fit scripts save). `test-final_run_tasks.R`
checks the task table of the final run against the contract of the launcher and against the
files each script reads and writes (`tests/testthat/final_run_files.R`).

A rehearsal of the launcher without a fit: `tests/testthat/final_run_stand_in_tasks.R`, given
to `launch.ps1` as `-TasksScript`, writes the real task table with the stand-in
`final_run_stand_in.R` as the script of every task; its header has the command (a scratch
folder as `-RunRoot`, `RAW_DIR` inside it, `-Python uv`, `-NoPush`).

## Branches

- `main`: the trunk; code only.
- `results/final-run`: the results of the final run only (an orphan branch, see above).
- `archive/six-lob-model-code`: a local branch with the model code once written for the six
  lines of business (joint bCCNN, LoB embedding); not used, kept for reference.

## Setup of a computer

For the VM see [The final run on the VM](#the-final-run-on-the-vm). Another computer:

1. R 4.6.1; the packages of `renv.lock`, for instance into the user library as the setup of
   the VM does (renv is not activated in the project; install renv first):

   ```
   Rscript -e "install.packages('renv', repos = 'https://cloud.r-project.org')"
   Rscript -e "renv::restore(lockfile = 'renv.lock', library = .libPaths()[1], prompt = FALSE)"
   ```

2. Keras runs on Python through reticulate. `analysis/00_setup.R` declares the pinned packages
   of `requirements.txt`, and reticulate builds the environment with uv when a script first
   loads keras3 (internet needed). To use an environment of your own, set
   `RETICULATE_PYTHON=<path>/python.exe` in `.Renviron`.
3. `.Renviron` in the project folder (not in git) for settings of the computer, such as
   `RAW_DIR=<folder of the simulated claims>`.
4. Keep `models/` and `.git` out of OneDrive sync.

## Notes on the strands

### SynthETIC description scripts

`SynthETIC claims description.R` (about 30 s): the portfolio at the valuation date (end of year
20): accident years, claim sizes, delays, reported claims and claim status (Risks Tables 3 and
6), triangles, development factors, calendar years and Mack's chain ladder against the true
outstanding (Risks Tables 5 and 7); 19 tables `synthetic_data_t*.csv` and 12 figures.
`SynthETIC feature impact.R` (about 1 min): the five claim features: their design, the
portfolio mix against the design, and their impact on the claim size, the delays, the number of
payments, the payment pattern, the true outstanding and the chain-ladder factors and reserves
by level; 27 tables `synthetic_features_t*.csv` and 13 figures. Both measure on the full
simulation ("true") unless a table says "observed".

### NN chain ladder on SynthETIC

Cells (accident year, feature value) of the five covariates, all categorical: 14 dummies, or 11
inputs with Age of Claimant as an ordinal score (the midpoint of the age band, `age_midpoints`
in `config.yml`, scaled to [-1, 1] by the MinMaxScaler (3.8); the input still takes five
values). The networks are fitted on the payments in millions (SGD needs moderate gradients).
With at most a few thousand learning cells per development period the batch of 10,000 holds
all rows, so an epoch is one gradient step and a paper run is 100 steps. The portfolio is one
LoB, so a zero claims factor with a positive numerator over a zero denominator is pooled over
the accident years (own rule); SynthETIC pays no recoveries, so the zero claims features are
the cells with C = 0. The grids are of my own design (`nncl: grid:` and `cl_grid:` in
`config.yml`): hidden layers (20), (20, 20, 15) and (20, 15, 10) x ten optimisers (SGD, SGD
with momentum, Nesterov, Adagrad, Adadelta, RMSprop, Adam, AdamW, Adamax, Nadam) x two
trainings x 20 seeds, the runs named `grid_<hidden>_<optimizer>_<training>_s<seed>` and
`clgrid_...`. The analysis script writes per grid `nncl_synthetic_<grid>_layers_optimisers.csv`,
`_seed_spread.csv` and `_nagging.csv` (nagging predictors of Richman & Wuthrich 2020: the CL
factors averaged over blocks of 10 seeds) and a figure of the bias per training. The age coding
script compares the two codings run by run (same seed) on the reserves by age band against
three benchmarks with age the only feature.

### Six lines of business (Paper C Appendix A; Harkonen 2021 Section 3)

Six LoBs from the Gabrielli & Wuthrich (2018) machine V1, seed 75 (data set `lob6`; settings:
the `lob:` block of `config.yml`). Scripts in `analysis/00_claim-simulation/lines-of-business/`,
each sets `DATASET=lob6` itself:

1. `lines of business simulation.R`: Paper C Listing 1 line by line (`lob_simulate()` in
   `R/lob_simulation.R`). The machine has four LoBs; the paper's six are

   | LoB | portfolio (V, growth) | features of machine LoB | claims development of machine LoB |
   |---|---|---|---|
   | 1 | 1,000,000, 1% | 1 | 1 |
   | 2 | 1,000,000, 1% | 2 | 1 |
   | 3 | 200,000, 5% | 1 | 1 |
   | 4 | 1,000,000, 1% | 4 | 4 |
   | 5 | 1,000,000, 1% | 3 | 4 |
   | 6 | 200,000, 5% | 4 | 4 |

   Writes `claims.csv`, `triangles.csv`, `counts.csv`, `payments.csv` and `summary.csv` to
   `data/raw/claim-simulation-lob/`.
2. `data fingerprint.R` and `claims triangles.R` with `DATASET=lob6` (triangles per unit in
   `data/interim/lob6/lob1` ... `lob6`, `lob_all`)
3. `lines of business description.R`: Harkonen's Tables 1, 4, 5 and 12-17, Paper C Table 2 and
   her Figure 3 (`output/tables|figures/lob6/00_claim-simulation/lines-of-business/`)
4. `lines of business seed study.R`: the simulation repeated with seeds 1 to 100 (Paper C
   Table 8 and Figures 9-10), one file per seed (`data/processed/lob6/lob_seed_study_001.rds`
   to `_100.rds`, a saved seed is not simulated again); then
   `lines of business seed study analysis.R`

Every table has the rows `simulated`, `paper` and `difference`. Notes for another computer:
`rng_rounding: true` sets `sample.kind = "Rounding"` (R < 3.6: the paper is of 2018) in the
session and in the machine's workers; the features are drawn with `MASS::mvrnorm()`, whose
eigenvectors come from LAPACK, so another BLAS/LAPACK can give other features (compare
`sessionInfo.txt` in `output/logs/lob6/` between the computers).

### The paper's NN chain ladder (Wuthrich 2018, data set `machine4`)

1. `analysis/00_claim-simulation/individual_claims_simulation_machine.R` (about 7 min, peak
   about 20 GB): the paper's Listing 1 portfolio; writes
   `data/raw/claim-simulation-machine/claims.csv` (about 395 MB)
2. `.../trackA_wuthrich2018/simulated data description.R`: Risks Tables 3, 5, 6, 7
3. `.../trackA_wuthrich2018/NN chain ladder fit.R` (about 75 min on CPU; one R session): the
   networks of Listing 2 (q = 5, 10, 20), S1 to S4 and the zero claims factors; cells in
   `data/interim/machine4/`, fits in `data/processed/machine4/nncl_fit_<run>.rds`. Fits made
   before the data sets had folders of their own are read when copied there (the header of the
   script names the files)
4. `.../trackA_wuthrich2018/NN chain ladder analysis.R` (no Keras): reserves, EAJ Tables 2-5,
   Figures 2-4 and 7-9 (`output/tables|figures/machine4/04_NN-chain-ladder/`);
   `NN chain ladder learning cells.R`: the learning cells per network

Deviations from the paper: the zero claims features are the cells with C <= 0 (recoveries), 0/0
gives a factor 1, and a zero claims factor with a positive numerator over a zero denominator
takes the ratio pooled over the LoBs. `analysis/00_claim-simulation/Simulation.Machine.V1/` is
the authors' machine V1, unmodified: third-party code, not lint-clean.
