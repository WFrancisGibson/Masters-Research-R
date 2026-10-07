##########################################
#########  checks of the bCCNN scripts of a unit (analysis/03_bCCNN: main
#########  fit, grid and masking study with their analyses), run as the
#########  final run runs them, under the quick profile on a fabricated
#########  triangle; no Keras: a fit script runs as a copy with the
#########  stand-ins of keras_stand_ins.R in place of library(keras3)
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
source(here::here("R", "nn_models.R"))

script_dir <- here::here("analysis", "03_bCCNN")
stand_ins <- here::here("tests", "testthat", "keras_stand_ins.R")
run_root <- gsub("\\\\", "/", tempfile("run_root"))
processed <- file.path(run_root, "data", "processed", "quick", "baseline")
tab_dir <- file.path(run_root, "output", "quick", "tables", "baseline",
                     "03_bCCNN")
fig_dir <- file.path(run_root, "output", "quick", "figures", "baseline",
                     "03_bCCNN")

## a script in an R session of its own with the environment of the final run
## (analysis/06_final-run: RUN_ROOT, the profile, the data set and, for a
## worker, RUN_SLOT and RUN_MAX); its exit status, 0: no error
run_script <- function(name, keras = FALSE, slot = NA, max_runs = NA) {
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
                      VALIDATION = NA,
                      FINAL_FIT = NA,
                      RUN_SLOT = slot,
                      RUN_MAX = max_runs)
  system2(file.path(R.home("bin"), "Rscript"),
          shQuote(script),
          stdout = file.path(run_root, "log.txt"),
          stderr = file.path(run_root, "log.txt"))
}

## fabricated triangles of 20 x 20 as "claims triangles.R" saves them: a
## cross-classified pattern with a calendar-year effect (for the "networks"
## to learn) and Poisson noise; the claims split halves every cell, except
## the development years 19 and 20, paid in the validation half only (the
## masked cells)
set.seed(1)
n <- 20
beta <- exp(-0.45 * (0:(n - 1)))
mu <- outer(4e8 * (1 + 0.03 * (1:n)), beta / sum(beta)) *
  exp(0.15 * sin((row(diag(n)) + col(diag(n))) / 3))
full <- matrix(1e4 * rpois(n * n, mu / 1e4), n, n,
               dimnames = list(origin = 1:n, dev = 1:n))
upper <- ifelse(row(full) + col(full) <= n + 1, full, NA)
train <- round(upper * runif(n * n, 0.48, 0.52), -4)
train[, 19:20] <- 0 * train[, 19:20]
dir.create(file.path(run_root, "data", "interim", "baseline"),
           recursive = TRUE)
saveRDS(list(full = full,
             upper = upper,
             test = ifelse(row(full) + col(full) > n + 1, full, NA),
             train = train,
             vali = upper - train,
             tail = rep(0, n)),
        file.path(run_root, "data", "interim", "baseline", "triangles.rds"))

test_that("the main fit and the grid fit under the four stopping rules", {
  expect_equal(run_script("bCCNN fit.R", keras = TRUE), 0)
  main_file <- file.path(processed, "bccnn_fit_rolling_origin_refit.rds")
  main <- readRDS(main_file)
  # two worker sessions share the 8 runs of the quick grid: the first takes
  # 5 (RUN_MAX), the second the other 3; no lock is left
  grid_files <- function() {
    list.files(processed, pattern = "^bccnn_grid_fit_.*[.]rds$")
  }
  expect_equal(run_script("bCCNN grid fit.R", TRUE, slot = 1, max_runs = 5), 0)
  expect_length(grid_files(), 5)
  expect_equal(run_script("bCCNN grid fit.R", TRUE, slot = 2, max_runs = 5), 0)
  cfg <- config::get(file = here::here("config.yml"), config = "quick")
  runs <- bccnn_grid_runs(cfg$bccnn$grid, cfg$seed)
  expect_setequal(grid_files(), paste0("bccnn_grid_fit_", names(runs), ".rds"))
  expect_length(grid_files(), 8)
  expect_length(list.files(processed, pattern = "[.](lock|tmp)$"), 0)
  expect_equal(run_script("bCCNN grid fit.R", TRUE, slot = 1), 0)  # all saved
  # the main fit refitted to another step, a run still to fit: the session
  # stops before it adds a run of another fixed number of steps to the
  # saved ones, and takes the run once the main fit is the one of these
  last_run <- file.path(processed, grid_files()[8])
  run_before <- readRDS(last_run)
  file.remove(last_run)
  refitted <- main
  refitted$best_epoch <- main$best_epoch + 50
  saveRDS(refitted, main_file)
  expect_equal(run_script("bCCNN grid fit.R", TRUE, slot = 1), 1)
  expect_length(grid_files(), 7)
  expect_length(list.files(processed, pattern = "[.](lock|tmp)$"), 0)
  saveRDS(main, main_file)
  expect_equal(run_script("bCCNN grid fit.R", TRUE, slot = 1), 0)
  expect_equal(readRDS(last_run)[c("fixed", "steps", "mu")],
               run_before[c("fixed", "steps", "mu")])
  #
  # a run of the first seed: the steps of every rule, their networks and
  # the loss curve of 300 steps
  rules <- c("minimum", "fixed", "moving_average", "patience")
  run <- readRDS(file.path(processed, paste0("bccnn_grid_fit_grid_20_tanh_",
                                             "d0.1_rmsprop_bfull_s2026.rds")))
  expect_named(run, c("run", "param", "final_fit", "fixed", "run_time",
                      "time_fit", "steps", "rolling_origin", "mu", "mu_test",
                      "epoch_blocks", "history", "epoch_time", "info"))
  expect_named(run$steps, rules)
  expect_equal(run$fixed, fixed_steps(main$best_epoch, 10))
  expect_equal(run$steps[["fixed"]], run$fixed)
  expect_equal(nrow(run$history), 301)
  expect_equal(dim(run$rolling_origin), c(12, 17))
  expect_named(run$mu, rules)
  expect_equal(sapply(run$mu_test$patience, nrow), c(15, 18))
  expect_equal(max(run$epoch_blocks$block), 3)
  expect_equal(run$info$slot, "1")
  # the stand-in network depends on the seed only: the rule "minimum" of
  # this run gives the steps, test errors and final network of "bCCNN fit.R"
  ro <- run$rolling_origin[run$rolling_origin$rule == "minimum", ]
  expect_equal(run$steps[["minimum"]], main$best_epoch)
  expect_lte(main$best_epoch, 100)
  expect_equal(ro$steps, main$rolling_origin$best_epoch)
  expect_equal(ro$test_loss_bCCNN, main$rolling_origin$test_loss_bCCNN)
  expect_equal(ro$test_bCCNN, main$rolling_origin$test_bCCNN)
  expect_equal(run$mu$minimum, main$mu_bccnn)
  # the other seeds keep neither the loss curve nor the times of every epoch
  run <- readRDS(file.path(processed, paste0("bccnn_grid_fit_grid_20_tanh_",
                                             "d0.1_rmsprop_b64_s2029.rds")))
  expect_null(run$history)
  expect_null(run$epoch_time)
  expect_equal(run$param$batch_size, 64)
})

test_that("the grid analysis has the stopping rule in every table", {
  expect_equal(run_script("bCCNN grid analysis.R"), 0)
  runs <- read.csv(file.path(tab_dir, "bccnn_grid_runs.csv"))
  expect_equal(nrow(runs), 8 * 4)                 # runs x rules
  expect_equal(as.vector(table(runs$rule)), rep(8, 4))
  expect_true(all(is.finite(runs$reserve) & is.finite(runs$bias_pct)))
  spread <- read.csv(file.path(tab_dir, "bccnn_grid_seed_spread.csv"))
  expect_equal(nrow(spread), 2 * 4)               # combinations x rules
  expect_equal(spread$seeds, rep(4, 8))
  # nagging predictors: two blocks of 2 seeds and one of 4 per combination
  # and rule
  nag <- read.csv(file.path(tab_dir, "bccnn_grid_nagging.csv"))
  expect_equal(nrow(nag), 2 * 3 * 4)
  expect_true(all(paste0("bias_pct_", c("nag2_b1", "nag2_b2", "nag4_b1")) %in%
                    names(spread)))
  effects <- read.csv(file.path(tab_dir, "bccnn_grid_main_effects.csv"))
  expect_equal(sort(unique(effects$setting)),
               c("activation", "batch_size", "dropout", "hidden", "optimizer",
                 "rule"))
  expect_equal(effects$runs[effects$setting == "rule"], rep(8, 4))
  # the rules side by side; the quick grid has no network of Paper C
  rules <- read.csv(file.path(tab_dir, "bccnn_grid_rules.csv"))
  expect_equal(rules$scope, rep("all combinations", 4))
  expect_equal(rules$rule, c("minimum", "fixed", "moving_average", "patience"))
  expect_equal(rules$steps_mean,
               as.vector(tapply(runs$steps, runs$rule, mean)[rules$rule]))
  expect_equal(rules$steps_sd[rules$rule == "fixed"], 0)
  expect_length(list.files(fig_dir, pattern = "^bCCNN grid .*[.]png$"), 9)
})

test_that("a diverged run is left out of the grid tables", {
  # the final network of one run under the rule "fixed" with an infinite
  # mean in the lower triangle: no reserve, so the means over the runs stay
  # finite and the run is counted as diverged
  run_file <- file.path(processed, paste0("bccnn_grid_fit_grid_20_tanh_",
                                          "d0.1_rmsprop_bfull_s2027.rds"))
  run <- readRDS(run_file)
  run$mu$fixed[20, 20] <- Inf
  saveRDS(run, run_file)
  expect_equal(run_script("bCCNN grid analysis.R"), 0)
  runs <- read.csv(file.path(tab_dir, "bccnn_grid_runs.csv"))
  diverged <- runs$seed == 2027 & runs$batch_size == "full" &
    runs$rule == "fixed"
  expect_equal(is.na(runs$reserve), diverged)
  expect_equal(is.na(runs$bias_pct), diverged)
  expect_true(all(is.finite(runs$test_loss_per_cell)))
  rules <- read.csv(file.path(tab_dir, "bccnn_grid_rules.csv"))
  expect_equal(rules$diverged, c(0, 1, 0, 0))
  expect_equal(rules$reserve_mean,
               as.vector(tapply(runs$reserve, runs$rule, mean,
                                na.rm = TRUE)[rules$rule]))
  expect_true(all(is.finite(unlist(rules[c("reserve_mean", "bias_pct_mean",
                                           "bias_pct_sd", "loss_out_mean",
                                           "closer_than_cl")]))))
  spread <- read.csv(file.path(tab_dir, "bccnn_grid_seed_spread.csv"))
  expect_equal(spread$diverged,
               as.numeric(spread$batch_size == "full" & spread$rule == "fixed"))
  expect_true(all(is.finite(spread$bias_pct_mean) &
                    is.finite(spread$bias_pct_max)))
  effects <- read.csv(file.path(tab_dir, "bccnn_grid_main_effects.csv"))
  expect_equal(sum(effects$diverged), 6)           # once per setting
  expect_true(all(is.finite(effects$bias_pct) &
                    is.finite(effects$abs_bias_pct)))
})

test_that("the masking study of the claims split", {
  expect_equal(run_script("bCCNN masking fit.R", keras = TRUE), 0)
  seed_files <- list.files(processed,
                           pattern = "^bccnn_masking_fit_s[0-9]+[.]rds$")
  expect_equal(seed_files, paste0("bccnn_masking_fit_s", 2026:2027, ".rds"))
  seed <- readRDS(file.path(processed, "bccnn_masking_fit_s2026.rds"))
  expect_named(seed, c("seed", "param", "run_time", "time_fit", "runs", "mu",
                       "history", "epoch_time", "info"))
  expect_equal(seed$runs$cells, c("all", "masked"))
  expect_named(seed$mu, c("all", "masked"))
  expect_equal(nrow(seed$history), 101)
  # one early-stopping run and one final network per number of steps
  expect_length(seed$epoch_time$refit, length(unique(seed$runs$steps)))
  expect_equal(run_script("bCCNN masking analysis.R"), 0)
  cells <- read.csv(file.path(tab_dir, "bccnn_masking_cells.csv"))
  expect_equal(c(cells$n_vali, cells$vali_masked), c(210, 3))
  masked <- read.csv(file.path(tab_dir, "bccnn_masking_masked_cells.csv"))
  expect_equal(masked[c("origin", "dev")],
               data.frame(origin = c(1, 2, 1), dev = c(19, 19, 20)))
  runs <- read.csv(file.path(tab_dir, "bccnn_masking_runs.csv"))
  expect_equal(runs[c("seed", "cells")],
               data.frame(seed = rep(2026:2027, each = 2),
                          cells = rep(c("all", "masked"), 2)))
  # the masked cells are part of the validation loss of all cells only
  expect_true(all(runs$vali_start[runs$cells == "all"] >
                    runs$vali_start[runs$cells == "masked"]))
  spread <- read.csv(file.path(tab_dir, "bccnn_masking_seed_spread.csv"))
  expect_equal(spread$seeds, c(2, 2))
  effect <- read.csv(file.path(tab_dir, "bccnn_masking_effect.csv"))
  steps <- matrix(runs$steps, 2)                  # rows: all, masked
  expect_equal(effect$steps_changed, sum(steps[1, ] != steps[2, ]))
  expect_equal(effect$steps_diff_mean, mean(steps[2, ] - steps[1, ]))
  expect_length(list.files(fig_dir, pattern = "^bCCNN masking .*[.]png$"), 2)
})
