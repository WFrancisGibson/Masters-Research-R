## scratch driver for a machine without the laptop's raw data: the fit script
## "NN chain ladder SynthETIC fit.R" on the cells of
## data/interim/nncl_synthetic_cells.rds (the laptop's portfolio, true
## reserves 9,626.8 million) in place of the claims of data/raw.
## Rscript worker_cells.R fit [m]: the runs not fitted yet of the seeds in
## $NNCL_SEEDS (blank separated, default: all), in the order of the seeds;
## any number of these share the runs through lock directories
## (<run file>.lock): a free worker takes the next run no other worker has
## taken; it quits after m runs (default: no limit), as the memory of an R
## session that fits Keras networks grows with every run; exit status 3: no
## run was left to take.
## Rscript worker_cells.R s4: the S4 run from the saved S3 run
args <- commandArgs(trailingOnly = TRUE)
mode <- args[1]
max_runs <- as.numeric(args[2])
if (is.na(max_runs)) max_runs <- Inf
seeds_share <- scan(text = Sys.getenv("NNCL_SEEDS"), quiet = TRUE)
f <- file.path("analysis/04_nn-chain-ladder/trackA_wuthrich2018",
               "NN chain ladder SynthETIC fit.R")
l <- readLines(f)
raw_from <- which(startsWith(l, "## claims and payments of the annual"))
raw_to <- which(l == "rm(claims, trans, paid)")
loop <- which(startsWith(l, "for (run_name in names(runs)) {"))
skip <- which(l == "  if (file.exists(run_file)) next")
cut <- which(startsWith(l, "## S4:"))
zero <- which(startsWith(l, "#########  zero claims features"))
save_hom <- which(startsWith(l, "saveRDS(homogeneous")) + 0:1
stopifnot(length(raw_from) == 1, length(raw_to) == 1, length(loop) == 1,
          length(skip) == 1, length(cut) == 1, length(zero) == 1,
          length(save_hom) == 2, raw_from < raw_to, raw_to < save_hom[1],
          save_hom[2] < loop, loop < skip, skip < cut, cut < zero)
## the cells from the file in place of the block that builds them from the
## claims and transactions; the check: this is the laptop's portfolio
cells_lines <- c(
  "cells <- readRDS(file.path(paths$interim, 'nncl_synthetic_cells.rds'))",
  "cum <- as.matrix(cells[, paste0('cum_', 0:(n_ay - 1)), with = FALSE])",
  paste("stopifnot(round(sum((cum[, n_ay] - cells$c_diag)[cells$i > 1]) /",
        "units, 1) == 9626.8, sum(cells$i > 1 & cells$c_diag > 0) == 3167)")
)
pre <- c(l[seq_len(raw_from - 1)], cells_lines,
         l[setdiff((raw_to + 1):(loop - 1), save_hom)])
if (mode == "s4") {
  eval(parse(text = c(pre, l[cut:(zero - 2)])), envir = globalenv())
  quit(status = 0)
}
sub <- c(
  "todo <- !file.exists(file.path(paths$processed,",
  "  paste0(tag, '_fit_', names(runs), '.rds')))",
  "runs <- runs[todo]",
  "run_seed <- vapply(runs, function(run) run$param$seed, numeric(1))",
  "if (length(seeds_share) > 0) runs <- runs[run_seed %in% seeds_share]",
  "run_seed <- vapply(runs, function(run) run$param$seed, numeric(1))",
  "runs <- runs[order(run_seed)]",
  "print(length(runs))",
  "n_taken <- 0"
)
lock <- c("  if (n_taken >= max_runs) break",
          paste("  if (!dir.create(paste0(run_file, '.lock'),",
                "showWarnings = FALSE)) next"),
          "  n_taken <- n_taken + 1")
l2 <- c(pre, sub, l[loop:skip], lock, l[(skip + 1):(cut - 1)])
eval(parse(text = l2), envir = globalenv())
quit(status = if (n_taken == 0) 3 else 0)
