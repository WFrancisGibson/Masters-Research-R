##########################################
#########  final run: stand-in for the script of a task (no Keras, no
#########  model, no data): a rehearsal of the launcher on the real task
#########  table (analysis/06_final-run/launch.ps1)
##########################################

## run by the launcher in place of the script of a task, in a copy of the
## task table whose rows have this file as script and as arguments the file
## name of their real script and its arguments:
##   Rscript "tests/testthat/final_run_stand_in.R" "bCCNN grid fit.R"
## It reads the profile, data set and variant of its task from the
## environment the launcher gives it, as the real script would, stops if a
## file the real script reads is not there (final_run_files.R), waits
## STAND_IN_SLEEP seconds per run (default 0.1) and writes what the real
## script would write: a queue its run files, shared with the other
## sessions through claim_run() and save_run() (R/runs.R), another task its
## files and a marker in <RUN_ROOT>/stand-in. With STAND_IN_SCALE = k a grid
## of the final table (bCCNN grid, the two grids of the NN chain ladder) is
## its first n / k runs, for a table whose n_runs of the grids were divided
## by k (final_run_stand_in_tasks.R writes it); the quick table is run in
## full. A rehearsal has a RUN_ROOT of its own and RAW_DIR inside it: the
## stand-in stops rather than write among real claims
args <- commandArgs(trailingOnly = TRUE)
source(here::here("R", "runs.R"))
source(here::here("R", "nn_models.R"))
source(here::here("R", "nn_chain_ladder.R"))
source(here::here("tests", "testthat", "final_run_files.R"))

cfg <- config::get(file = here::here("config.yml"))
run_root <- cfg$run_root
raw <- cfg$paths$raw
stopifnot("RAW_DIR of a rehearsal is a folder inside its RUN_ROOT" =
            run_root != "." && startsWith(raw, paste0(run_root, "/")))
wait <- as.numeric(Sys.getenv("STAND_IN_SLEEP", "0.1"))
quick <- startsWith(Sys.getenv("R_CONFIG_ACTIVE"), "quick")
scale <- if (quick) 1 else as.numeric(Sys.getenv("STAND_IN_SCALE", "1"))

## the files of the real script; those it reads must be there
files <- final_run_files(args[1], args[-1], cfg, run_root, raw, scale)
reads <- as.character(files$reads)
missing <- reads[!file.exists(reads)]
missing
stopifnot("files the script of the task reads are missing" =
            length(missing) == 0)
for (f in c(files$writes, files$runs)) {
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
}

## a queue: its runs, each with the seconds it took where the real run keeps
## them ("final run status.R"): per refit of a bootstrap chunk, per network
## of the NN chain ladder, else of the run
for (run_file in files$runs) {
  if (!claim_run(run_file)) next
  t0 <- Sys.time()
  Sys.sleep(wait)
  seconds <- as.numeric(Sys.time() - t0, units = "secs")
  run <- list(run = basename(run_file), stand_in = args, info = run_info())
  if (args[1] == "bCCNN bootstrap fit.R") {
    run$time <- rep(seconds / 2, 2)
  } else if (args[1] == "NN chain ladder SynthETIC fit.R") {
    run$fits <- list(list(time_build = 0,
                          run_time = seconds,
                          time_predict = 0))
  } else {
    run$run_time <- seconds
  }
  if (run_file %in% names(files$with)) save_run(run, files$with[[run_file]])
  save_run(run, run_file)
}

## another task: the files of the real script and a marker that tells the
## environment of the session
if (length(files$runs) == 0) {
  Sys.sleep(wait)
  for (f in files$writes) {
    if (endsWith(f, ".rds")) {
      save_run(list(stand_in = args, info = run_info()), f)
    } else {
      writeLines("stand-in", f)
    }
  }
  marker <- paste(c(args, cfg$dataset, Sys.getenv("R_CONFIG_ACTIVE"),
                    cfg$bccnn$training$validation,
                    cfg$bccnn$training$final_fit),
                  collapse = " ")
  dir.create(file.path(run_root, "stand-in"), showWarnings = FALSE)
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             file.path(run_root, "stand-in", paste0(marker, ".txt")))
}
cat("stand-in done:", args, "\n")
