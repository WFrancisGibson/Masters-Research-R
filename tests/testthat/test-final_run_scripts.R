##########################################
#########  checks of the status and the timings script of the final run
#########  (analysis/06_final-run) on the run files the fit scripts save,
#########  under the quick profile on fabricated data; no Keras: a fit
#########  script runs as a copy with the stand-ins of keras_stand_ins.R or
#########  nncl_stand_ins.R in place of library(keras3)
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)

run_root <- gsub("\\\\", "/", tempfile("run_root"))
interim <- file.path(run_root, "data", "interim", "baseline")
processed <- file.path(run_root, "data", "processed", "quick", "baseline")
state <- file.path(run_root, "final-run", "quick")
bccnn_dir <- "analysis/03_bCCNN"
nncl_dir <- "analysis/04_nn-chain-ladder/trackA_wuthrich2018"
final_dir <- "analysis/06_final-run"
nncl_fit <- file.path(nncl_dir, "NN chain ladder SynthETIC fit.R")

## a script in an R session of its own with the environment of a task of
## the final run (data set baseline); stand_ins: the file that takes the
## place of library(keras3) in a copy of a fit script; workers: RUN_WORKERS
## (NA: not set, a script run by hand); root: RUN_ROOT; its exit status
run_script <- function(script,
                       args = NULL,
                       stand_ins = NULL,
                       profile = "quick",
                       validation = NA,
                       final_fit = NA,
                       slot = NA,
                       workers = "4",
                       root = run_root) {
  file <- here::here(script)
  if (!is.null(stand_ins)) {
    lines <- readLines(file)
    # never Keras itself: the one line that attaches it is replaced
    stopifnot(sum(grepl("keras3", lines)) == 1,
              sum(lines == "library(keras3)") == 1)
    lines[lines == "library(keras3)"] <-
      sprintf("source(\"%s\")", here::here("tests", "testthat", stand_ins))
    file <- file.path(root, basename(script))
    writeLines(lines, file)
  }
  withr::local_envvar(RUN_ROOT = root,
                      RAW_DIR = file.path(root, "raw"),
                      R_CONFIG_ACTIVE = profile,
                      DATASET = "baseline",
                      UNIT = NA,
                      VALIDATION = validation,
                      FINAL_FIT = final_fit,
                      RUN_SLOT = slot,
                      RUN_MAX = NA,
                      RUN_WORKERS = workers)
  system2(file.path(R.home("bin"), "Rscript"),
          c(shQuote(file), args),
          stdout = file.path(root, "log.txt"),
          stderr = file.path(root, "log.txt"))
}

## fabricated triangles of 20 x 20 as "claims triangles.R" saves them (the
## bCCNN scripts): a cross-classified pattern with Poisson noise, the
## claims split halves every cell
set.seed(1)
n <- 20
beta <- exp(-0.45 * (0:(n - 1)))
mu <- outer(4e8 * (1 + 0.03 * (1:n)), beta / sum(beta)) *
  exp(0.15 * sin((row(diag(n)) + col(diag(n))) / 3))
full <- matrix(1e4 * rpois(n * n, mu / 1e4), n, n,
               dimnames = list(origin = 1:n, dev = 1:n))
upper <- ifelse(row(full) + col(full) <= n + 1, full, NA)
train <- round(upper * runif(n * n, 0.48, 0.52), -4)
dir.create(interim, recursive = TRUE)
saveRDS(list(full = full,
             upper = upper,
             test = ifelse(row(full) + col(full) > n + 1, full, NA),
             train = train,
             vali = upper - train,
             tail = rep(0, n)),
        file.path(interim, "triangles.rds"))

## fabricated claims as the SynthETIC simulation saves them (the NN chain
## ladder scripts): 60 claims a year with the five covariates, paid over 22
## years in amounts that fall by 40% a year
claims <- data.table(claim_no = 1:(60 * n),
                     occurrence_period = rep(1:n, each = 60),
                     occurrence_time = rep(1:n, each = 60) - 0.5,
                     notidel = 0.1,
                     legal = sample(c("N", "Y"), 60 * n, replace = TRUE),
                     severity = sample(1:2, 60 * n, replace = TRUE),
                     age = sample(c("0-15", "15-30", "30-50", "50-65",
                                    "over 65"), 60 * n, replace = TRUE),
                     vehicle = sample(c("Bus", "Car"), 60 * n, replace = TRUE),
                     business = sample(c("N", "Y"), 60 * n, replace = TRUE))
setnames(claims,
         c("legal", "severity", "age", "vehicle", "business"),
         c("Legal Representation", "Injury Severity", "Age of Claimant",
           "Vehicle type", "Business use"))
trans <- claims[rep(claim_no, each = 22), .(claim_no, occurrence_period)]
trans$payment_period <- trans$occurrence_period + 0:21
trans$payment_inflated <- 1e5 * claims[["Injury Severity"]][trans$claim_no] *
  0.6^(0:21) * runif(nrow(trans), 0.5, 1.5)
raw_dir <- file.path(run_root, "raw", "claim-simulation-annual")
dir.create(raw_dir, recursive = TRUE)
fwrite(claims, file.path(raw_dir, "claims.csv"))
fwrite(trans, file.path(raw_dir, "transactions.csv"))

## the fits of the data set, each script as the task table runs it: the
## bCCNN under its three variants, the bootstrap of one of them, the masking
## study, the grid and the search; the NN chain ladder under the dummy
## coding (main runs and both grids, one search) and the numeric coding
## (main runs)
keras <- "keras_stand_ins.R"
fits <- c(
  run_script(file.path(bccnn_dir, "bCCNN fit.R"), stand_ins = keras, slot = 1),
  run_script(file.path(bccnn_dir, "bCCNN fit.R"), stand_ins = keras,
             final_fit = "partition", slot = 1),
  run_script(file.path(bccnn_dir, "bCCNN fit.R"), stand_ins = keras,
             validation = "claims_split", final_fit = "refit", slot = 1),
  run_script(file.path(bccnn_dir, "bCCNN bootstrap fit.R"), stand_ins = keras,
             validation = "claims_split", final_fit = "refit", slot = 1),
  run_script(file.path(bccnn_dir, "bCCNN masking fit.R"), stand_ins = keras,
             slot = 1),
  run_script(file.path(bccnn_dir, "bCCNN grid fit.R"), stand_ins = keras,
             slot = 1),
  run_script(file.path(bccnn_dir, "bCCNN hyperparameter search.R"),
             stand_ins = keras, slot = 1),
  run_script(file.path(nncl_dir, "NN chain ladder SynthETIC cells.R")),
  run_script(file.path(nncl_dir, "NN chain ladder SynthETIC cells.R"),
             profile = "quick_age_numeric"),
  run_script(nncl_fit, c("main", "grid", "cl_grid"), "nncl_stand_ins.R",
             slot = 1),
  run_script(nncl_fit, "main", "nncl_stand_ins.R",
             profile = "quick_age_numeric", slot = 1),
  run_script(file.path(nncl_dir, paste("NN chain ladder SynthETIC",
                                       "hyperparameter search.R")),
             "cl_start", "nncl_stand_ins.R", slot = 1)
)

## the task table of the smoke test; then the run at a moment of its own: a
## grid run being saved (its temporary file and lock, its run file not yet
## there), a task of one R session done and another given up
run_script(file.path(final_dir, "final run tasks.R"))
tasks <- fread(file.path(state, "tasks.csv"), data.table = FALSE)
grid_run <- file.path(processed, paste0("bccnn_grid_fit_grid_20_tanh_d0.1_",
                                        "rmsprop_b64_s2029.rds"))
file.rename(grid_run, paste0(grid_run, ".tmp"))
dir.create(paste0(grid_run, ".lock"))
dir.create(file.path(state, "done"))
dir.create(file.path(state, "failed"))
writeLines("2026-10-08 12:00:00, 75 s",
           file.path(state, "done", "baseline.triangles.done"))
writeLines("task baseline.mack failed 3 times in a row: exit code 1",
           file.path(state, "failed", "baseline.mack.failed"))
## run_info.txt of the launcher (in final-run, also for the smoke test): two
## launches, the last one with 14 slots
writeLines(c("launch: 2026-10-08 10:00:00", "slots: 12", "",
             "launch: 2026-10-08 11:00:00", "slots: 14", ""),
           file.path(dirname(state), "run_info.txt"))

test_that("the fit scripts ran with their stand-ins", {
  expect_equal(fits, rep(0, length(fits)))
})

test_that("the timings script reads the times of every kind of run", {
  expect_equal(run_script(file.path(final_dir, "final run timings.R"),
                          slot = 1), 0)
  tab_dir <- file.path(run_root, "output", "quick", "tables", "baseline",
                       "06_final-run")
  runs <- fread(file.path(tab_dir, "timings_runs.csv"))
  epochs <- fread(file.path(tab_dir, "timings_epochs.csv.gz"))
  blocks <- fread(file.path(tab_dir, "timings_epoch_blocks.csv.gz"))
  # a row per fit: the networks of every task (quick profile: 8 bootstrap
  # refits, 2 sets and 2 final networks of 6 fits in the bCCNN search, 19
  # networks per run of the NN chain ladder, 7 of the 8 grid runs)
  fits <- runs[, .(runs = uniqueN(run), fits = .N, networks = sum(networks)),
               keyby = task]
  expect_equal(fits$task,
               c("bccnn.bootstrap.claims_split_refit",
                 "bccnn.fit.claims_split_refit",
                 "bccnn.fit.rolling_origin_partition",
                 "bccnn.fit.rolling_origin_refit",
                 "bccnn.grid", "bccnn.masking", "bccnn.search",
                 "nncl.cl_grid", "nncl.grid", "nncl.main",
                 "nncl.search.cl_start", "nncl_numeric.main"))
  expect_equal(fits$runs, c(2, 1, 1, 1, 7, 2, 4, 8, 8, 6, 4, 6))
  expect_equal(fits$fits[c(1:4, 7:12)],
               c(8, 2, 3, 6, 2 * 4 + 2 * 6, 152, 152, 114, 2 * 19 + 4, 114))
  expect_equal(fits$networks[11], 2 * 19 + 2 * (14 + 17))
  expect_true(all(fits$fits[5] >= 7 * 3 & fits$fits[5] <= 7 * 15))
  expect_true(all(fits$fits[6] %in% 4:6))
  # the tasks are those of the task table
  expect_true(all(paste0("baseline.", fits$task) %in% tasks$id))
  # seconds of every fit and of every run, epochs, and where it was fitted
  expect_true(all(is.finite(runs$seconds_fit) & runs$seconds_fit >= 0))
  expect_true(all(is.finite(runs$run_seconds) & runs$run_seconds >= 0))
  expect_true(all(runs[model == "nncl" & networks == 1,
                       seconds_total >= seconds_fit + seconds_build]))
  expect_true(all(runs[task == "bccnn.bootstrap.claims_split_refit",
                       seconds_total >= seconds_fit]))
  expect_true(all(runs[networks == 1, epochs >= 0 & epochs == round(epochs)]))
  expect_true(all(runs[epochs > 0,
                       abs(seconds_per_epoch - seconds_fit / epochs) < 1e-6]))
  expect_true(all(runs$host != "" & runs$workers == 4 & !is.na(runs$time)))
  expect_equal(runs[task == "nncl.main" & run == "paper_q5", epochs],
               rep(5, 19))
  expect_equal(runs[task == "bccnn.fit.rolling_origin_refit" &
                      grepl("early_stop", fit), epochs],
               rep(100, 3))
  # every epoch of the main fits, the masking study, the search and the
  # first seed of the grids, each of a fit of timings_runs.csv
  key <- function(x) paste(x$task, x$run, x$fit)
  expect_true(all(key(epochs) %in% key(runs)))
  expect_setequal(epochs$task, setdiff(fits$task,
                                       "bccnn.bootstrap.claims_split_refit"))
  first_seed <- unique(epochs[task %in% c("bccnn.grid", "nncl.grid",
                                          "nncl.cl_grid",
                                          "nncl.search.cl_start"), run])
  expect_true(all(grepl("_s2026$", first_seed)))
  expect_length(first_seed, 2 + 4 + 4 + 1)
  expect_equal(nrow(epochs[task == "nncl.main" & run == "paper_q5"]), 19 * 5)
  expect_equal(epochs[task == "bccnn.fit.claims_split_refit" &
                        fit == "halves early_stop", epoch],
               0:100)
  expect_true(all(epochs[!is.na(seconds), seconds >= 0]))
  expect_true(all(is.na(epochs[model == "nncl", seconds_predict])))
  # the mean milliseconds per block of 100 epochs of every run of the grid
  expect_setequal(blocks$run, runs[task == "bccnn.grid", run])
  expect_true(all(key(blocks) %in% key(runs)))
  expect_true(all(blocks$block %in% 0:3))
})


test_that("the status script counts runs, seconds and the work left", {
  # as the task status.benchmark, which then counts as done; without
  # RUN_WORKERS: the slots of the last launch in run_info.txt
  expect_equal(run_script(file.path(final_dir, "final run status.R"),
                          "status.benchmark", workers = NA), 0)
  status <- fread(file.path(state, "status.csv"), data.table = FALSE)
  rownames(status) <- status$id
  expect_equal(status$id, tasks$id)
  # queues: their run files; a run being saved is not counted
  done <- c("baseline.nncl.main" = 6,
            "baseline.nncl_numeric.main" = 6,
            "baseline.nncl.grid" = 8,
            "baseline.nncl.grid.benchmark" = 1,
            "baseline.nncl.cl_grid" = 8,
            "baseline.bccnn.bootstrap.claims_split_refit" = 2,
            "baseline.bccnn.masking" = 2,
            "baseline.bccnn.grid" = 7,
            "baseline.bccnn.grid.benchmark" = 1,
            "si_calendar.bccnn.grid" = 0)
  expect_equal(status[names(done), "done"], unname(done))
  expect_equal(unlist(status["baseline.bccnn.grid", c("runs", "to_do")]),
               c(runs = 8, to_do = 1))
  expect_equal(status["baseline.bccnn.grid", "state"], "waiting")
  expect_equal(status["baseline.nncl.grid", "state"], "done")
  expect_equal(status["status.benchmark", "state"], "done")
  expect_equal(status["status.final", "state"], "waiting")
  # the seconds of a run: of the run (grid, masking), of its refits
  # (bootstrap), of its networks (NN chain ladder)
  run_files <- function(pattern) {
    lapply(list.files(processed, pattern, full.names = TRUE), readRDS)
  }
  seconds <- c(
    "baseline.bccnn.grid" =
      mean(sapply(run_files("^bccnn_grid_fit_.*[.]rds$"), `[[`, "run_time")),
    "baseline.bccnn.bootstrap.claims_split_refit" =
      mean(sapply(run_files("^bccnn_bootstrap_.*[.]rds$"),
                  function(x) sum(x$time))),
    "baseline.nncl.cl_grid" =
      mean(sapply(run_files("^nncl_synthetic_fit_clgrid_.*[.]rds$"),
                  function(x) {
                    sum(sapply(x$fits, function(fit) {
                      fit$time_build + fit$run_time + fit$time_predict
                    }))
                  }))
  )
  expect_equal(status[names(seconds), "seconds"], unname(seconds),
               tolerance = 1e-6)
  expect_true(all(seconds >= 0))
  expect_equal(status[names(seconds), "seconds_from"], rep("own", 3))
  expect_equal(status[names(seconds), "seconds_runs"], c(7, 2, 8))
  # a queue without a run yet: the seconds of the same task of another data
  # set; a run of it is to do once, with its benchmark
  expect_equal(status[c("si_calendar.bccnn.grid.benchmark",
                        "si_calendar.bccnn.grid"), "to_do"],
               c(1, 7))
  expect_equal(status["si_calendar.bccnn.grid", "seconds_from"], "alike")
  expect_equal(status["si_calendar.bccnn.grid", "seconds_runs"], 7)
  expect_equal(status["si_calendar.bccnn.grid", "seconds"],
               status["baseline.bccnn.grid", "seconds"])
  expect_equal(status["si_calendar.bccnn.grid", "slot_hours"],
               7 * status["baseline.bccnn.grid", "seconds"] / 3600,
               tolerance = 1e-6)
  # tasks of one R session: the seconds of the done marker, also for the
  # same task of the other data sets; a task given up
  expect_equal(unlist(status["baseline.triangles", c("done", "seconds")]),
               c(done = 1, seconds = 75))
  expect_equal(status["baseline.triangles", "state"], "done")
  expect_equal(unlist(status["long_reporting.triangles",
                             c("state", "seconds_from")]),
               c(state = "waiting", seconds_from = "alike"))
  expect_equal(status["long_reporting.triangles", "seconds"], 75)
  expect_equal(status["baseline.mack", "state"], "FAILED")
  expect_true(is.na(status["baseline.mack", "seconds"]))
  # the stages and the whole run: the runs of the queues once (those of the
  # benchmark are runs of their queues), the slots of the last launch
  stages <- fread(file.path(state, "status_stages.csv"), data.table = FALSE)
  expect_equal(stages$stage, c(sort(unique(tasks$stage)), "all"))
  all_stages <- stages[stages$stage == "all", ]
  real <- tasks$kind == "queue" & tasks$stage != 2
  expect_equal(all_stages$tasks, nrow(tasks))
  expect_equal(all_stages$runs, sum(tasks$n_runs[real]))
  expect_equal(all_stages$runs_done, 6 + 6 + 8 + 8 + 2 + 2 + 7)
  expect_equal(stages$runs[stages$stage == "2"], sum(tasks$stage == 2) - 1)
  expect_true(all(stages$slots == 14))
  expect_match(all_stages$end, "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$")
  expect_equal(all_stages$slot_hours,
               sum(status$slot_hours, na.rm = TRUE),
               tolerance = 1e-6)
})

test_that("the status script times a queue by its runs or by alike tasks", {
  # a table of its own: two alike queues with their benchmarks (a has 10 of
  # 100 runs, the first one cheap, b only its benchmark run), a queue of
  # another script with one run, tasks of one R session
  root <- gsub("\\\\", "/", tempfile("status_root"))
  state <- file.path(root, "final-run")
  dir.create(file.path(state, "done"), recursive = TRUE)
  row <- function(id, stage, script, n_runs = NA, run_dir = "", args = "") {
    queue <- !is.na(n_runs)
    data.frame(id = id,
               stage = stage,
               dataset = "baseline",
               unit = "",
               profile = "",
               validation = "",
               final_fit = "",
               script = script,
               args = args,
               kind = if (queue) "queue" else "single",
               sessions = if (queue) min(n_runs, 64) else NA,
               max_runs = if (queue) min(n_runs, 8) else NA,
               n_runs = n_runs,
               run_dir = run_dir,
               pattern = if (queue) "^g_.*[.]rds$" else "",
               needs = "")
  }
  fwrite(rbind(row("keras.check", 0, "k.R"),
               row("a.q.benchmark", 2, "g.R", 1, "d/a"),
               row("b.q.benchmark", 2, "g.R", 1, "d/b"),
               row("status.x", 2, "s.R", args = "status.x"),
               row("a.q", 3, "g.R", 100, "d/a"),
               row("b.q", 3, "g.R", 100, "d/b"),
               row("c.q", 3, "h.R", 100, "d/c"),
               row("c.single", 3, "c.R"),
               row("k.single", 5, "k.R")),
         file.path(state, "tasks.csv"))
  writeLines("2026-10-08 12:00:00, 60 s",
             file.path(state, "done", "keras.check.done"))
  status_script <- file.path(final_dir, "final run status.R")
  read_status <- function(file) {
    x <- fread(file.path(state, file), data.table = FALSE)
    rownames(x) <- x[[1]]
    x
  }

  # no run file yet: no queue has a time, so no end is estimated
  expect_equal(run_script(status_script, profile = NA, root = root), 0)
  status <- read_status("status.csv")
  expect_equal(status$to_do, c(0, 1, 1, 1, 99, 99, 100, 1, 1))
  expect_true(all(is.na(status[status$kind == "queue", "seconds"])))
  stages <- read_status("status_stages.csv")
  expect_true(is.na(stages["all", "end"]) || stages["all", "end"] == "")
  expect_equal(stages["all", "no_time"], 7)

  # run files: of a, the first cheap; of b and c, the benchmark run alone.
  # A run being saved (its temporary file and lock) is no run file
  save_runs <- function(dir, seconds) {
    dir.create(file.path(root, dir), recursive = TRUE)
    for (k in seq_along(seconds)) {
      saveRDS(list(run_time = seconds[k]),
              file.path(root, dir, sprintf("g_%02d.rds", k)))
    }
  }
  save_runs("d/a", c(10, rep(110, 9)))
  save_runs("d/b", 10)
  save_runs("d/c", 50)
  saveRDS(list(run_time = 9999), file.path(root, "d/a", "g_11.rds.tmp"))
  dir.create(file.path(root, "d/a", "g_11.rds.lock"))
  expect_equal(run_script(status_script, "status.x", profile = NA,
                          root = root), 0)
  status <- read_status("status.csv")
  expect_equal(status$done, c(1, 1, 1, 1, 10, 1, 1, 0, 0))
  expect_equal(status$to_do, c(0, 0, 0, 0, 90, 99, 99, 1, 1))
  expect_equal(status["status.x", "state"], "done")
  # a has 10% of its runs: its own mean. b has 1%: the mean of the 11 run
  # files of a and b, not its cheap first run. c has no alike task: its
  # one run, a thin estimate
  expect_equal(status[c("a.q", "b.q", "c.q"), "seconds_from"],
               c("own", "alike", "alike"))
  expect_equal(status[c("a.q", "b.q", "c.q"), "seconds"],
               c(100, (10 * 100 + 10) / 11, 50))
  expect_equal(status[c("a.q", "b.q", "c.q"), "seconds_runs"], c(10, 11, 1))
  # the work left: the runs and the starts of the sessions to come (8 runs
  # a session), each the 60 s of the Keras check; RUN_WORKERS = 4 slots
  slot_hours <- c(90 * 100 + 12 * 60,
                  99 * (10 * 100 + 10) / 11 + 13 * 60,
                  99 * 50 + 13 * 60) / 3600
  expect_equal(status[c("a.q", "b.q", "c.q"), "slot_hours"], slot_hours)
  expect_equal(status[c("a.q", "b.q", "c.q"), "hours"], slot_hours / 4)
  # tasks of one R session: by an alike task (k.R, 60 s), or no time
  expect_equal(status["k.single", "slot_hours"], 60 / 3600)
  expect_true(is.na(status["c.single", "slot_hours"]))
  # stages: a run of a benchmark and its queue once; all slots busy, at
  # least the longest task (stage 5: one task of 60 s on one slot)
  stages <- read_status("status_stages.csv")
  expect_equal(stages$stage, c("0", "2", "3", "5", "all"))
  expect_equal(stages$runs, c(0, 2, 298, 0, 300))
  expect_equal(stages$runs_done, c(0, 2, 10, 0, 12))
  expect_equal(stages$no_time, c(0, 0, 1, 0, 1))
  expect_equal(stages$hours,
               c(0, 0, sum(slot_hours) / 4, 60 / 3600,
                 (sum(slot_hours) + 60 / 3600) / 4))
  expect_true(all(stages$slots == 4))
  expect_match(stages["all", "end"], "^[0-9]{4}-[0-9]{2}-[0-9]{2} ")
})
