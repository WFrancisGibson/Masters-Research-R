##########################################
#########  checks of the hyperparameter searches on rolling-origin folds
#########  (R/tuning.R, R/bccnn_tuning.R, R/nncl_tuning.R); no Keras: the
#########  network fits are replaced by stubs
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
for (f in c("runs.R", "triangles.R", "nn_models.R", "tuning.R",
            "bccnn_tuning.R", "nn_chain_ladder.R", "nncl_tuning.R")) {
  source(here::here("R", f))
}

## a score with a known minimum: dropout 0.1, hidden 40-30-20, activation
## tanh; runs of two valuation dates, the baseline scores 1 per cell
toy_score <- function(hp) {
  calls <<- calls + 1
  per_cell <- 1 + (hp$dropout - 0.1)^2 +
    0.01 * (sum(hp$hidden) != 90) + 0.02 * (hp$activation != "tanh")
  runs <- data.frame(seed = rep(1:2, each = 2), origin = c(15, 18, 15, 18),
                     n_test = c(60, 33, 60, 33), steps = 5)
  runs$loss <- per_cell * runs$n_test + c(0, 0, 0.93, 0)
  runs$loss_baseline <- runs$n_test
  tscv_summary(runs, hp)
}
cand <- list(dropout = c(0, 0.1, 0.2),
             hidden = list(c(20, 15, 10), c(40, 30, 20)),
             activation = c("tanh", "relu"))

test_that("tscv_summary pools per test cell and averages over the seeds", {
  calls <<- 0
  s <- toy_score(list(dropout = 0.3, hidden = 90, activation = "tanh"))
  expect_equal(unname(s$per_seed), 1.04 + c(0, 0.01))
  expect_equal(s$score, 1.045)
  expect_equal(s$score_baseline, 1)
  runs <- data.frame(seed = 1, origin = 15, n_test = 1, steps = 1,
                     loss = NaN, loss_baseline = 1)
  expect_equal(tscv_summary(runs, list())$score, Inf)   # diverged
})

test_that("grid search scores every combination and keeps the lowest", {
  calls <<- 0
  g <- tune_search(toy_score, cand, method = "grid", verbose = FALSE)
  expect_equal(calls, 12)
  expect_equal(nrow(g$table), 12)
  expect_equal(g$best, list(dropout = 0.1, hidden = c(40, 30, 20),
                            activation = "tanh"))
  expect_true(all(diff(g$table$score) >= 0))
})

test_that("successive search tunes one at a time, reuses and caches", {
  calls <<- 0
  dir <- tempfile("tuning")
  start <- list(dropout = 0.2, hidden = c(20, 15, 10), activation = "relu")
  s <- tune_search(toy_score, cand, start = start, cache_dir = dir,
                   verbose = FALSE)
  expect_equal(s$best, list(dropout = 0.1, hidden = c(40, 30, 20),
                            activation = "tanh"))
  # start; dropout 0 and 0.1; hidden 40-30-20; activation tanh
  expect_equal(calls, 5)
  expect_equal(s$path$tuned, c("start", "dropout", "hidden", "activation"))
  expect_true(all(diff(s$path$score) <= 0))
  # one file per scored set, none left half-written (save_run())
  expect_length(list.files(dir), 5)
  expect_true(all(grepl("\\.rds$", list.files(dir))))
  # run again: everything is read from the cache
  calls <<- 0
  s2 <- tune_search(toy_score, cand, start = start, cache_dir = dir,
                    verbose = FALSE)
  expect_equal(calls, 0)
  expect_equal(s2$best, s$best)
})

test_that("a set half-written by a stopped search is scored again", {
  # stand-in for saveRDS() in save_run(): the R session is stopped while it
  # writes the second set
  with_stand_ins <- function(f, stand_ins) {
    environment(f) <- list2env(stand_ins, parent = environment(f))
    f
  }
  writes <- 0
  stopped_save <- function(object, file, ...) {
    writes <<- writes + 1
    if (writes == 2) {
      writeLines("half a set", file)
      stop("stopped")
    }
    saveRDS(object, file, ...)
  }
  save_stopped <- with_stand_ins(save_run, list(saveRDS = stopped_save))
  search_stopped <- with_stand_ins(tune_search, list(save_run = save_stopped))
  dir <- tempfile("tuning")
  start <- list(dropout = 0.2, hidden = c(20, 15, 10), activation = "relu")
  calls <<- 0
  expect_error(search_stopped(toy_score, cand, start = start, cache_dir = dir,
                              verbose = FALSE),
               "stopped")
  # the start is saved; the half-written set is no .rds file
  expect_equal(sum(grepl("\\.rds$", list.files(dir))), 1)
  expect_length(list.files(dir), 2)
  # the next search reads the start and scores the other four sets
  calls <<- 0
  s <- tune_search(toy_score, cand, start = start, cache_dir = dir,
                   verbose = FALSE)
  expect_equal(calls, 4)
  expect_equal(s$best, list(dropout = 0.1, hidden = c(40, 30, 20),
                            activation = "tanh"))
  expect_length(list.files(dir), 5)
  expect_true(all(grepl("\\.rds$", list.files(dir))))
})

test_that("successive search keeps the current value on a tie", {
  # every set scores the same (all networks early-stopped at the ccODP
  # start) or diverges: no candidate scores lower, the start stays
  start <- list(dropout = 0.1, hidden = c(20, 15, 10), activation = "relu")
  for (loss in c(1, NaN)) {
    flat_score <- function(hp) {
      tscv_summary(data.frame(seed = 1, origin = 15, n_test = 60, steps = 0,
                              loss = 60 * loss, loss_baseline = 60),
                   hp)
    }
    s <- tune_search(flat_score, cand, start = start, verbose = FALSE)
    expect_identical(s$best, start)
    expect_equal(s$path$label, rep(hp_label(start), 4))
    expect_equal(s$best_score, if (is.nan(loss)) Inf else 1)
  }
  # a start that does not name the hyperparameter (the model's default,
  # here dropout 0.1) takes a candidate only if it scores lower
  calls <<- 0
  default_score <- function(hp) {
    if (is.null(hp$dropout)) hp$dropout <- 0.1
    toy_score(hp)
  }
  s <- tune_search(default_score, cand["dropout"],
                   start = list(hidden = 90, activation = "tanh"),
                   verbose = FALSE)
  expect_null(s$best$dropout)
  expect_equal(s$path$score, c(1.005, 1.005))
})

test_that("hp_grid, hp_label and hp_check", {
  g <- hp_grid(list(a = 1:2, hidden = list(c(1, 2), 3)))
  expect_length(g, 4)
  expect_equal(g[[4]], list(a = 2L, hidden = 3))
  expect_equal(hp_label(list(a = 1, hidden = c(20, 15))), "a=1, hidden=20-15")
  expect_error(hp_check(list(units = 3), bccnn_tunable),
               "not a tunable hyperparameter")
  # the optimiser of nncl_optimizer() and its momentum can be tuned; rho and
  # epsilon of RMSprop are no arguments of param
  expect_silent(hp_check(list(optimizer = "adam", momentum = 0.9),
                         bccnn_tunable))
  expect_error(hp_check(list(rho = 0.9), bccnn_tunable), "not a tunable")
  expect_error(hp_check(list(epsilon = 1e-7), bccnn_tunable), "not a tunable")
})

test_that("the bCCNN score uses the test partitions and the seeds", {
  parts <- rolling_origin(upper_triangle(matrix(1, 20, 20)), c(5, 2), 2, 2)
  seen <- NULL
  stub <- function(parts, truth, param, max_epochs, final_fit) {
    seen <<- rbind(seen, data.frame(seed = param$seed, dropout = param$dropout,
                                    n_parts = length(parts),
                                    final = any(sapply(parts, `[[`, "final"))))
    n_test <- sapply(parts, function(p) sum(!is.na(p$test)))
    list(summary = data.frame(origin = sapply(parts, `[[`, "origin"),
                              n_test = n_test, best_epoch = 7,
                              test_loss_bCCNN = 2 * n_test,
                              test_loss_ccODP = n_test,
                              test_loss_ccODP_train = 3 * n_test,
                              test_actual = 1, test_bCCNN = 1,
                              test_ccODP = 1,
                              time_early_stop = 4, time_refit = 0.5),
         epoch_time = data.frame(partition = "1", fit = "early_stop",
                                 epoch = 0:2, time = c(NA, 0.0514, 2),
                                 time_predict = 0.0026))
  }
  s <- bccnn_tscv_score(parts, list(dropout = 0.2), list(dropout = 0.1),
                        seeds = c(5, 6), max_epochs = 10, fit = stub)
  expect_equal(seen$seed, c(5, 6))
  expect_true(all(seen$dropout == 0.2 & seen$n_parts == 2 & !seen$final))
  expect_equal(sum(s$runs$n_test[s$runs$seed == 5]), 93)
  # the seconds of the fits stay with the runs, the milliseconds per epoch
  # of every seed with the set
  expect_equal(s$runs$time_early_stop + s$runs$time_refit, rep(4.5, 4))
  expect_named(s$epoch_time, c("seed", "partition", "fit", "epoch", "time",
                               "time_predict"))
  expect_equal(s$epoch_time$seed, rep(c(5, 6), each = 3))
  expect_identical(s$epoch_time$time, rep(c(NA, 51L, 2000L), 2))
  expect_equal(s$score, 2)
  expect_equal(s$score_baseline, 1)
  s_p <- bccnn_tscv_score(parts, list(), list(dropout = 0.1), seeds = 1,
                          max_epochs = 10, final_fit = "partition", fit = stub)
  expect_equal(s_p$score_baseline, 3)
  expect_error(bccnn_tscv_score(parts, list(units = 1), list(), 1, 10,
                                fit = stub), "not a tunable")
})

## NN chain ladder toy: I = 8 accident years, two cells per year (feature 0
## and 1), cumulative payments with feature effects on the CL factors
toy_cells <- function(n_ay = 8) {
  ay <- rep(1:n_ay, each = 2)
  x <- matrix(rep(0:1, n_ay), ncol = 1)
  f <- 1 + 0.5 * exp(-(1:(n_ay - 1)) / 2)
  cum <- matrix(0, length(ay), n_ay)
  cum[, 1] <- 10 * (1 + x[, 1]) * (1 + 0.1 * ay)
  for (j in 2:n_ay) cum[, j] <- cum[, j - 1] * (f[j - 1] + 0.05 * x[, 1])
  list(ay = ay, x = x, cum = cum)
}

test_that("nncl_origin: learning rows, part-1 rows and test cells at tau", {
  d <- toy_cells()
  org <- nncl_origin(d$cum, d$ay, tau = 6)
  expect_length(org$learn_rows, 5)                  # networks j = 1..5
  expect_true(all(d$ay[org$learn_rows[[2]]] <= 4))  # accident years to tau - j
  expect_true(all(d$ay[org$diag_rows] %in% 2:6))
  # test cells (i, j): tau < i + j <= I, j <= tau - 1, two cells each
  ij <- expand.grid(i = 2:6, j = 1:5)
  n_ij <- sum(ij$i + ij$j > 6 & ij$i + ij$j <= 8)
  expect_equal(nrow(org$test), 2 * n_ij)
  i_test <- d$ay[org$diag_rows[org$test$k]]
  expect_true(all(i_test + org$test$j > 6 & i_test + org$test$j <= 8))
})

test_that("projection with the true factors has no test loss", {
  d <- toy_cells()
  org <- nncl_origin(d$cum, d$ay, tau = 6)
  f_true <- sapply(1:5, function(j) {
    d$cum[org$diag_rows, j + 1] / d$cum[org$diag_rows, j]
  })
  tl <- nncl_test_loss(org, d$cum, nncl_project(org, f_true))
  expect_equal(tl[["loss"]], 0)
  expect_equal(tl[["actual"]], tl[["projected"]])
})

test_that("the NN chain ladder score: a homogeneous stub equals the CL", {
  d <- toy_cells()
  seen <- NULL
  # stub for nncl_fit(): the homogeneous CL factor sum C_j / sum C_{j-1} of
  # all its rows, 3 epochs in 2 seconds
  stub_cl <- function(x, y, w, x_new, q, param, f_start) {
    seen <<- rbind(seen, data.frame(q = paste(q, collapse = "-"),
                                    dropout = param$dropout,
                                    seed = param$seed,
                                    cl_start = !is.null(f_start)))
    list(f_new = rep(sum(y * w) / sum(w^2), nrow(x_new)),
         epochs_used = 3,
         run_time = 2)
  }
  run <- list(q = 20, cl_start = TRUE,
              param = list(dropout = 0, validation_split = 0.1, seed = 1))
  s <- nncl_tscv_score(d$cum, d$ay, d$x, origins = c(5, 6),
                       hp = list(dropout = 0.2, hidden = c(4, 3)), run = run,
                       seeds = c(11, 12), units = 10, fit = stub_cl)
  expect_equal(nrow(seen), 2 * (4 + 5))             # seeds x networks
  expect_true(all(seen$q == "4-3" & seen$dropout == 0.2 & seen$cl_start))
  expect_equal(sort(unique(seen$seed)), c(11, 12))
  # per seed and valuation date tau: the epochs and the seconds of its
  # tau - 1 networks
  expect_equal(s$runs$origin, c(5, 6, 5, 6))
  expect_equal(s$runs$steps, rep(3, 4))
  expect_equal(s$runs$time, c(8, 10, 8, 10))
  expect_equal(s$runs$loss, s$runs$loss_baseline)
  expect_equal(s$score, s$score_baseline)
  expect_gt(s$score, 0)                             # features matter
  # a stub with the true feature factors beats the chain ladder
  stub_x <- function(x, y, w, x_new, q, param, f_start) {
    f <- y / w[, 1]                                 # C_j / C_{j-1}
    list(f_new = ifelse(x_new[, 1] == 1, mean(f[x[, 1] == 1]),
                        mean(f[x[, 1] == 0])),
         epochs_used = 0,
         run_time = 1)
  }
  s_x <- nncl_tscv_score(d$cum, d$ay, d$x, origins = c(5, 6), hp = list(),
                         run = run, seeds = 1, units = 10, fit = stub_x)
  expect_lt(s_x$score, s_x$score_baseline)
  expect_equal(s_x$score, 0)
})
