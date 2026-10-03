## scratch driver: the fit script up to its fit loop, on the runs not fitted
## yet, in the order of the seeds; any number of these share the runs through
## lock directories (<run file>.lock): a free worker takes the next run no
## other worker has taken. Start them with run_queue.sh (it clears the locks
## of a stopped run first); argument: the number of runs after which the
## worker quits (default: no limit), as the memory of an R session that
## fits Keras networks grows with every run (about 0.1 GB a run); exit
## status 3: no run was left to take
max_runs <- as.numeric(commandArgs(trailingOnly = TRUE)[1])
if (is.na(max_runs)) max_runs <- Inf
f <- file.path("analysis/04_nn-chain-ladder/trackA_wuthrich2018",
               "NN chain ladder SynthETIC fit.R")
l <- readLines(f)
cut <- which(startsWith(l, "## S4:"))
loop <- which(startsWith(l, "for (run_name in names(runs)) {"))
skip <- which(l == "  if (file.exists(run_file)) next")
drop <- c(which(startsWith(l, "saveRDS(cells")),
          which(startsWith(l, "saveRDS(homogeneous")) + 0:1)
stopifnot(length(cut) == 1, length(loop) == 1, length(skip) == 1,
          length(drop) == 3, loop < skip, skip < cut)
sub <- c(
  "todo <- !file.exists(file.path(paths$processed,",
  "  paste0(tag, '_fit_', names(runs), '.rds')))",
  "runs <- runs[todo]",
  "runs <- runs[order(sapply(runs, function(run) run$param$seed))]",
  "print(length(runs))",
  "n_taken <- 0"
)
lock <- c("  if (n_taken >= max_runs) break",
          paste("  if (!dir.create(paste0(run_file, '.lock'),",
                "showWarnings = FALSE)) next"),
          "  n_taken <- n_taken + 1")
keep <- setdiff(seq_len(cut - 1), drop)
l2 <- c(l[keep[keep < loop]], sub,
        l[keep[keep >= loop & keep <= skip]], lock,
        l[keep[keep > skip]])
eval(parse(text = l2), envir = globalenv())
quit(status = if (n_taken == 0) 3 else 0)
