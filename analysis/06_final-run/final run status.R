##########################################
#########  final run: progress and the time left
#########  own design: analysis/06_final-run/launch.ps1, contract 1. to 3.
##########################################

## what is done, what is left and how long that takes at the least, from the
## task table of the launcher (tasks.csv), its done and failed markers, the
## run files of the queues and the seconds the fit scripts save in them. A
## command at any moment of the run, from the project root:
##   Rscript "analysis/06_final-run/final run status.R"
## with the environment variable RUN_ROOT as the launcher has it, the folder
## ../Masters-Research-R-results/results (README: the final run on the VM);
## R_CONFIG_ACTIVE=quick gives the smoke test. Also a task of the final run
## (after the benchmark stage, after the first queue of each grid and at the
## end): it is then given the id of its own task, which counts as done.
## The slots (R sessions at once) are RUN_WORKERS if set (a task has it),
## else those of the last launch in <RUN_ROOT>/final-run/run_info.txt (on
## the laptop: the slots of the VM, pushed with the results), else the
## processors of this computer.
## Printed, and written to <RUN_ROOT>/final-run[/quick]/status.csv, per task:
##   runs, done, to_do  a queue: its run files; another task: 1 run. A
##                      benchmark task and its queue share their run files;
##                      a run to do is counted once, with the first of them
##   seconds            mean seconds of a run by the clock; a task of one R
##                      session: its seconds in the done marker
##   seconds_from       own: of the run files of the task (of at most n_read
##                      of them) once it has own_share of its runs; alike:
##                      of the tasks of the same script, arguments and
##                      variant (the other data sets, the other coding of
##                      Age of Claimant), weighted by their run files
##   seconds_runs       the run files (markers) the seconds were read from
##   slot_hours         the work left, on one slot: to_do x seconds and, for
##                      a queue, the starts of its R sessions to come (to_do
##                      / max_runs of them, each the seconds of the Keras
##                      check: R, Python and TensorFlow)
##   hours              slot_hours over the sessions the task can have
## and to status_stages.csv per stage and for the whole run (stage all): the
## tasks, the runs of the queues (each counted once), slot_hours and hours =
## slot_hours / slots, at least the longest of its tasks: every slot busy to
## the end, as the queues of the later stages take the slots a stage leaves
## free; with the time of this status, the slots and the estimated end.
## The end is the earliest one. The first runs of a grid are its cheapest:
## the NN chain ladder starts with one hidden layer, SGD and the 100 epochs
## of the paper (on the laptop a third of the mean run of the random-start
## grid), the bCCNN with one hidden layer and the full batch. After the
## benchmark stage the hours of the grids rest on these runs alone and are
## too low; they firm up when the first queue of a grid has own_share of
## its runs (the NN chain ladder: a whole seed), and for the bCCNN grid,
## which goes setting by setting, only as it goes on. A task without a time
## is left out of the hours and counted. A bCCNN run file holds the start
## of Python in the first run of a session: counted twice, a minute a
## session
source(here::here("analysis", "00_setup.R"))

quick <- startsWith(Sys.getenv("R_CONFIG_ACTIVE"), "quick")
state_final <- here::here(cfg$run_root, "final-run")
state <- if (quick) file.path(state_final, "quick") else state_final
n_read <- 200                # run files read per queue, spread over the run
own_share <- 0.05            # a queue with this share of its runs: own time

## the slots of the launcher
slots <- as.numeric(Sys.getenv("RUN_WORKERS", NA))
slots_from <- "RUN_WORKERS"
info_file <- file.path(state_final, "run_info.txt")
if (is.na(slots) && file.exists(info_file)) {
  launches <- grep("^slots: [0-9]+", readLines(info_file), value = TRUE)
  slots <- as.numeric(sub("^slots: ([0-9]+).*$", "\\1",
                          launches[length(launches)]))
  slots_from <- "the last launch in run_info.txt"
}
if (length(slots) == 0 || is.na(slots)) {
  slots <- parallel::detectCores()
  slots_from <- "the processors of this computer"
}

##########################################
#########  the tasks and their run files
##########################################

stopifnot("no task table: start launch.ps1, or run final run tasks.R" =
            file.exists(file.path(state, "tasks.csv")))
tasks <- fread(file.path(state, "tasks.csv"),
               colClasses = "character",
               data.table = FALSE)
tasks[is.na(tasks)] <- ""
queue <- tasks$kind == "queue"
n_runs <- ifelse(queue, as.numeric(tasks$n_runs), 1)
sessions <- ifelse(queue, as.numeric(tasks$sessions), 1)
max_runs <- as.numeric(tasks$max_runs)         # NA: no limit, or no queue
## as a task of the run: the task of this session, done with this status
self <- tasks$id %in% commandArgs(trailingOnly = TRUE)

## the seconds of a saved run by the clock: run_time of a bCCNN grid run or
## masking seed, time of the refits of a bootstrap chunk; a run of the NN
## chain ladder keeps them per network: the build, the epochs (run_time) and
## the predictions
run_seconds <- function(x) {
  if (!is.null(x$fits)) {
    return(sum(sapply(x$fits, function(fit) {
      fit$time_build + fit$run_time + fit$time_predict
    })))
  }
  if (!is.null(x$run_time)) return(sum(x$run_time))
  sum(x$time)
}

## the seconds of the R session of a task in its done marker, which the
## launcher writes as "2026-10-08 12:00:00, 75 s"; NA: another text
marker_seconds <- function(file) {
  line <- c(readLines(file, n = 1, warn = FALSE), "")[1]
  if (!grepl(", [0-9]+ s", line)) return(NA_real_)
  as.numeric(sub("^.*, ([0-9]+) s.*$", "\\1", line))
}

## the run files of a queue as the launcher counts them (contract 3.): the
## names in run_dir that match its pattern, never a temporary file (.tmp, a
## run being saved) or a lock directory (<run file>.lock); the mean seconds
## of n_read of them, spread over the order they were saved in. A file that
## cannot be read at this moment is passed over. set: the run files of a
## task; a benchmark and its queue have the same, read once
set <- ifelse(queue, paste(tasks$run_dir, tasks$pattern), tasks$id)
files <- rep(0, nrow(tasks))
read <- rep(0, nrow(tasks))
seconds <- rep(NA_real_, nrow(tasks))
for (k in which(queue & !duplicated(set))) {
  dir <- here::here(cfg$run_root, tasks$run_dir[k])
  run_files <- grep(tasks$pattern[k], list.files(dir), value = TRUE,
                    perl = TRUE)
  run_files <- file.path(dir, run_files[!grepl("[.](tmp|partial|lock)$",
                                               run_files)])
  run_files <- run_files[order(file.mtime(run_files))]
  picked <- unique(round(seq(1, length(run_files),
                             length.out = min(n_read, length(run_files)))))
  run_time <- sapply(run_files[picked], function(f) {
    tryCatch(run_seconds(readRDS(f)), error = function(e) NA_real_)
  })
  same <- set == set[k]
  files[same] <- length(run_files)
  read[same] <- sum(!is.na(run_time))
  if (any(!is.na(run_time))) seconds[same] <- mean(run_time, na.rm = TRUE)
}

## a task of one R session: done with its marker, which holds its seconds
marker <- file.path(state, "done", paste0(tasks$id, ".done"))
for (k in which(!queue & file.exists(marker))) {
  files[k] <- 1
  seconds[k] <- marker_seconds(marker[k])
  read[k] <- as.numeric(!is.na(seconds[k]))
}
files[self] <- 1
done <- pmin(files, n_runs)

## the runs to do. Tasks with the same run files (a benchmark and its
## queue): a run is to do for the first task that wants it, in the order of
## their numbers of runs; before: the runs of the tasks before it
before <- rep(0, nrow(tasks))
for (s in unique(set[queue])) {
  k <- which(set == s)
  k <- k[order(n_runs[k])]
  before[k] <- c(0, n_runs[k[-length(k)]])
}
to_do <- pmax(0, n_runs - pmax(files, before))

## failed tasks (given up after three failures in a row: the first line of
## the marker has the reason) and the R sessions running now (sessions.csv
## of the launcher, rewritten at any moment: if it cannot be read, none)
failed_marker <- file.path(state, "failed", paste0(tasks$id, ".failed"))
failed <- file.exists(failed_marker)
running <- tryCatch(read.csv(file.path(state, "sessions.csv"),
                             colClasses = "character")$id,
                    error = function(e) NULL,
                    warning = function(w) NULL)
running <- as.numeric(table(factor(running, levels = tasks$id)))
running[self] <- 0

##########################################
#########  the time left
##########################################

## seconds of a run. alike: the tasks of the same script, arguments and
## variant (another data set or coding of Age of Claimant); their mean,
## each set of run files once and weighted by its run files
alike <- paste(tasks$script, tasks$args, tasks$validation, tasks$final_fit)
timed <- !duplicated(set) & !is.na(seconds)
pool <- function(x) ave(ifelse(timed, x, 0), alike, FUN = sum)
seconds_alike <- ifelse(pool(files) > 0,
                        pool(files * seconds) / pool(files),
                        NA)
## own: the task has enough run files of its own; the first runs of a grid
## are not its mean run
own <- !is.na(seconds) & files >= own_share * n_runs
seconds_from <- ifelse(own, "own", ifelse(is.na(seconds_alike), "", "alike"))
seconds_runs <- ifelse(own, read, pool(read))
seconds <- ifelse(own, seconds, seconds_alike)

## the R sessions a queue still starts: to_do / max_runs of them, at least
## those it starts at once; each takes the seconds of the Keras check
keras_marker <- file.path(state, "done", "keras.check.done")
start_seconds <- 0
if (file.exists(keras_marker)) start_seconds <- marker_seconds(keras_marker)
if (is.na(start_seconds)) start_seconds <- 0
starts <- ifelse(queue,
                 pmax(ceiling(to_do / max_runs),
                      pmin(sessions, slots, to_do),
                      na.rm = TRUE),
                 0)
slot_hours <- ifelse(to_do == 0,
                     0,
                     (to_do * seconds + starts * start_seconds) / 3600)
no_time <- to_do > 0 & is.na(slot_hours)       # left out of the hours

status <- data.frame(
  id = tasks$id,
  stage = as.numeric(tasks$stage),
  kind = tasks$kind,
  state = ifelse(done >= n_runs, "done",
                 ifelse(failed, "FAILED",
                        ifelse(running > 0, "running", "waiting"))),
  runs = n_runs,
  done = done,
  to_do = to_do,
  sessions = running,
  seconds = seconds,
  seconds_from = seconds_from,
  seconds_runs = seconds_runs,
  slot_hours = slot_hours,
  hours = slot_hours / pmax(1, pmin(slots, sessions, to_do))
)
## printed rounded, in one block of lines; status.csv keeps the numbers
shown <- status
shown$seconds <- round(shown$seconds, 1)
shown$slot_hours <- round(shown$slot_hours, 2)
shown$hours <- round(shown$hours, 2)
options(width = 200)
print(shown, row.names = FALSE, right = FALSE)

## per stage: tasks, the runs of the queues (a run of a benchmark and its
## queue once) and the work left; hours with all slots, at least the
## longest of its tasks with the sessions that task can have
by_stage <- aggregate(
  data.frame(tasks = 1,
             tasks_done = status$state == "done",
             failed = status$state == "FAILED",
             runs = ifelse(queue, n_runs - before, 0),
             runs_done = ifelse(queue, n_runs - before - to_do, 0),
             no_time = no_time,
             slot_hours = ifelse(no_time, 0, slot_hours)),
  list(stage = status$stage),
  sum
)
longest <- tapply(ifelse(is.na(status$hours), 0, status$hours),
                  status$stage,
                  max)
by_stage$hours <- pmax(by_stage$slot_hours / slots, as.numeric(longest))
total <- data.frame(stage = "all",
                    as.list(colSums(by_stage[2:8])),
                    hours = max(sum(by_stage$slot_hours) / slots,
                                by_stage$hours))
by_stage <- rbind(by_stage, total)
by_stage$days <- by_stage$hours / 24
cbind(by_stage[1:7], round(by_stage[8:10], 2))

## the whole run: every slot busy to the end. No end while runs of the
## queues are to do and none of them has a time; thin: a queue timed by
## fewer run files than own_share of its runs
now <- Sys.time()
has_end <- !any(queue & to_do > 0) || any(queue & to_do > 0 & !no_time)
end <- if (has_end) format(now + 3600 * total$hours, "%Y-%m-%d %H:%M") else ""
end_text <- if (has_end) end else "no estimate yet"
if (all(to_do == 0)) end_text <- "nothing is left to do"
thin <- queue & to_do > 0 & !no_time & seconds_runs < own_share * n_runs
cat(sprintf(paste0("%s: %d of %d tasks done, %d failed; %d R sessions ",
                   "running; %d slots (%s)\n",
                   "work left: %.1f slot hours, at least %.1f hours ",
                   "(%.1f days); end at the earliest: %s\n",
                   "to do without a time yet (not in the hours): %d runs ",
                   "of %d queues, %d other tasks\n",
                   "queues to do with a time from less than %g%% of their ",
                   "runs: %d%s\n"),
            format(now, "%Y-%m-%d %H:%M"),
            sum(status$state == "done"),
            nrow(status),
            sum(status$state == "FAILED"),
            sum(running),
            slots,
            slots_from,
            total$slot_hours,
            total$hours,
            total$hours / 24,
            end_text,
            sum(to_do[queue & no_time]),
            sum(queue & no_time),
            sum(!queue & no_time),
            100 * own_share,
            sum(thin),
            if (any(thin)) paste(" (the first runs of a grid are its",
                                 "cheapest: their hours are too low)") else
              ""))

## the failed tasks with the reason (their logs: <state>/logs/<id>_slot*.log)
for (k in which(status$state == "FAILED")) {
  cat(readLines(failed_marker[k], n = 1, warn = FALSE), "\n")
}

by_stage$time <- format(now, "%Y-%m-%d %H:%M:%S")
by_stage$slots <- slots
by_stage$end <- ifelse(by_stage$stage == "all", end, "")
fwrite(status, file.path(state, "status.csv"))
fwrite(by_stage, file.path(state, "status_stages.csv"))
