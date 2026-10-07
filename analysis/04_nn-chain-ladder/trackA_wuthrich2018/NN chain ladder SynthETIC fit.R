##########################################
#########  NN chain ladder on the SynthETIC portfolio: CL factor networks
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Section 3, Appendix 2 (Listing 2)
#########  data: SynthETIC, Avanzi, Taylor, Wang & Wong (2021)
##########################################

## the networks and runs of "NN chain ladder fit.R" on the cells of
## "NN chain ladder SynthETIC cells.R" (run that script first). Every run is
## saved in its own file and several R sessions can share the runs
## (R/runs.R); the tables and figures are those of "NN chain ladder SynthETIC
## analysis.R". An argument restricts the runs to those of the paper and
## S1-S4 (main) or to the hidden layers and optimisers (grid):
##   Rscript "<this script>" main
source(here::here("analysis", "00_setup.R"))
library(keras3)
stopifnot(cfg$data$generator == "synthetic")

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # fits and tables in millions
## Age of Claimant as four dummies or as an ordinal score
## (R_CONFIG_ACTIVE=age_numeric); the fits of the two codings are saved apart
## (tag)
age <- cfg$nncl$synthetic$age
tag <- cfg$nncl$synthetic$tag

## the runs of Listing 2 (Appendix 2), the sensitivity runs S1-S3 and the
## hidden layers and optimisers (own design, not in the paper)
runs <- nncl_runs(cfg$nncl, cfg$seed)
part <- commandArgs(trailingOnly = TRUE)
if (length(part) == 1) {
  runs <- runs[grepl("^grid_", names(runs)) == (part == "grid")]
}
length(runs)

##########################################
#########  cells, network inputs and homogeneous model
##########################################

## of the cells script: cumulative payments C_{i,j}(x) of the cells, inputs
## x of the feature values and the feature value x_id of every cell,
## learning cells of development period j
cells <- readRDS(file.path(paths$interim, "nncl_synthetic_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])
inputs <- readRDS(file.path(paths$interim, paste0(tag, "_inputs.rds")))
x_id <- inputs$x_id
x <- inputs$x[x_id, ]                          # network inputs of the cells
learn_rows <- inputs$learn_rows
homogeneous <- readRDS(file.path(paths$processed,
                                 "nncl_synthetic_homogeneous.rds"))

##########################################
#########  CL factor networks (Section 3, Listing 2)
##########################################

## one network per development period j; a run keeps the CL factors of the
## feature values, f_x (feature values x networks j: the factor of a cell is
## row x_id), and of every network the losses, the epochs and the training
## times; the networks of the first seed go to models/<tag>/
model_dir <- file.path(paths$models, tag)
dir.create(model_dir, showWarnings = FALSE)
s4_file <- file.path(paths$processed, paste0(tag, "_fit_s4_balance.rds"))
for (run_name in names(runs)) {
  run_file <- file.path(paths$processed,
                        paste0(tag, "_fit_", run_name, ".rds"))
  if (!claim_run(run_file)) next
  # the first run of an R session starts Python and TensorFlow here (about a
  # minute), not in the build time of its first network; nncl_model() clears
  # the session again and sets the seed
  clear_session()
  run <- runs[[run_name]]
  model_prefix <- NULL
  if (run$param$seed == cfg$seed) model_prefix <- file.path(model_dir, run_name)
  fits <- nncl_run_fit(cum,
                       x,
                       learn_rows,
                       inputs$x,
                       run,
                       units,
                       model_prefix)
  cat(sprintf("%s: %.0f s, epochs used %s, loss %.1f (homogeneous %.1f)\n",
              run_name,
              sum(sapply(fits, `[[`, "run_time")),
              paste(sapply(fits, `[[`, "epochs_used"), collapse = " "),
              sum(sapply(fits, `[[`, "loss")) / units,
              sum(homogeneous$loss) / units))
  result <- list(run = run_name,
                 age = age,
                 q = run$q,
                 param = run$param,
                 f_x = sapply(fits, `[[`, "f_new"),
                 fits = lapply(fits, function(fit) {
                   fit[setdiff(names(fit), c("f_learn", "f_new"))]
                 }),
                 info = run_info())
  # S4: the networks of S3 with the balance correction, no fit of its own;
  # saved before S3, so that S4 is there wherever S3 is
  if (run_name == "s3_cl_start") {
    save_run(nncl_balance(result, cum, x_id, learn_rows), s4_file)
  }
  save_run(result, run_file)
}
