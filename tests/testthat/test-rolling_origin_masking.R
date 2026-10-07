##########################################
#########  checks of the masking of periods without payments in the
#########  rolling origin (R/nn_models.R: zero_periods(), mask_periods(),
#########  rolling_origin_masked(), rolling_origin_fit(mask = TRUE)); no
#########  Keras: bccnn_fit() is replaced by a stub
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
for (f in c("triangles.R", "loss functions.R", "fit ODP GLM.R",
            "nn_models.R")) {
  source(here::here("R", f))
}

## 20 x 20 triangle; at valuation year 15: development period 13 pays only
## in its validation cell (3, 13), development period 14 pays nothing by
## year 15 but in its test cells (3..7, 14)
toy_parts <- function() {
  set.seed(1)
  n <- 20
  mu <- outer(exp(seq(0, 0.5, length.out = n)), 100 * exp(-0.3 * (0:(n - 1))))
  y <- matrix(rpois(n * n, mu) + 1, n)
  y[, 13] <- 0
  y[3, 13] <- 50
  y[, 14] <- 0
  y[3:7, 14] <- 40
  rolling_origin(upper_triangle(y), c(5, 2), 2, 2)
}

test_that("zero_periods and mask_periods", {
  y <- matrix(c(1, 0, 3, 0, 0, 0, 2, 0, 5), 3)
  z <- zero_periods(y, matrix(TRUE, 3, 3))
  expect_equal(z$origin, c(FALSE, TRUE, FALSE))
  expect_equal(z$dev, c(FALSE, TRUE, FALSE))
  m <- mask_periods(y, z)
  expect_equal(sum(is.na(m)), 5)
  expect_null(mask_periods(NULL, z))
  # payments outside 'cells' do not count
  expect_true(zero_periods(y, row(y) != 3)$dev[1] == FALSE)
  expect_true(zero_periods(y, col(y) != 3)$dev[3])
})

test_that("rolling_origin_masked counts the cells left out", {
  parts <- toy_parts()
  p1 <- parts[[1]]
  expect_equal(p1$origin, 15)
  expect_true(p1$vali[3, 13])
  mc <- rolling_origin_masked(parts)
  expect_equal(mc$vali_zero_devs[1], "13 14")   # no training payment
  expect_equal(mc$n_vali_masked[1], 1)          # the cell (3, 13)
  expect_equal(mc$test_zero_devs[1], "14")      # nothing paid by year 15
  expect_equal(mc$n_test_masked[1], 5)          # test cells (3..7, 14)
  expect_equal(mc$n_test_masked[3], 0)          # final partition: no test
})

test_that("rolling_origin_fit scores the masked cells only when asked", {
  parts <- toy_parts()[1]
  seen <- list()
  # stub of bccnn_fit(): records the scored cells, flat deviance curves
  bccnn_fit <<- function(odp, epochs, param, track) {
    seen[[length(seen) + 1]] <<- track
    h <- data.frame(epoch = 0:epochs)
    for (k in names(track)) {
      h[[k]] <- 1
      h[[paste0(k, "_pred")]] <- sum(!is.na(track[[k]]))
    }
    list(history = h, mu_path = list(), mu = odp$mu)
  }
  on.exit(rm(bccnn_fit, envir = globalenv()))
  r0 <- suppressWarnings(rolling_origin_fit(parts, NULL, list(), 5, "refit",
                                            mask = FALSE))$summary
  r1 <- suppressWarnings(rolling_origin_fit(parts, NULL, list(), 5, "refit",
                                            mask = TRUE))$summary
  expect_equal(r1$n_vali, r0$n_vali - 1)
  expect_equal(r1$n_test, r0$n_test - 5)
  expect_equal(c(r1$n_vali_masked, r1$n_test_masked), c(1, 5))
  expect_equal(c(r0$n_vali_masked, r0$n_test_masked), c(0, 0))
  # the early-stopping run (seen[[3]]) and the refit (seen[[4]]) of the
  # masked form: (3, 13) not in the validation cells, (3..7, 14) not tested
  expect_true(is.na(seen[[3]]$vali[3, 13]))
  expect_false(is.na(seen[[1]]$vali[3, 13]))
  expect_true(all(is.na(seen[[4]]$test[3:7, 14])))
  expect_false(any(is.na(seen[[2]]$test[3:7, 14])))
  # test cells of development period 13 (paid only in validation) stay in
  expect_false(any(is.na(seen[[4]]$test[4:8, 13])))
})
