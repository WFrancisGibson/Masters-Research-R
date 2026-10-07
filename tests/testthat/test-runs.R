##########################################
#########  checks of the runs shared by several R sessions (R/runs.R)
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
source(here::here("R", "runs.R"))

## a worker session of the final run has the environment variables RUN_SLOT
## and RUN_MAX and counts the runs it took in the option runs_taken; every
## test sets them for itself (NA: not set)
lock <- function(run_file) paste0(run_file, ".lock")

test_that("a session without RUN_SLOT takes every run that is not saved", {
  withr::local_envvar(RUN_SLOT = NA, RUN_MAX = NA)
  withr::local_options(runs_taken = 0)
  run_file <- tempfile("run", fileext = ".rds")
  expect_true(claim_run(run_file))
  expect_true(claim_run(run_file))                 # no lock, no count
  expect_false(dir.exists(lock(run_file)))
  expect_equal(getOption("runs_taken"), 0)
  save_run(list(a = 1), run_file)
  expect_false(claim_run(run_file))                # saved
})

test_that("a worker claims a run once", {
  withr::local_envvar(RUN_SLOT = "1", RUN_MAX = NA)
  withr::local_options(runs_taken = 0)
  run_file <- tempfile("run", fileext = ".rds")
  expect_true(claim_run(run_file))
  expect_true(dir.exists(lock(run_file)))
  expect_true(file.exists(file.path(lock(run_file), "slot_1")))  # whose lock
  expect_equal(getOption("runs_taken"), 1)
  # the lock is there: to this and to any other worker the run is taken
  expect_false(claim_run(run_file))
  withr::local_envvar(RUN_SLOT = "2")
  withr::local_options(runs_taken = 0)
  expect_false(claim_run(run_file))
  expect_equal(getOption("runs_taken"), 0)
})

test_that("a worker takes no more than RUN_MAX runs", {
  withr::local_envvar(RUN_SLOT = "1", RUN_MAX = "2")
  withr::local_options(runs_taken = 0)
  run_files <- tempfile(paste0("run", 1:3), fileext = ".rds")
  expect_true(claim_run(run_files[1]))
  expect_true(claim_run(run_files[2]))
  expect_false(claim_run(run_files[3]))
  expect_false(dir.exists(lock(run_files[3])))     # left to the next session
  expect_equal(getOption("runs_taken"), 2)
})

test_that("a worker skips a saved run", {
  withr::local_envvar(RUN_SLOT = "1", RUN_MAX = NA)
  withr::local_options(runs_taken = 0)
  run_file <- tempfile("run", fileext = ".rds")
  saveRDS(list(a = 1), run_file)
  expect_false(claim_run(run_file))
  expect_false(dir.exists(lock(run_file)))
  expect_equal(getOption("runs_taken"), 0)
})

test_that("a saved run leaves neither a temporary file nor a lock", {
  withr::local_envvar(RUN_SLOT = "1", RUN_MAX = NA)
  withr::local_options(runs_taken = 0)
  run_file <- tempfile("run", fileext = ".rds")
  expect_true(claim_run(run_file))
  save_run(list(a = 1, b = "x"), run_file)
  expect_equal(readRDS(run_file), list(a = 1, b = "x"))
  expect_false(file.exists(paste0(run_file, ".tmp")))
  expect_false(dir.exists(lock(run_file)))
  expect_false(claim_run(run_file))                # saved: not fitted again
})

test_that("run_info tells where and how a run was fitted", {
  withr::local_envvar(RUN_SLOT = "3", RUN_WORKERS = "10",
                      TF_NUM_INTRAOP_THREADS = "1")
  info <- run_info()
  expect_named(info, c("host", "cores", "workers", "threads", "slot", "time"))
  expect_equal(info[c("workers", "threads", "slot")],
               list(workers = 10, threads = "1", slot = "3"))
})
