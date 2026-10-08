##########################################
#########  final run: the files the script of a task reads and writes
#########  (analysis/06_final-run), read off the scripts; for
#########  test-final_run_tasks.R and the stand-in final_run_stand_in.R
##########################################

## script: the file name of the script of a task, args: its arguments, cfg:
## config.yml as its R session reads it (profile, DATASET, VALIDATION and
## FINAL_FIT of the task), run_root and raw: RUN_ROOT and the folder of the
## simulated claims. Returns the files the script
##   reads   and that another task writes (they must be there at its start)
##   writes  without a claim (the tables and figures are not listed)
##   runs    as a queue, in the order of its loop: the run files it claims
##   with    saves with a run: S4 of the NN chain ladder with S3
## scale: a rehearsal can do with a part of the grids, the first 1 / scale
## of their runs (1: all of them, the final run).
## Needs the run lists nncl_runs() and bccnn_grid_runs(), functions of the
## files nn_chain_ladder.R and nn_models.R in R/
final_run_files <- function(script, args, cfg, run_root, raw, scale = 1) {
  first <- function(x) x[seq_len(ceiling(length(x) / scale))]
  d <- cfg$dataset
  raw_dir <- file.path(raw, cfg$datasets[[d]]$dir)
  interim <- file.path(run_root, cfg$paths$interim, d)
  processed <- file.path(run_root, cfg$paths$processed, d)
  claims <- file.path(raw_dir, c("claims.csv", "transactions.csv"))
  design <- file.path(raw_dir, c("covariates_freq_relativities.csv",
                                 "covariates_sev_relativities.csv",
                                 "delay_multipliers.csv"))
  factors <- file.path(raw_dir, "covariates_5factor.rds")
  triangles <- file.path(interim, "triangles.rds")
  ## bCCNN: the variant of the session, as "bCCNN fit.R" names it
  train_cfg <- cfg$bccnn$training
  final_fit <- if (train_cfg$validation == "claims_split") "refit" else
    train_cfg$final_fit
  variant <- paste(train_cfg$validation, final_fit, sep = "_")
  bccnn_fit <- file.path(processed, paste0("bccnn_fit_", variant, ".rds"))
  nsim <- cfg$bccnn$bootstrap$nsim
  chunks <- seq_along(unique(ceiling(cfg$bccnn$bootstrap$chunks *
                                       seq_len(nsim) / nsim)))
  bootstrap <- file.path(processed,
                         paste0("bccnn_bootstrap_", variant, "_c", chunks,
                                ".rds"))
  masking <- file.path(processed,
                       paste0("bccnn_masking_fit_s",
                              cfg$seed + seq_len(cfg$bccnn$masking$seeds) - 1,
                              ".rds"))
  ## the run lists of the grids take a moment: built when a script below
  ## uses them (delayedAssign)
  delayedAssign("grid",
                first(file.path(processed,
                                paste0("bccnn_grid_fit_",
                                       names(bccnn_grid_runs(cfg$bccnn$grid,
                                                             cfg$seed)),
                                       ".rds"))))
  ## NN chain ladder: the files of the cells script and the runs of the
  ## coding of the session (tag), by part of the fit script
  tag <- cfg$nncl$synthetic$tag
  cells <- file.path(interim, "nncl_synthetic_cells.rds")
  inputs <- file.path(interim, paste0(tag, "_inputs.rds"))
  homogeneous <- file.path(processed, "nncl_synthetic_homogeneous.rds")
  zero <- file.path(processed, "nncl_synthetic_zero_claims.rds")
  delayedAssign("runs", nncl_runs(cfg$nncl, cfg$seed))
  delayedAssign("part", sapply(runs, `[[`, "part"))
  part_runs <- function(p) {
    if (p == "main") names(runs)[part == p] else first(names(runs)[part == p])
  }
  nncl_fit <- function(tag, run) {
    file.path(processed, paste0(tag, "_fit_", run, ".rds"))
  }
  delayedAssign("main", nncl_fit(tag, c(part_runs("main"), "s4_balance")))
  ## both codings, as "NN chain ladder SynthETIC age coding.R" reads them
  yml <- here::here("config.yml")
  tags <- sapply(c("default", "age_numeric"), function(p) {
    config::get("nncl", config = p, file = yml)$synthetic$tag
  })
  out <- switch(
    script,
    "keras check.R" = list(),
    "SynthETIC claims simulation.R" = list(writes = c(claims, design, factors)),
    "data fingerprint.R" = {
      stopifnot(identical(args, "check"),
                file.exists(here::here("analysis", "00_claim-simulation",
                                       "fingerprints", paste0(d, ".csv"))))
      list(reads = claims)
    },
    "claims triangles.R" = list(reads = claims[2], writes = triangles),
    "SynthETIC claims description.R" = list(reads = c(claims, factors)),
    "SynthETIC feature impact.R" = list(reads = c(claims, factors, design)),
    "Mack chainladder fit.R" = list(reads = triangles),
    "ODP glm fit plot.R" = list(reads = triangles),
    "bCCNN fit.R" = list(reads = triangles, writes = bccnn_fit),
    "bCCNN partitions.R" = list(reads = triangles),
    "bCCNN bootstrap fit.R" = list(reads = bccnn_fit, runs = bootstrap),
    "bCCNN bootstrap analysis.R" = list(reads = c(triangles, bccnn_fit,
                                                  bootstrap)),
    "bCCNN masking fit.R" = list(reads = triangles, runs = masking),
    "bCCNN masking analysis.R" = list(reads = c(triangles, masking)),
    "bCCNN hyperparameter search.R" = list(
      reads = triangles,
      writes = file.path(processed, "bccnn_tuning_search.rds")
    ),
    "bCCNN grid fit.R" = list(
      reads = c(triangles,
                file.path(processed, "bccnn_fit_rolling_origin_refit.rds")),
      runs = grid
    ),
    "bCCNN grid analysis.R" = list(reads = c(triangles, grid)),
    "NN chain ladder SynthETIC cells.R" = list(
      reads = claims,
      writes = c(cells, inputs, homogeneous, zero)
    ),
    "NN chain ladder SynthETIC fit.R" = {
      # as the script: an argument that is no part is an error
      stopifnot(length(args) > 0, args %in% part)
      s3 <- nncl_fit(tag, "s3_cl_start")
      list(reads = c(cells, inputs, homogeneous),
           runs = nncl_fit(tag, unlist(lapply(intersect(unique(part), args),
                                              part_runs))),
           with = setNames(nncl_fit(tag, "s4_balance"), s3))
    },
    "NN chain ladder SynthETIC analysis.R" = list(
      reads = c(cells, inputs, homogeneous, zero, main)
    ),
    "NN chain ladder SynthETIC partition.R" = list(reads = c(cells, inputs)),
    "NN chain ladder SynthETIC hyperparameter search.R" = {
      stopifnot(length(args) == 1, args %in% names(cfg$nncl$tuning$modes))
      seeds <- cfg$seed + seq_len(cfg$nncl$tuning$final_seeds) - 1
      list(reads = c(cells, inputs, zero),
           writes = nncl_fit(tag, paste0("tuned_", args, "_s", seeds)))
    },
    "NN chain ladder SynthETIC age coding.R" = list(
      reads = c(cells,
                zero,
                homogeneous,
                file.path(interim, paste0(tags, "_inputs.rds")),
                unlist(lapply(tags,
                              nncl_fit,
                              c(unlist(lapply(unique(part), part_runs)),
                                "s4_balance"))))
    ),
    "final run timings.R" = list(),
    "final run status.R" = list()
  )
  stopifnot("a script the final run does not know" = !is.null(out))
  out
}
