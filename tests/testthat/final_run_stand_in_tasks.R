##########################################
#########  final run: the task table of a rehearsal, the real table with
#########  the stand-in as the script of every task (no Keras, no model)
#########  (analysis/06_final-run/launch.ps1, parameter -TasksScript)
##########################################

## given to the launcher in place of "final run tasks.R", it writes the real
## task table of the run (the smoke test, then the final run) and replaces
## the script of every row but the status script by final_run_stand_in.R,
## with the file name of the real script before its arguments. The launcher
## then goes through the whole run as on the VM, without a fit. From the
## project root, with the environment variable RAW_DIR a folder inside the
## RUN_ROOT of the rehearsal (a scratch folder; forward slashes, spelled as
## -RunRoot), in one line:
##   powershell -ExecutionPolicy Bypass -File
##     "analysis\06_final-run\launch.ps1" -RunRoot <folder>\results
##     -TasksScript "tests/testthat/final_run_stand_in_tasks.R" -Python uv
##     -NoPush
## (-Python uv: no Python environment is asked for, and none is started;
## -NoPush: nothing is committed.)
## STAND_IN_SCALE = k divides the runs of the grids of the final table by k
## (2,880 and 1,200 small files per queue take an hour as stand-ins); the
## quick table is run in full. tasks_real.csv beside tasks.csv: the table
## as the tasks script wrote it
source(here::here("analysis", "06_final-run", "final run tasks.R"))
fwrite(tasks, file.path(state, "tasks_real.csv"))

scale <- if (quick) 1 else as.numeric(Sys.getenv("STAND_IN_SCALE", "1"))
grid <- tasks$kind == "queue" & tasks$stage != 2 &
  (basename(tasks$script) == "bCCNN grid fit.R" |
     tasks$args %in% c("grid", "cl_grid"))
tasks$n_runs[grid] <- ceiling(tasks$n_runs[grid] / scale)
tasks$sessions[grid] <- pmin(tasks$sessions[grid], tasks$n_runs[grid])

stand_in <- basename(tasks$script) != "final run status.R"
tasks$args[stand_in] <- trimws(paste0("\"",
                                      basename(tasks$script[stand_in]),
                                      "\" ",
                                      tasks$args[stand_in]))
tasks$script[stand_in] <- "tests/testthat/final_run_stand_in.R"
fwrite(tasks, file.path(state, "tasks.csv"))
