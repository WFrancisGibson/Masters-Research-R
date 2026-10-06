## scratch driver: the fit script up to its fit loop, on the runs not fitted
## yet whose position modulo n is in 'res'; the runs of the optimisers in
## 'first' come first, then the others, each in the order of the seeds;
## arguments: n, the residues, a label (P or E cores)
args <- commandArgs(trailingOnly = TRUE)
n <- as.integer(args[1])
res <- as.integer(args[2:(length(args) - 1)])
first <- c("sgd", "sgd_momentum", "rmsprop", "adam", "nadam")
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
  sprintf("first <- c(%s)", paste0("'", first, "'", collapse = ", ")),
  "runs <- runs[order(!sapply(runs, function(run) run$param$optimizer %in%",
  "                             first),",
  "                   sapply(runs, function(run) run$param$seed))]",
  sprintf("runs <- runs[seq_along(runs) %%%% %d %%in%% c(%s)]",
          n, paste(res, collapse = ", ")),
  "print(length(runs))",
  "print(head(names(runs), 3))"
)
keep <- setdiff(seq_len(cut - 1), drop)
l2 <- c(l[keep[keep < loop]], sub, l[keep[keep >= loop]])
eval(parse(text = l2), envir = globalenv())
