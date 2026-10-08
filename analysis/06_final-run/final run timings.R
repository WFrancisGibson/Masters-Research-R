##########################################
#########  final run: the training times of the fits
#########  own design: the seconds the fit scripts save with their runs
#########  (R/runs.R, R/nn_models.R, R/nn_chain_ladder.R)
##########################################

## the training times of everything fitted so far on the data set of this
## session (environment variable DATASET), read from the run files (no Keras
## needed) and written to <tables>/06_final-run. A task of the final run
## after the first models and at the end; by hand at any moment, also while
## fits are running (a run being fitted has no run file yet):
##   Rscript "analysis/06_final-run/final run timings.R"
##
## timings_runs.csv: one row per fit, wall-clock seconds
##   model, task        bccnn or nncl; the task of the final run without its
##                      data set (bccnn.grid, nncl.cl_grid, nncl_numeric.main:
##                      the numeric coding of Age of Claimant)
##   run, fit           the run (network settings and seed, bootstrap chunk,
##                      set of a search) and its fit. bCCNN: <partition>
##                      early_stop or refit, partition 1, 2 (test partitions
##                      of the rolling origin), final, or halves (the claims
##                      split); a refit of the grid or the masking study
##                      also has its steps; refit <k> of the bootstrap. NN
##                      chain ladder: j<j>, the network of development
##                      period j
##   networks           networks in the row: 1; a set of a NN chain ladder
##                      search keeps one time per seed and valuation date
##                      (origin), that of its origin - 1 networks
##   epochs             epochs trained (bCCNN: gradient descent steps)
##   seconds_fit        of the Keras fit; masking study and the two final
##                      networks of the bCCNN search: the sum of its epochs
##   seconds_build      of building the network, where the run keeps it
##   seconds_total      of the whole fit, where the run keeps it: a refit of
##                      the bootstrap by the clock; a network of the NN chain
##                      ladder, build + epochs + predictions
##   seconds_per_epoch  seconds_fit / epochs
##   run_seconds        of the run by the clock (NN chain ladder: the sum of
##                      seconds_total; bCCNN search, final networks: of their
##                      Keras fits); the first run of an R session also
##                      starts Python
##   host, cores, workers, threads, time
##                      where and when the run was saved (run_info())
## timings_epochs.csv.gz: one row per epoch (model, task, run, fit, epoch,
##   seconds, seconds_predict: of the prediction of the triangle after the
##   step, bCCNN only) of the fits that keep every epoch and are kept here:
##   the bCCNN main fits, masking study and search and the first seed of its
##   grid; of the NN chain ladder the main runs and the first seed of its
##   grids and final fits of the searches. The run files of the NN chain
##   ladder keep the seconds of every epoch of every run (tens of millions
##   of rows a data set): of the other seeds timings_runs.csv has the totals
##   per network
## timings_epoch_blocks.csv.gz: the bCCNN grid, every run: mean milliseconds
##   of a step and of its prediction per block of 100 epochs of each fit
##   (block 0: the prediction of the start)
source(here::here("analysis", "00_setup.R"))
stopifnot(cfg$data$generator == "synthetic")
tab_dir <- file.path(paths$tables, "06_final-run")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

## the two codings of Age of Claimant of the NN chain ladder: the tag of
## their fits (as "NN chain ladder SynthETIC age coding.R") by the name of
## their tasks
tags <- sapply(c(nncl = "default", nncl_numeric = "age_numeric"), function(p) {
  config::get("nncl", config = p, file = here::here("config.yml"))$synthetic$tag
})
## the start of the names of the runs of its two grids: grid_, clgrid_
prefix <- sapply(nncl_grids(cfg$nncl), `[[`, "prefix")

##########################################
#########  functions
##########################################

## the saved runs of a pattern: the patterns end in [.]rds$, so never a
## temporary file (<run file>.tmp) or a lock directory (<run file>.lock)
run_files <- function(pattern, dir = paths$processed) {
  list.files(dir, pattern = pattern, full.names = TRUE)
}

## the fits of a run and the epochs of its fits: a row each
fits_of <- function(fit,
                    epochs,
                    seconds_fit,
                    seconds_build = NA_real_,
                    seconds_total = NA_real_,
                    networks = 1) {
  data.table(fit, networks, epochs, seconds_fit, seconds_build, seconds_total)
}
epochs_of <- function(fit, epoch, seconds, seconds_predict = NA_real_) {
  data.table(fit,
             epoch,
             seconds = round(seconds, 4),
             seconds_predict = round(seconds_predict, 4))
}

## per fit of the rows of epochs_of(): its epochs and the seconds of its
## steps and predictions (where a run keeps no seconds per fit)
epoch_sums <- function(e) {
  e[,
    .(epochs = max(epoch),
      seconds_fit = sum(seconds, seconds_predict, na.rm = TRUE)),
    by = fit]
}

## the rows of a run in timings_runs.csv: its fits (fits_of()) with the
## model, task and run, the seconds of the run and where it was saved
run_rows <- function(fits, model, task, run, run_seconds, info) {
  data.table(model = model,
             task = task,
             run = run,
             fits,
             seconds_per_epoch = ifelse(fits$epochs > 0,
                                        fits$seconds_fit / fits$epochs,
                                        NA),
             run_seconds = run_seconds,
             host = info$host,
             cores = info$cores,
             workers = info$workers,
             threads = info$threads,
             time = info$time)
}

runs_tab <- list()
epochs_tab <- list()
blocks_tab <- list()

##########################################
#########  bCCNN: main fits, bootstrap, masking study
##########################################

## "bCCNN fit.R", a file per variant. Rolling origin: per partition the
## early-stopping run and, at a test partition under the refit, the test
## refit (summary of rolling_origin_fit(), epoch_time); claims split: the
## early-stopping run on the training half; then the final refit
for (f in run_files("^bccnn_fit_[a-z_]+[.]rds$")) {
  x <- readRDS(f)
  task <- paste0("bccnn.fit.", x$variant)
  h <- x$history_validation
  ro <- x$rolling_origin
  if (is.null(ro)) {
    fits <- fits_of("halves early_stop",
                    max(h$epoch),
                    x$time_fit[["early_stopping"]])
    epochs <- epochs_of("halves early_stop", h$epoch, h$time, h$time_predict)
  } else {
    refit <- ro[!is.na(ro$time_refit), ]
    fits <- rbind(fits_of(paste(ro$partition, "early_stop"),
                          max(h$epoch),
                          ro$time_early_stop,
                          ro$time_build),
                  fits_of(paste(refit$partition, "refit", recycle0 = TRUE),
                          refit$best_epoch,
                          refit$time_refit))
    et <- x$epoch_time
    epochs <- epochs_of(paste(et$partition, et$fit),
                        et$epoch,
                        et$time,
                        et$time_predict)
  }
  if (endsWith(x$variant, "_refit")) {
    h <- x$history_fit
    fits <- rbind(fits,
                  fits_of("final refit", x$epochs, x$time_fit[["final_fit"]]))
    epochs <- rbind(epochs,
                    epochs_of("final refit", h$epoch, h$time, h$time_predict))
  }
  runs_tab[[f]] <- run_rows(fits, "bccnn", task, x$variant,
                            x$time[["total"]], x$info)
  epochs_tab[[f]] <- data.table(model = "bccnn", task = task,
                                run = x$variant, epochs)
}

## "bCCNN bootstrap fit.R", a file per chunk of refits: the seconds of every
## refit by the clock (time) and of its Keras fit (time_fit)
for (f in run_files("^bccnn_bootstrap_[a-z_]+_c[0-9]+[.]rds$")) {
  x <- readRDS(f)
  name <- sub("^bccnn_bootstrap_(.*)_(c[0-9]+)[.]rds$", "\\1 \\2", basename(f))
  name <- strsplit(name, " ")[[1]]             # variant and chunk
  fits <- fits_of(paste("refit", x$refits),
                  x$key$epochs,
                  x$time_fit,
                  seconds_total = x$time)
  runs_tab[[f]] <- run_rows(fits, "bccnn", paste0("bccnn.bootstrap.", name[1]),
                            name[2], sum(x$time), x$info)
}

## "bCCNN masking fit.R", a file per seed: the milliseconds per epoch of the
## early-stopping run on the training half and of the final refits, one per
## number of steps
for (f in run_files("^bccnn_masking_fit_s[0-9]+[.]rds$")) {
  x <- readRDS(f)
  run <- paste0("s", x$seed)
  et <- x$epoch_time$claims_split
  epochs <- epochs_of("halves early_stop",
                      et$epoch,
                      et$time / 1000,
                      et$time_predict / 1000)
  for (s in names(x$epoch_time$refit)) {
    et <- x$epoch_time$refit[[s]]
    epochs <- rbind(epochs,
                    epochs_of(paste("final refit", s),
                              et$epoch,
                              et$time / 1000,
                              et$time_predict / 1000))
  }
  sums <- epoch_sums(epochs)
  runs_tab[[f]] <- run_rows(fits_of(sums$fit, sums$epochs, sums$seconds_fit),
                            "bccnn", "bccnn.masking", run, x$run_time, x$info)
  epochs_tab[[f]] <- data.table(model = "bccnn", task = "bccnn.masking",
                                run = run, epochs)
}

##########################################
#########  bCCNN: search and grid
##########################################

## "bCCNN hyperparameter search.R": a file per scored set in bccnn_tuning
## (per seed and test partition the early-stopping run and the test refit:
## runs, and the milliseconds of their epochs: epoch_time), and the two
## final networks in the file of the finished search (final_epoch_time)
for (f in run_files("[.]rds$", file.path(paths$processed, "bccnn_tuning"))) {
  x <- readRDS(f)
  et <- x$epoch_time
  r <- x$runs
  r$partition <- ave(r$seed, r$seed, FUN = seq_along)  # 1, 2 per seed
  refit <- r[!is.na(r$time_refit), ]
  fits <- rbind(fits_of(paste("seed", r$seed, r$partition, "early_stop"),
                        max(et$epoch),
                        r$time_early_stop),
                fits_of(paste("seed", refit$seed, refit$partition, "refit",
                              recycle0 = TRUE),
                        refit$steps,
                        refit$time_refit))
  runs_tab[[f]] <- run_rows(fits, "bccnn", "bccnn.search", x$label,
                            x$run_time, x$info)
  epochs_tab[[f]] <- data.table(model = "bccnn",
                                task = "bccnn.search",
                                run = x$label,
                                epochs_of(paste("seed", et$seed,
                                                et$partition, et$fit),
                                          et$epoch,
                                          et$time / 1000,
                                          et$time_predict / 1000))
}
for (f in run_files("^bccnn_tuning_search[.]rds$")) {
  x <- readRDS(f)
  for (m in names(x$final_epoch_time)) {
    et <- x$final_epoch_time[[m]]
    run <- paste("final", m)
    epochs <- epochs_of(paste(et$partition, et$fit),
                        et$epoch,
                        et$time / 1000,
                        et$time_predict / 1000)
    sums <- epoch_sums(epochs)
    runs_tab[[paste(f, m)]] <- run_rows(
      fits_of(sums$fit, sums$epochs, sums$seconds_fit),
      "bccnn", "bccnn.search", run,
      x$final$seconds[x$final$model == m], x$info
    )
    epochs_tab[[paste(f, m)]] <- data.table(model = "bccnn",
                                            task = "bccnn.search",
                                            run = run,
                                            epochs)
  }
}

## "bCCNN grid fit.R", a file per run: per partition the validation run and
## one refit per number of steps of the stopping rules (rolling_origin: a
## row per partition and rule); epoch_blocks of every run, the milliseconds
## of every epoch (epoch_time) of the runs of the first seed
grid_fit <- function(partition, fit, steps) {
  ifelse(fit == "refit", paste(partition, fit, steps), paste(partition, fit))
}
for (f in run_files("^bccnn_grid_fit_.*[.]rds$")) {
  x <- readRDS(f)
  ro <- x$rolling_origin
  blocks <- x$epoch_blocks
  early <- unique(ro[c("partition", "time_build", "time_early_stop")])
  refit <- unique(ro[!is.na(ro$time_refit),
                     c("partition", "steps", "time_refit")])
  fits <- rbind(fits_of(paste(early$partition, "early_stop"),
                        max(blocks$steps[blocks$fit == "early_stop"]),
                        early$time_early_stop,
                        early$time_build),
                fits_of(paste(refit$partition, "refit", refit$steps,
                              recycle0 = TRUE),
                        refit$steps,
                        refit$time_refit))
  runs_tab[[f]] <- run_rows(fits, "bccnn", "bccnn.grid", x$run, x$run_time,
                            x$info)
  blocks_tab[[f]] <- data.table(
    model = "bccnn",
    task = "bccnn.grid",
    run = x$run,
    fit = grid_fit(blocks$partition, blocks$fit, blocks$steps),
    block = blocks$block,
    milliseconds = blocks$time,
    milliseconds_predict = blocks$time_predict
  )
  et <- x$epoch_time
  if (!is.null(et)) {
    epochs_tab[[f]] <- data.table(model = "bccnn",
                                  task = "bccnn.grid",
                                  run = x$run,
                                  epochs_of(grid_fit(et$partition, et$fit,
                                                     et$steps),
                                            et$epoch,
                                            et$time / 1000,
                                            et$time_predict / 1000))
  }
}

##########################################
#########  NN chain ladder, both codings of Age of Claimant
##########################################

for (k in names(tags)) {
  ## the runs of the fit script and the final fits of the search script,
  ## <tag>_fit_<run>.rds: main runs, grid_ and clgrid_ runs, tuned_<mode>_
  ## fits (S4, s4_balance, is S3 with a correction: no fit of its own). Per
  ## network j the epochs run and the seconds of its build, its epochs and
  ## its predictions; the seconds of every epoch (history) are kept for the
  ## main runs and the first seed
  for (f in run_files(paste0("^", tags[[k]], "_fit_.*[.]rds$"))) {
    run <- sub(paste0("^", tags[[k]], "_fit_(.*)[.]rds$"), "\\1", basename(f))
    if (run == "s4_balance") next
    part <- "main"
    for (g in names(prefix)) if (startsWith(run, prefix[[g]])) part <- g
    if (startsWith(run, "tuned_")) {
      part <- paste0("search.", sub("^tuned_(.*)_s[0-9]+$", "\\1", run))
    }
    task <- paste0(k, ".", part)
    x <- readRDS(f)
    nets <- x$fits
    j <- paste0("j", seq_along(nets))
    seconds_fit <- sapply(nets, `[[`, "run_time")
    seconds_build <- sapply(nets, `[[`, "time_build")
    seconds_total <- seconds_fit + seconds_build +
      sapply(nets, `[[`, "time_predict")
    fits <- fits_of(j,
                    sapply(nets, `[[`, "epochs_run"),
                    seconds_fit,
                    seconds_build,
                    seconds_total)
    runs_tab[[f]] <- run_rows(fits, "nncl", task, run, sum(seconds_total),
                              x$info)
    if (part == "main" || x$param$seed == cfg$seed) {
      h <- lapply(nets, `[[`, "history")
      epochs_tab[[f]] <- data.table(
        model = "nncl",
        task = task,
        run = run,
        epochs_of(rep(j, sapply(h, nrow)),
                  unlist(lapply(h, `[[`, "epoch")),
                  unlist(lapply(h, `[[`, "time")))
      )
    }
  }
  ## the scored sets of the search script, nncl_tuning/<tag>/<mode>: per
  ## seed and valuation date (origin) the seconds of the epochs of its
  ## networks j = 1..origin - 1 together (runs$time)
  set_files <- list.files(file.path(paths$processed, "nncl_tuning",
                                    tags[[k]]),
                          pattern = "[.]rds$",
                          recursive = TRUE,
                          full.names = TRUE)
  for (f in set_files) {
    x <- readRDS(f)
    r <- x$runs
    fits <- fits_of(paste("seed", r$seed, "origin", r$origin),
                    NA_real_,
                    r$time,
                    networks = r$origin - 1)
    runs_tab[[f]] <- run_rows(fits,
                              "nncl",
                              paste0(k, ".search.", basename(dirname(f))),
                              x$label,
                              x$run_time,
                              x$info)
  }
}

##########################################
#########  tables
##########################################

## a table without rows keeps its columns (nothing of its kind fitted yet)
runs_tab <- rbindlist(c(
  list(run_rows(fits_of(character(), numeric(), numeric()),
                character(), character(), character(), numeric(),
                list(host = character(), cores = numeric(),
                     workers = numeric(), threads = character(),
                     time = character()))),
  runs_tab
))
epochs_tab <- rbindlist(c(
  list(data.table(model = character(), task = character(),
                  run = character(),
                  epochs_of(character(), numeric(), numeric()))),
  epochs_tab
))
blocks_tab <- rbindlist(c(
  list(data.table(model = character(), task = character(),
                  run = character(), fit = character(), block = numeric(),
                  milliseconds = numeric(),
                  milliseconds_predict = numeric())),
  blocks_tab
))

## per task: runs, fits, networks and hours (fit: the Keras fits; run: the
## runs by the clock) and the mean seconds of an epoch
by_task <- runs_tab[,
                    .(runs = uniqueN(run),
                      fits = .N,
                      networks = sum(networks),
                      hours_fit = sum(seconds_fit) / 3600,
                      hours_run = sum(run_seconds[!duplicated(run)]) / 3600,
                      seconds_per_epoch = sum(seconds_fit[!is.na(epochs)]) /
                        sum(epochs, na.rm = TRUE)),
                    by = .(model, task)]
cbind(by_task[, 1:5], round(by_task[, 6:8], 4))
c("rows of timings_epochs" = nrow(epochs_tab),
  "rows of timings_epoch_blocks" = nrow(blocks_tab))

fwrite(runs_tab, file.path(tab_dir, "timings_runs.csv"))
fwrite(epochs_tab, file.path(tab_dir, "timings_epochs.csv.gz"))
fwrite(blocks_tab, file.path(tab_dir, "timings_epoch_blocks.csv.gz"))
