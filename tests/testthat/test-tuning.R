##########################################
#########  checks of the hyperparameter searches on rolling-origin folds
#########  (R/tuning.R, R/bccnn_tuning.R, R/nncl_tuning.R); no Keras: the
#########  network fits are replaced by stubs
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
for (f in c("triangles.R", "tuning.R", "bccnn_tuning.R", "nncl_tuning.R")) {
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
  expect_length(list.files(dir), 5)
  # run again: everything is read from the cache
  calls <<- 0
  s2 <- tune_search(toy_score, cand, start = start, cache_dir = dir,
                    verbose = FALSE)
  expect_equal(calls, 0)
  expect_equal(s2$best, s$best)
})

test_that("hp_grid, hp_label and hp_check", {
  g <- hp_grid(list(a = 1:2, hidden = list(c(1, 2), 3)))
  expect_length(g, 4)
  expect_equal(g[[4]], list(a = 2L, hidden = 3))
  expect_equal(hp_label(list(a = 1, hidden = c(20, 15))), "a=1, hidden=20-15")
  expect_error(hp_check(list(units = 3), bccnn_tunable),
               "not a tunable hyperparameter")
})

test_that("the bCCNN score uses the test partitions and the seeds", {
  parts <- rolling_origin(upper_triangle(matrix(1, 20, 20)), c(5, 2), 2, 2)
  seen <- NULL
  stub <- function(parts, truth, param, max_epochs, final_fit, mask = FALSE) {
    seen <<- rbind(seen, data.frame(seed = param$seed, dropout = param$dropout,
                                    mask = mask,
                                    n_parts = length(parts),
                                    final = any(sapply(parts, `[[`, "final"))))
    n_test <- sapply(parts, function(p) sum(!is.na(p$test)))
    list(summary = data.frame(origin = sapply(parts, `[[`, "origin"),
                              n_test = n_test, best_epoch = 7,
                              test_loss_bCCNN = 2 * n_test,
                              test_loss_ccODP = n_test,
                              test_loss_ccODP_train = 3 * n_test,
                              test_actual = 1, test_bCCNN = 1,
                              test_ccODP = 1))
  }
  s <- bccnn_tscv_score(parts, list(dropout = 0.2), list(dropout = 0.1),
                        seeds = c(5, 6), max_epochs = 10, mask = TRUE,
                        fit = stub)
  expect_equal(seen$seed, c(5, 6))
  expect_true(all(seen$mask))
  expect_true(all(seen$dropout == 0.2 & seen$n_parts == 2 & !seen$final))
  expect_equal(sum(s$runs$n_test[s$runs$seed == 5]), 93)
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
  expect_true(all(d$ay[org$learn_rows[[2]]] <= 4))  # i <= tau - j
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
  # stub: the homogeneous CL factor sum C_j / sum C_{j-1} of all its rows
  stub_cl <- function(x, y, w, x_diag, q, param, f_start) {
    seen <<- rbind(seen, data.frame(q = paste(q, collapse = "-"),
                                    dropout = param$dropout,
                                    seed = param$seed,
                                    cl_start = !is.null(f_start)))
    list(f_diag = rep(sum(y * w) / sum(w^2), nrow(x_diag)), epochs_used = 3)
  }
  run <- list(q = 20, cl_start = TRUE,
              param = list(dropout = 0, validation_split = 0.1, seed = 1))
  s <- nncl_tscv_score(d$cum, d$ay, d$x, origins = c(5, 6),
                       hp = list(dropout = 0.2, hidden = c(4, 3)), run = run,
                       seeds = c(11, 12), units = 10, fit = stub_cl)
  expect_equal(nrow(seen), 2 * (4 + 5))             # seeds x networks
  expect_true(all(seen$q == "4-3" & seen$dropout == 0.2 & seen$cl_start))
  expect_equal(sort(unique(seen$seed)), c(11, 12))
  expect_equal(s$runs$loss, s$runs$loss_baseline)
  expect_equal(s$score, s$score_baseline)
  expect_gt(s$score, 0)                             # features matter
  # a stub with the true feature factors beats the chain ladder
  stub_x <- function(x, y, w, x_diag, q, param, f_start) {
    f <- y / w[, 1]                                 # C_j / C_{j-1}
    list(f_diag = ifelse(x_diag[, 1] == 1, mean(f[x[, 1] == 1]),
                         mean(f[x[, 1] == 0])),
         epochs_used = 0)
  }
  s_x <- nncl_tscv_score(d$cum, d$ay, d$x, origins = c(5, 6), hp = list(),
                         run = run, seeds = 1, units = 10, fit = stub_x)
  expect_lt(s_x$score, s_x$score_baseline)
  expect_equal(s_x$score, 0)
})
