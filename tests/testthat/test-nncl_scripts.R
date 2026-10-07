##########################################
#########  checks of the NN chain ladder SynthETIC scripts
#########  (analysis/04_nn-chain-ladder: cells, fit and search), run as the
#########  final run runs them, under the quick profile on a fabricated
#########  portfolio; no Keras: the fit and the search script run as a copy
#########  with the stand-ins of nncl_stand_ins.R in place of library(keras3)
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)
source(here::here("R", "nn_chain_ladder.R"))

script_dir <- here::here("analysis", "04_nn-chain-ladder",
                         "trackA_wuthrich2018")
stand_ins <- here::here("tests", "testthat", "nncl_stand_ins.R")
run_root <- gsub("\\\\", "/", tempfile("run_root"))
interim <- file.path(run_root, "data", "interim", "baseline")
processed <- file.path(run_root, "data", "processed", "quick", "baseline")
fit_script <- "NN chain ladder SynthETIC fit.R"

## a script in an R session of its own with the environment of the final run
## (analysis/06_final-run: RUN_ROOT, the profile, the data set, the arguments
## of the task and, for a worker, RUN_SLOT and RUN_MAX); its exit status, 0:
## no error
run_script <- function(name,
                       args = NULL,
                       keras = FALSE,
                       slot = NA,
                       max_runs = NA) {
  script <- file.path(script_dir, name)
  if (keras) {
    lines <- readLines(script)
    # never Keras itself: the one line that attaches it is replaced
    stopifnot(sum(grepl("keras3", lines)) == 1,
              sum(lines == "library(keras3)") == 1)
    lines[lines == "library(keras3)"] <- sprintf("source(\"%s\")", stand_ins)
    script <- file.path(run_root, name)
    writeLines(lines, script)
  }
  withr::local_envvar(RUN_ROOT = run_root,
                      RAW_DIR = file.path(run_root, "raw"),
                      R_CONFIG_ACTIVE = "quick",
                      DATASET = "baseline",
                      UNIT = NA,
                      RUN_SLOT = slot,
                      RUN_MAX = max_runs)
  system2(file.path(R.home("bin"), "Rscript"),
          c(shQuote(script), args),
          stdout = file.path(run_root, "log.txt"),
          stderr = file.path(run_root, "log.txt"))
}

## the runs of the quick profile and the run files of the dummy coding by
## the anchored patterns of the tasks
cfg <- config::get(file = here::here("config.yml"), config = "quick")
runs <- nncl_runs(cfg$nncl, cfg$seed)
part <- sapply(runs, `[[`, "part")
file_name <- function(run) paste0("nncl_synthetic_fit_", run, ".rds")
pattern <- c(main = "^nncl_synthetic_fit_(paper_q[0-9]+|s[1-4]_[a-z_]+)[.]rds$",
             grid = "^nncl_synthetic_fit_grid_.*[.]rds$",
             cl_grid = "^nncl_synthetic_fit_clgrid_.*[.]rds$",
             tuned = "^nncl_synthetic_fit_tuned_[a-z_]+_s[0-9]+[.]rds$")
run_files <- function(task) list.files(processed, pattern = pattern[[task]])
saved <- function(run) readRDS(file.path(processed, file_name(run)))

## fabricated claims of 20 accident years as the SynthETIC simulation saves
## them: 60 claims a year with the five covariates, each paid over 22 years
## (the last two after development year J) in amounts that fall by 40% a year
set.seed(1)
n <- 20
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
raw_dir <- file.path(run_root, "raw", cfg$datasets$baseline$dir)
dir.create(raw_dir, recursive = TRUE)
fwrite(claims, file.path(raw_dir, "claims.csv"))
fwrite(trans, file.path(raw_dir, "transactions.csv"))

test_that("the fit script fits the parts named by its arguments", {
  expect_equal(run_script("NN chain ladder SynthETIC cells.R"), 0)
  # two parts: the main runs (S4 is saved with S3) and the random-start grid
  expect_equal(run_script(fit_script, c("main", "grid"), keras = TRUE), 0)
  expect_setequal(run_files("main"),
                  file_name(c(names(runs)[part == "main"], "s4_balance")))
  expect_setequal(run_files("grid"), file_name(names(runs)[part == "grid"]))
  expect_length(run_files("cl_grid"), 0)
  # one part, a worker session: the first RUN_MAX runs of the
  # chain-ladder-start grid
  expect_equal(run_script(fit_script, "cl_grid", TRUE, slot = 1, max_runs = 5),
               0)
  expect_setequal(run_files("cl_grid"),
                  file_name(names(runs)[part == "cl_grid"][1:5]))
  # an argument that is no part (the prefix of the run names for cl_grid): an
  # error, not a session that ends without a fit as if its task were done
  n_before <- length(list.files(processed))
  expect_equal(run_script(fit_script, "clgrid", TRUE, slot = 1), 1)
  expect_equal(run_script(fit_script, c("main", "Grid"), TRUE, slot = 1), 1)
  expect_length(list.files(processed), n_before)
  # no argument: all runs, here a main run and the rest of the
  # chain-ladder-start grid
  file.remove(file.path(processed, file_name("paper_q5")))
  expect_equal(run_script(fit_script, keras = TRUE, slot = 2), 0)
  expect_setequal(c(run_files("main"), run_files("grid"), run_files("cl_grid")),
                  file_name(c(names(runs), "s4_balance")))
  expect_setequal(run_files("cl_grid"),
                  file_name(names(runs)[part == "cl_grid"]))
  expect_length(list.files(processed, pattern = "[.](lock|tmp)$"), 0)
  # the networks of the first seed
  first <- sapply(runs, function(run) run$param$seed) == cfg$seed
  expect_length(list.files(file.path(run_root, "models", "quick", "baseline",
                                     "nncl_synthetic")),
                (n - 1) * sum(first))
})

test_that("a saved run keeps its settings and the start of its networks", {
  fits <- lapply(names(runs), saved)
  expect_true(all(sapply(fits, function(fit) {
    identical(names(fit), c("run", "age", "q", "param", "cl_start", "f_x",
                            "fits", "info"))
  })))
  expect_equal(sapply(fits, `[[`, "run"), names(runs))
  expect_identical(lapply(fits, `[`, c("q", "param", "cl_start")),
                   unname(lapply(runs, `[`, c("q", "param", "cl_start"))))
  # S4: the run S3 with the balance correction
  s4 <- saved("s4_balance")
  expect_true(s4$cl_start)
  expect_identical(s4$param, runs$s3_cl_start$param)
  expect_length(sapply(s4$fits, `[[`, "balance"), n - 1)
  # a cl_paper run and its paper run differ in the start only: without
  # cl_start the name of the file alone would tell them apart
  paper <- saved("grid_20_rmsprop_paper_s2026")
  cl_paper <- saved("clgrid_20_rmsprop_cl_paper_s2026")
  expect_identical(cl_paper[c("age", "q", "param")],
                   paper[c("age", "q", "param")])
  expect_identical(c(paper$cl_start, cl_paper$cl_start), c(FALSE, TRUE))
  # the stand-in network after Listing 2's epochs: from the random start 2
  # and from the CL factor of Keras's training rows, half of the way to the
  # homogeneous CL factor of the learning cells in every epoch
  cells <- readRDS(file.path(interim, "nncl_synthetic_cells.rds"))
  cum <- as.matrix(cells[, paste0("cum_", 0:(n - 1)), with = FALSE])
  inputs <- readRDS(file.path(interim, "nncl_synthetic_inputs.rds"))
  f_hom <- readRDS(file.path(processed, "nncl_synthetic_homogeneous.rds"))$f_hom
  f_train <- sapply(1:(n - 1), function(j) {
    r <- inputs$learn_rows[[j]]
    r <- r[seq_len(floor(length(r) * (1 - cfg$nncl$training$validation_split)))]
    sum(cum[r, j + 1]) / sum(cum[r, j])
  })
  epochs <- cfg$nncl$training$epochs
  f_x <- function(f_start) {
    matrix(f_hom + (f_start - f_hom) / 2^epochs,
           nrow(inputs$x),
           n - 1,
           byrow = TRUE)
  }
  expect_equal(paper$f_x, f_x(2))
  expect_equal(cl_paper$f_x, f_x(f_train))
  expect_false(isTRUE(all.equal(f_x(f_train), f_x(2))))
  # no early stopping from the CL start: every epoch is run and used
  expect_equal(sapply(cl_paper$fits, `[[`, "epochs_used"), rep(epochs, n - 1))
  # cl_start: the early stopping of S2 from the CL start
  cl_start <- saved("clgrid_20_rmsprop_cl_start_s2026")
  expect_true(cl_start$cl_start && cl_start$param$early_stop)
  expect_equal(sapply(cl_start$fits, `[[`, "epochs_run"),
               rep(cfg$nncl$sensitivity$max_epochs, n - 1))
})

test_that("the final fits of the search keep the start of their mode", {
  search_script <- "NN chain ladder SynthETIC hyperparameter search.R"
  expect_equal(run_script(search_script, keras = TRUE), 0)
  seeds <- cfg$seed + seq_len(cfg$nncl$tuning$final_seeds) - 1
  tab_dir <- file.path(run_root, "output", "quick", "tables", "baseline",
                       "04_NN-chain-ladder", "synthetic")
  for (mode in names(cfg$nncl$tuning$modes)) {
    tuned <- lapply(paste0("tuned_", mode, "_s", seeds), saved)
    expect_equal(sapply(tuned, `[[`, "cl_start"),
                 rep(mode == "cl_start", length(seeds)))
    expect_equal(sapply(tuned, function(fit) fit$param$seed), seeds)
    expect_true(file.exists(file.path(tab_dir, paste0("nncl_tuning_", mode,
                                                      "_final.csv"))))
  }
  # the files of the tasks stay apart
  expect_length(run_files("tuned"), 3 * length(seeds))
  expect_equal(lengths(lapply(c("main", "grid", "cl_grid"), run_files)),
               c(7, 8, 8))
})
