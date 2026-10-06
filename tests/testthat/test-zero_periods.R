# Checks for mask_zero_periods() in R/nn_models.R and its use in the
# rolling-origin partitions. No Keras needed. From the project root:
#   Rscript -e "testthat::test_file('tests/testthat/test-zero_periods.R')"
library(testthat)
for (f in c("triangles.R", "loss functions.R", "metrics.R",
            "classical_models.R", "fit ODP GLM", "nn_models.R")) {
  source(here::here("R", f))
}

test_that("mask_zero_periods() masks exactly the flagged rows and columns", {
  m <- matrix(1:16, 4)
  fit <- list(zero_origin = c(FALSE, TRUE, FALSE, FALSE),
              zero_dev = c(FALSE, FALSE, FALSE, TRUE))
  mm <- mask_zero_periods(m, fit)
  expect_true(all(is.na(mm[2, ])) && all(is.na(mm[, 4])))
  expect_equal(sum(is.na(mm)), 7)
  expect_null(mask_zero_periods(NULL, fit))
  expect_error(mask_zero_periods(matrix(1, 3, 3), fit))
})

test_that("an empty development period in the training cells is masked", {
  set.seed(1)
  n <- 20
  mu <- outer(exp(seq(0, 0.5, length.out = n)), 100 * exp(-0.3 * (0:(n - 1))))
  y <- matrix(rpois(n * n, mu) + 1, n)
  y[, 13] <- 0
  y[3, 13] <- 50    # payment only in validation cell (3, 13) of partition 1
  y[, 14] <- 0
  y[3:7, 14] <- 40  # payments only in test cells of partition 1
  p1 <- rolling_origin_sets(upper(y))[[1]]
  expect_true(p1$vali[3, 13])

  odp <- suppressWarnings(fit_odp_glm(p1$y, cells = p1$train))
  cl <- suppressWarnings(fit_odp_glm(p1$y))
  expect_true(odp$zero_dev[13] && odp$zero_dev[14])
  expect_true(!cl$zero_dev[13] && cl$zero_dev[14])

  vali <- ifelse(p1$vali, odp$y, NA)
  # unmasked, the one cell scored against a mean of ~e^-30 dominates
  expect_gt(poisson_deviance(vali, odp$mu),
            10 * poisson_deviance(mask_zero_periods(vali, odp), odp$mu))
  # test cells: only column 14 (no payments at all by year 15) is dropped
  test <- mask_zero_periods(p1$test, cl)
  expect_equal(sum(!is.na(test)), sum(!is.na(p1$test)) - 5)
})
