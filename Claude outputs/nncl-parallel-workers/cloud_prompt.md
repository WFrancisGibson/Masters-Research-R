Refit the numeric-age ("age_numeric") grid of the NN chain ladder on the LAPTOP's portfolio in this cloud container and push the fit files to a branch. This is a long compute job (about 16 hours on 4 cores): keep going until every run is saved and pushed, or report exactly what blocked you. Do only this; storing the files on the laptop and the analysis happen on the laptop afterwards.

Repository: https://github.com/WFrancisGibson/Masters-Research-R

Prepared on origin: branch `age-numeric-laptop-portfolio` (commit 1795dbe = branch Formatted-bCCNN + four files):
- `data/interim/nncl_synthetic_cells.rds`: the laptop's cells (md5 b9cca58b4827572d9f53591ff0abc114);
- in `Claude outputs/nncl-parallel-workers/`: `setup_cloud.sh` (container setup, no claims simulation), `run_cells_queue.sh` (worker slots) and `worker_cells.R` (the fit script on the cells file; modes `fit` and `s4`). Read their header comments first.

They were tested on the laptop: the network inputs are identical to those of the raw-data path, a run fitted through `worker_cells.R` reproduces the laptop's fit exactly, and its S4 is identical.

Why the cells file matters (do not deviate): `data/raw` is not in git. An earlier cloud run (branch `claude/sleepy-planck-z3i47i`) simulated the claims again and got another portfolio (true reserves 9,459.1 million against the laptop's 9,626.8 million), so its 1,207 fits cannot be compared with the dummy-coded fits, which exist only on the laptop. Never use, merge or copy that branch's fits. Do NOT run `analysis/00_claim-simulation/short_tailed_claims.R`, do not create `data/raw`, do not run `NN chain ladder SynthETIC fit.R` directly, and do not edit the fit script. `worker_cells.R` stops with an error if the cells are not the laptop's (true reserves 9,626.8 million, 3,167 part-1 cells). If the md5 of the cells file differs from the one above, stop and report.

Steps

1. `git fetch origin age-numeric-laptop-portfolio && git checkout -B age-numeric-laptop-fits origin/age-numeric-laptop-portfolio`. Push only to `origin age-numeric-laptop-fits`: no force-push, no pull request, nothing to main, Formatted-bCCNN or the prepared branch.
2. Setup (10-25 minutes, every step is skipped when done): `bash "Claude outputs/nncl-parallel-workers/setup_cloud.sh"`. Then in every shell that runs R: `export PATH=/opt/mamba/envs/r/bin:$PATH` and `export RETICULATE_PYTHON=/opt/mamba/envs/r/bin/python`. Check: `Rscript -e 'library(keras3); library(data.table); library(ChainLadder); cat("ok\n")'`.
3. Dry check (under a minute, fits nothing): `R_CONFIG_ACTIVE=age_numeric Rscript "Claude outputs/nncl-parallel-workers/worker_cells.R" fit 0`. It must print `Age of Claimant: numeric, scaled midpoints -1 -0.556 -0.037 0.481 1` and `[1] 1206`. Then remove the lock directory it leaves: `find data/processed -maxdepth 1 -name "*.rds.lock" -type d -exec rmdir {} +`.
4. Start the workers: `"Claude outputs/nncl-parallel-workers/run_cells_queue.sh" <n> 8` with n about 1.5 x `nproc` (6 on 4 cores; about 1.3 GB of memory per slot). Leave `NNCL_SEEDS` unset: all 20 seeds, 1,206 runs. Logs: `output/logs/nncl_cells_age_numeric_<k>.log`. Progress: `ls data/processed | grep -c 'age_numeric_fit_.*rds$'`. If all slots have ended (`pgrep -f worker_cells` finds nothing) and runs are missing, start the script again (it clears stale locks). A run whose log shows NaN losses has diverged: that is a result, keep its file.
5. About every hour and at the end: `git add -f` the finished fit files (`data/processed/nncl_synthetic_age_numeric_fit_*.rds`, only files not modified in the last minute, never the `.lock` directories) and `models/nncl_synthetic_age_numeric`; commit (`age_numeric fits on the laptop's portfolio: N of 1206 runs`); `git push origin age-numeric-laptop-fits`.
6. When all 1,206 runs are saved and no worker is running: `R_CONFIG_ACTIVE=age_numeric Rscript "Claude outputs/nncl-parallel-workers/worker_cells.R" s4` (writes `data/processed/nncl_synthetic_age_numeric_fit_s4_balance.rds`).
7. Final check in R on all 1,207 files: readable, 19 networks, every `fits[[j]]$f_diag` of length 3167, element `age` equal to "numeric"; 60 grid files per seed 2026..2045 plus the seven main runs (paper_q5, paper_q10, paper_q20, s1_adam, s2_early_stop, s3_cl_start, s4_balance); list the runs with non-finite `f_diag` (diverged). Refit anything unreadable or of the wrong shape (delete the file, start the queue again).
8. Final commit with the logs (`git add -f output/logs/nncl_cells_age_numeric_*.log`), push, and confirm that `git ls-remote origin age-numeric-laptop-fits` equals the local HEAD and that the branch holds 1,207 fit files and 1,254 files in `models/nncl_synthetic_age_numeric/`.

Do not run the analysis or comparison scripts in the cloud.

Final report: the branch and commit, the number of fit and model files, the diverged runs (or none), the wall time, and the versions (`Rscript -e 'library(keras3); cat(R.version.string, "\n"); print(packageVersion("keras3")); print(tensorflow::tf_version())'`).
