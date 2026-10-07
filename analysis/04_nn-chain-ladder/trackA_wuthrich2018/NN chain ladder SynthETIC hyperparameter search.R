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
## 1. the cells of the fit script (data/interim/nncl_synthetic_cells.rds,
##    written by its first part) and the same network inputs
## 2. search: every set is scored at the valuation dates 15 and 18 of 20 --
##    per seed and date the networks j = 1..tau - 1 fitted on the cells known
##    then, the part-1 cells projected to the end of year 20 and scored
##    against the payments observed -- pooled per test cell and averaged over
##    the seeds; scored sets are saved in data/processed/nncl_tuning/<tag>/
##    <mode> and not refitted when the script is run again
## 3. the chosen set refitted on the full triangle with final_seeds seeds, as
##    the runs of the fit script (data/processed/<tag>_fit_tuned_<mode>_s<seed>
##    .rds, not refitted when present), and its reserves (5.1) for each seed
##    and for their average (nagging predictor), next to Mack's chain ladder
##    and the truth
## 4. tables to output/tables/04_NN-chain-ladder/<out_dir>:
##    nncl_tuning_<mode>_*.csv
##
## Run from the project folder, one mode or all three in turn:
##   Rscript "analysis/04_nn-chain-ladder/trackA_wuthrich2018/NN chain ladder SynthETIC hyperparameter search.R" cl_start
## (R_CONFIG_ACTIVE=age_numeric for the numeric coding of Age of Claimant).
## Run time: a set costs (seeds) x (14 + 17 networks); the default searches
## score at most 11 (cl_start), 27 (paper) and 11 (early_stop) sets.
## The test loss is the selection criterion here, so its value for the
## chosen set is optimistic; the reserves against the truth are the
## independent check.
source(here::here("analysis", "00_setup.R"))
library(keras3)

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # fits and tables in millions
tune_cfg <- cfg$nncl$tuning
tag <- cfg$nncl$synthetic$tag
age <- cfg$nncl$synthetic$age
tab_dir <- file.path(paths$tables, "04_NN-chain-ladder",
                     cfg$nncl$synthetic$out_dir)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
features <- c("Legal Representation", "Injury Severity", "Age of Claimant",
              "Vehicle type", "Business use")

modes <- commandArgs(trailingOnly = TRUE)
if (length(modes) == 0) modes <- names(tune_cfg$modes)
stopifnot(all(modes %in% names(tune_cfg$modes)))

## the training modes as the runs of the fit script: param of Listing 2,
## param_s2 = Adam and early stopping (S1, S2); the paper's q_main neurons;
## no dropout
param <- list(activation = cfg$nncl$model$activation,
              optimizer = "rmsprop",
              learning_rate = cfg$nncl$sensitivity$learning_rate,
              epochs = cfg$nncl$training$epochs,
              batch_size = cfg$nncl$training$batch_size,
              validation_split = cfg$nncl$training$validation_split,
              early_stop = FALSE,
              patience = cfg$nncl$sensitivity$patience,
              dropout = 0,
              seed = cfg$seed)
param_s2 <- modifyList(param,
                       list(optimizer = "adam",
                            early_stop = TRUE,
                            epochs = cfg$nncl$sensitivity$max_epochs))
q_main <- cfg$nncl$model$q_main
mode_runs <- list(paper = list(q = q_main, param = param, cl_start = FALSE),
                  early_stop = list(q = q_main, param = param_s2,
                                    cl_start = FALSE),
                  cl_start = list(q = q_main, param = param_s2,
                                  cl_start = TRUE))

##########################################
#########  cells and network inputs (as the fit script)
##########################################

cells_file <- file.path(paths$interim, "nncl_synthetic_cells.rds")
if (!file.exists(cells_file)) {
  stop(cells_file, " is missing: it is written by the first part of ",
       "\"NN chain ladder SynthETIC fit.R\"")
}
cells <- readRDS(cells_file)
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])

## feature pre-processing of the fit script (Section 3.3): dummy coding with
## the label of most reported claims as reference; age "numeric": the band
## midpoint scaled to [-1, 1]
x <- NULL
for (v in features) {
  if (v == "Age of Claimant" && age == "numeric") {
    x_v <- unlist(cfg$nncl$synthetic$age_midpoints)[cells[[v]]]
    x_v <- 2 * (x_v - min(x_v)) / (max(x_v) - min(x_v)) - 1
    x <- cbind(x, unname(x_v))
  } else {
    n_lab <- cells[, .(n = sum(n_reported)), by = v]
    ref <- n_lab[[v]][which.max(n_lab$n)]
    lab <- relevel(factor(cells[[v]]), ref = as.character(ref))
    x <- cbind(x, model.matrix(~lab)[, -1])
  }
}

## learning cells and part-1 diagonal cells at the end of year I (the fit
## script), for the final fits
learn_rows <- lapply(1:(n_ay - 1), function(j) {
  which(cells$i <= n_ay - j & cum[, j] > 0)
})
diag_rows <- which(cells$i > 1 & cells$c_diag > 0)
x_diag <- x[diag_rows, ]
m_diag <- n_ay - cells$i[diag_rows]
rows <- which(cells$i > 1)

## the truth, Mack's chain ladder and the zero claims ultimates (part 2 of
## (5.1), from the fit script; part 1 only if it has not been run)
true_reserves <- sum(cum[, n_ay] - cells$c_diag)
mack <- nncl_mack(rowsum(cum, cells$i))
zero_file <- file.path(paths$processed, "nncl_synthetic_zero_claims.rds")
ult_zero <- if (file.exists(zero_file)) readRDS(zero_file)$ult_zero else
  matrix(0, 1, n_ay)

## reserves (5.1) from the CL factors f_diag of the networks j = 1..J
## (a matrix: diagonal cells x networks), as the analysis script
nncl_total_reserves <- function(f_diag) {
  fp <- exp(rowSums(ifelse(outer(m_diag, 1:(n_ay - 1), "<"), log(f_diag), 0)))
  if (!all(is.finite(fp))) return(NA_real_)
  fp_all <- rep(1, length(rows))
  fp_all[match(diag_rows, rows)] <- fp
  sum(nncl_reserves(rep(1, length(rows)), cells$i[rows], cells$c_diag[rows],
                    fp_all, ult_zero)$reserve)
}

##########################################
#########  search and final fits per training mode
##########################################

for (mode in modes) {
  mc <- tune_cfg$modes[[mode]]
  run <- mode_runs[[mode]]
  defaults <- c(list(hidden = run$q), run$param)
  order <- unlist(mc$order)
  message("==== ", mode, ": ", mc$method, " search")

  ## 2. search
  search <- tune_search(
    function(hp) {
      nncl_tscv_score(cum, cells$i, x,
                      origins = n_ay - unlist(tune_cfg$test_periods),
                      hp = hp, run = run,
                      seeds = unlist(tune_cfg$seeds),
                      units = units)
    },
    candidates = mc$candidates,
    method = mc$method,
    start = if (mc$method == "successive") defaults[order] else list(),
    order = if (is.null(order)) names(mc$candidates) else order,
    cache_dir = file.path(paths$processed, "nncl_tuning", tag, mode))
  print(search$table)
  if (!is.null(search$path)) print(search$path)
  message(mode, " chosen: ", hp_label(search$best))

  ## 3. the chosen set on the full triangle, final_seeds seeds
  q <- if (is.null(search$best$hidden)) run$q else search$best$hidden
  p_best <- modifyList(run$param,
                       search$best[setdiff(names(search$best), "hidden")])
  seeds <- cfg$seed + seq_len(tune_cfg$final_seeds) - 1
  f_seeds <- list()
  for (s in seeds) {
    run_name <- paste0("tuned_", mode, "_s", s)
    run_file <- file.path(paths$processed,
                          paste0(tag, "_fit_", run_name, ".rds"))
    if (!file.exists(run_file)) {
      p <- modifyList(p_best, list(seed = s))
      fits <- list()
      for (j in 1:(n_ay - 1)) {
        r <- learn_rows[[j]]
        c_prev <- cum[r, j] / units
        y <- cum[r, j + 1] / units / sqrt(c_prev)
        w <- matrix(sqrt(c_prev), ncol = 1)
        f_start <- NULL
        if (run$cl_start) {
          train <- seq_len(floor(length(r) * (1 - p$validation_split)))
          f_start <- sum(cum[r[train], j + 1]) / sum(cum[r[train], j])
        }
        fit <- nncl_fit(x[r, ], y, w, x_diag, q, p, f_start)
        fit$model <- NULL
        for (k in c("loss", "loss_train", "loss_vali")) {
          fit[[k]] <- units * fit[[k]]
        }
        fits[[j]] <- fit
      }
      saveRDS(list(run = run_name, age = age, q = q, param = p,
                   hyperparameters = search$best, fits = fits),
              run_file)
    }
    f_seeds[[as.character(s)]] <- sapply(readRDS(run_file)$fits,
                                         function(fit) fit$f_diag)
  }
  ## reserves of each seed and of the nagging predictor (the CL factors
  ## averaged over the seeds)
  res <- sapply(f_seeds, nncl_total_reserves)
  final <- data.frame(model = c(paste0("seed ", seeds), "nagging predictor",
                                "Mack chain ladder"),
                      reserves = c(res,
                                   nncl_total_reserves(Reduce(`+`, f_seeds) /
                                                         length(f_seeds)),
                                   sum(mack$by_origin$ibnr)))
  final$true_reserves <- true_reserves
  final$bias <- final$reserves - true_reserves
  final$bias_pct <- 100 * (final$reserves / true_reserves - 1)
  final$reserves <- final$reserves / units
  final$true_reserves <- final$true_reserves / units
  final$bias <- final$bias / units
  final$units <- units
  final$part2_included <- file.exists(zero_file)
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
