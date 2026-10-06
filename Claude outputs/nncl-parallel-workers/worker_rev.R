## scratch driver: the fit script up to its fit loop, on every n-th run that
## is not fitted yet, in the order of the seeds
args <- as.integer(commandArgs(trailingOnly = TRUE))
f <- file.path("analysis/04_nn-chain-ladder/trackA_wuthrich2018",
               "NN chain ladder SynthETIC fit.R")
l <- readLines(f)
cut <- which(startsWith(l, "## S4:"))
loop <- which(startsWith(l, "for (run_name in names(runs)) {"))
drop <- c(which(startsWith(l, "saveRDS(cells")),
          which(startsWith(l, "saveRDS(homogeneous")) + 0:1)
stopifnot(length(cut) == 1, length(loop) == 1, length(drop) == 3)
sub <- c(
  "todo <- !file.exists(file.path(paths$processed,",
  "  paste0(tag, '_fit_', names(runs), '.rds')))",
  "runs <- runs[todo]",
  "runs <- rev(runs[order(sapply(runs, function(run) run$param$seed))])",
  sprintf("runs <- runs[seq_along(runs) %%%% %d == %d]", args[2], args[1] - 1),
  "print(length(runs))"
)
keep <- setdiff(seq_len(cut - 1), drop)
l2 <- c(l[keep[keep < loop]], sub, l[keep[keep >= loop]])
eval(parse(text = l2), envir = globalenv())
