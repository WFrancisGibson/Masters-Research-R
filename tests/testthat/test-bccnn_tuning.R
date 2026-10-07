# Checks for the hyperparameter search of R/bccnn_tuning.R. No Keras: the
# fit of a partition is replaced by a stub with a known test deviance. From
# the project root:
#   Rscript -e "testthat::test_file('tests/testthat/test-bccnn_tuning.R')"
library(testthat)
for (f in c("triangles.R", "loss functions.R", "metrics.R",
            "classical_models.R", "fit ODP GLM", "nn_models.R",
            "bccnn_tuning.R")) {
  source(here::here("R", f))
}

parts <- rolling_origin_sets(upper(matrix(1, 20, 20)))
calls <- 0
# test deviance per cell: minimal at dropout 0.1 and q = c(40, 30, 20),
# plus a seed effect; the chain ladder scores 1 per cell
stub <- function(part, max_epochs, scale, phi, final_fit, ...) {
  calls <<- calls + 1
  a <- list(...)
  per_cell <- 1 + (a$dropout - 0.1)^2 + 0.01 * (sum(a$q) != 90) +
    a$seed / 1e5
  n_test <- sum(!is.na(part$test))
  list(origin = part$origin, n_test = n_test, best_epoch = part$origin,
       test = c(test_loss_bCCNN = per_cell * n_test,
                test_loss_ccODP = n_test))
}
fixed <- list(q = c(20, 15, 10), dropout = 0.1, learning_rate = 0.001)

test_that("the score pools the test partitions per cell and averages seeds", {
  calls <<- 0
  s <- bccnn_tscv_score(parts, list(dropout = 0.3), fixed = fixed,
                        seeds = c(1, 3), fit_partition = stub)
  expect_equal(calls, 4)               # 2 seeds x 2 test partitions
  expect_equal(sort(unique(s$runs$origin)), c(15, 18))
  expect_equal(sum(s$runs$n_test[s$runs$seed == 1]), 93)
  expect_equal(unname(s$per_seed), 1 + 0.04 + 0.01 + c(1, 3) / 1e5)
  expect_equal(s$score, 1 + 0.04 + 0.01 + 2 / 1e5)
  expect_equal(s$score_ccODP, 1)
  expect_error(bccnn_tscv_score(parts, list(units = 3), fit_partition = stub),
               "not a bCCNN hyperparameter")
  expect_error(bccnn_tscv_score(Filter(function(p) p$final, parts),
                                fit_partition = stub), "no test partitions")
})

test_that("the grid search scores every combination and keeps the lowest", {
  cand <- list(dropout = c(0, 0.1, 0.2),
               q = list(c(20, 15, 10), c(40, 30, 20)))
  g <- bccnn_grid_search(parts, cand, fixed = fixed, seeds = 1,
                         fit_partition = stub, verbose = FALSE)
  expect_equal(nrow(g$table), 6)
  expect_equal(g$best, list(dropout = 0.1, q = c(40, 30, 20)))
  expect_equal(g$table$label[1], "dropout=0.1, q=40-30-20")
  expect_true(all(diff(g$table$score) >= 0))
})

test_that("the successive search tunes one at a time and reuses scores", {
  calls <<- 0
  cand <- list(dropout = c(0, 0.2, 0.1),
               q = list(c(20), c(40, 30, 20)))
  s <- bccnn_successive_search(parts, start = list(dropout = 0.2,
                                                   q = c(20, 15, 10)),
                               candidates = cand, fixed = fixed, seeds = 1,
                               fit_partition = stub, verbose = FALSE)
  expect_equal(s$best, list(dropout = 0.1, q = c(40, 30, 20)))
  # start, dropout 0 and 0.1 (0.2 is the start), q c(20) and c(40, 30, 20),
  # the current q c(20, 15, 10) already scored: 5 sets x 2 partitions
  expect_equal(calls, 10)
  expect_equal(nrow(s$table), 5)
  expect_equal(s$path$tuned, c("start", "dropout", "q"))
  expect_true(all(diff(s$path$score) <= 0))
})

test_that("hp_grid and hp_label", {
  g <- hp_grid(list(a = 1:2, q = list(c(1, 2), 3)))
  expect_length(g, 4)
  expect_equal(g[[4]], list(a = 2L, q = 3))
  expect_equal(hp_label(list(a = 1, q = c(20, 15))), "a=1, q=20-15")
})
