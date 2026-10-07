##########################################
#########  Runs shared by several R sessions
#########  the final run: analysis/06_final-run
##########################################

## a fit script saves every run (the networks of one setting and seed, a
## chunk of bootstrap refits) in its own file and leaves out the saved ones,
## so a stopped script resumes. In the final run several R sessions (workers,
## environment variable RUN_SLOT) run the same script at once: a worker takes
## a run by creating the directory <run_file>.lock, which only one session
## can, and leaves the runs saved or taken by others. After RUN_MAX runs it
## takes no more, so the script ends and the launcher starts a fresh session
## (the memory of an R session that fits Keras networks grows by about
## 0.1 GB a run). TRUE: fit this run now
claim_run <- function(run_file) {
  if (file.exists(run_file)) return(FALSE)
  if (Sys.getenv("RUN_SLOT") == "") return(TRUE)
  taken <- getOption("runs_taken", 0)
  if (taken >= as.numeric(Sys.getenv("RUN_MAX", "Inf"))) return(FALSE)
  if (!dir.create(paste0(run_file, ".lock"), showWarnings = FALSE)) {
    return(FALSE)
  }
  options(runs_taken = taken + 1)
  TRUE
}

## saves a run: written to a temporary file and renamed, so a session stopped
## while writing leaves no file that looks like a finished run; then the lock
## of claim_run() is removed
save_run <- function(x, run_file) {
  tmp <- paste0(run_file, ".tmp")
  saveRDS(x, tmp, compress = "xz")
  file.rename(tmp, run_file)
  unlink(paste0(run_file, ".lock"), recursive = TRUE)
}

## where a run was fitted, kept with its training times: computer, its cores,
## the R sessions fitting at the same time and the threads of each
run_info <- function() {
  list(host = Sys.info()[["nodename"]],
       cores = parallel::detectCores(),
       workers = as.numeric(Sys.getenv("RUN_WORKERS", "1")),
       threads = Sys.getenv("TF_NUM_INTRAOP_THREADS", "all"),
       slot = Sys.getenv("RUN_SLOT"),
       time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
}
