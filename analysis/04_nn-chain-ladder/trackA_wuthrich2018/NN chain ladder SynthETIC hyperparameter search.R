##########################################
#########  NN chain ladder on the SynthETIC portfolio: hyperparameters of
#########  each training mode chosen on rolling-origin folds
#########  Wuthrich (2018), EAJ 8:407-436, Section 3 and Listing 2; search
#########  after Al-Mudafer, Avanzi, Taylor & Wong (2021), Section 3.2
##########################################

## Own design, not in the paper (R/tuning.R, R/nncl_tuning.R). One search per
## training mode of "NN chain ladder SynthETIC fit.R":
##   cl_start   early stopping from the homogeneous CL factor (S3)
##   paper      random start, a fixed number of epochs (Listing 2)
##   early_stop early stopping from the random start (S2)
## each with the dropout rate (a dropout layer after every hidden layer, 0 =
## the network of the paper) and the activation among the hyperparameters
## (config nncl$tuning$modes: method, order, candidates).
## 1. the cells and network inputs of "NN chain ladder SynthETIC cells.R"
## 2. search: every set is scored at the valuation dates of the test
##    partitions of the rolling origin (cfg$data$rolling_origin: the end of
##    the years 15 and 18 of 20) -- per seed and date the networks
##    j = 1..tau - 1 fitted on the cells known then, the part-1 cells
##    projected to the end of year 20 and scored against the payments
##    observed -- pooled per test cell and averaged over the seeds; scored
##    sets are saved in <processed>/nncl_tuning/<tag>/<mode> and not
##    refitted when the script is run again
## 3. the chosen set refitted on the full triangle with final_seeds seeds, as
##    the runs of the fit script (<processed>/<tag>_fit_tuned_<mode>_s<seed>
##    .rds, a saved run is not refitted), and its reserves (5.1) for each
##    seed and for their average (nagging predictor), next to Mack's chain
##    ladder and the truth
## 4. tables to <tables>/04_NN-chain-ladder/<out_dir>:
##    nncl_tuning_<mode>_table, _runs, _best and _final.csv, and _path.csv
##    for a successive search (the mode paper is a grid search: no path);
##    _final.csv is written last
##
## Run from the project folder, one mode (one R session per mode) or all
## three in turn:
##   Rscript "<this script>" cl_start
## (R_CONFIG_ACTIVE=age_numeric for the numeric coding of Age of Claimant).
## The sets of a search are not shared between R sessions (R/runs.R: no
## claim, RUN_MAX does not end the session): one session scores them all.
## Run time: a set costs (seeds) x (14 + 17 networks); the default searches
## score at most 11 (cl_start), 27 (paper) and 11 (early_stop) sets.
## The test loss is the selection criterion here, so its value for the
## chosen set is optimistic; the reserves against the truth are the
## independent check.
source(here::here("analysis", "00_setup.R"))
library(keras3)
stopifnot(cfg$data$generator == "synthetic")

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # fits and tables in millions
tune_cfg <- cfg$nncl$tuning
tag <- cfg$nncl$synthetic$tag
age <- cfg$nncl$synthetic$age
tab_dir <- file.path(paths$tables, "04_NN-chain-ladder",
                     cfg$nncl$synthetic$out_dir)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

modes <- commandArgs(trailingOnly = TRUE)
if (length(modes) == 0) modes <- names(tune_cfg$modes)

## the training modes as the runs of the fit script at the paper's q_main
## neurons: Listing 2, S2 and S3 (Adam and early stopping); no dropout
runs <- nncl_runs(cfg$nncl, cfg$seed)
mode_runs <- list(paper = runs[[paste0("paper_q", cfg$nncl$model$q_main)]],
                  early_stop = runs$s2_early_stop,
                  cl_start = runs$s3_cl_start)
for (mode in names(mode_runs)) mode_runs[[mode]]$param$dropout <- 0

##########################################
#########  cells and network inputs (of the cells script)
##########################################

## cumulative payments C_{i,j}(x) of the cells, inputs of the feature values
## and feature value x_id of every cell; learning cells and part-1 diagonal
## cells at the end of year I, for the final fits
cells <- readRDS(file.path(paths$interim, "nncl_synthetic_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])
inputs <- readRDS(file.path(paths$interim, paste0(tag, "_inputs.rds")))
x_id <- inputs$x_id
x <- inputs$x[x_id, ]
learn_rows <- inputs$learn_rows
diag_rows <- inputs$diag_rows
m_diag <- n_ay - cells$i[diag_rows]
rows <- which(cells$i > 1)

## the truth, Mack's chain ladder and the zero claims ultimates (part 2 of
## (5.1), Section 4.2)
true_reserves <- sum(cum[, n_ay] - cells$c_diag)
mack <- nncl_mack(rowsum(cum, cells$i))
ult_zero <- readRDS(file.path(paths$processed,
                              "nncl_synthetic_zero_claims.rds"))$ult_zero

## reserves (5.1) from the CL factors f_x of the networks j = 1..J (feature
## values x networks), as the analysis script
total_reserves <- function(f_x) {
  f_diag <- f_x[x_id[diag_rows], ]
  fp <- exp(rowSums(ifelse(outer(m_diag, 1:(n_ay - 1), "<"), log(f_diag), 0)))
  if (!all(is.finite(fp))) return(NA_real_)
  fp_all <- rep(1, length(rows))
  fp_all[match(diag_rows, rows)] <- fp
  sum(nncl_reserves(rep(1, length(rows)),
                    cells$i[rows],
                    cells$c_diag[rows],
                    fp_all,
                    ult_zero)$reserve)
}

##########################################
#########  search and final fits per training mode
##########################################

for (mode in modes) {
  mc <- tune_cfg$modes[[mode]]
  run <- mode_runs[[mode]]
  defaults <- c(list(hidden = run$q), run$param)
  order <- unlist(mc$order)
  cat("==== ", mode, ": ", mc$method, " search\n", sep = "")

  ## 2. search; a scored set keeps the seconds of its fits (runs$time,
  ## run_time) and where it was fitted (info)
  search <- tune_search(
    function(hp) {
      c(nncl_tscv_score(cum,
                        cells$i,
                        x,
                        origins = n_ay - cfg$data$rolling_origin$test_periods,
                        hp = hp,
                        run = run,
                        seeds = tune_cfg$seeds,
                        units = units),
        list(info = run_info()))
    },
    candidates = mc$candidates,
    method = mc$method,
    start = if (mc$method == "successive") defaults[order] else list(),
    order = if (is.null(order)) names(mc$candidates) else order,
    cache_dir = file.path(paths$processed, "nncl_tuning", tag, mode)
  )
  print(search$table)
  if (!is.null(search$path)) print(search$path)
  cat(mode, " chosen: ", hp_label(search$best), "\n", sep = "")

  ## 3. the chosen set on the full triangle, final_seeds seeds; a run keeps
  ## its settings and the CL factors of the feature values (f_x), as in the
  ## fit script
  if (!is.null(search$best$hidden)) run$q <- search$best$hidden
  run$param <- modifyList(run$param,
                          search$best[setdiff(names(search$best), "hidden")])
  seeds <- cfg$seed + seq_len(tune_cfg$final_seeds) - 1
  run_names <- paste0("tuned_", mode, "_s", seeds)
  run_files <- file.path(paths$processed,
                         paste0(tag, "_fit_", run_names, ".rds"))
  for (k in seq_along(seeds)) {
    if (!claim_run(run_files[k])) next
    # Python and TensorFlow start here, not in the build time of the first
    # network, if the search was read from its saved sets (as the fit script)
    clear_session()
    run$param$seed <- seeds[k]
    fits <- nncl_run_fit(cum, x, learn_rows, inputs$x, run, units)
    save_run(
      list(run = run_names[k],
           age = age,
           q = run$q,
           param = run$param,
           cl_start = run$cl_start,
           hyperparameters = search$best,
           f_x = sapply(fits, `[[`, "f_new"),
           fits = lapply(fits, function(fit) {
             fit[setdiff(names(fit), c("f_learn", "f_new"))]
           }),
           info = run_info()),
      run_files[k]
    )
  }
  ## a final fit taken by another R session: the tables wait for it
  if (!all(file.exists(run_files))) next

  ## reserves of each seed and of the nagging predictor (the CL factors
  ## averaged over the seeds)
  f_seeds <- lapply(run_files, function(f) readRDS(f)$f_x)
  final <- data.frame(model = c(paste0("seed ", seeds), "nagging predictor",
                                "Mack chain ladder"),
                      reserves = c(sapply(f_seeds, total_reserves),
                                   total_reserves(Reduce(`+`, f_seeds) /
                                                    length(f_seeds)),
                                   sum(mack$by_origin$ibnr)))
  final$true_reserves <- true_reserves
  final$bias <- final$reserves - true_reserves
  final$bias_pct <- 100 * (final$reserves / true_reserves - 1)
  final$reserves <- final$reserves / units
  final$true_reserves <- final$true_reserves / units
  final$bias <- final$bias / units
  final$units <- units
  print(final)

  ## 4. tables
  out <- function(name) {
    file.path(tab_dir, paste0("nncl_tuning_", mode, "_", name, ".csv"))
  }
  fwrite(search$table, out("table"))
  if (!is.null(search$path)) fwrite(search$path, out("path"))
  fwrite(tuning_runs(search), out("runs"))
  fwrite(tuning_best(search), out("best"))
  fwrite(final, out("final"))
}
