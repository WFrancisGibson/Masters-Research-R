##########################################
#########  checks of the functions in R/
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(ChainLadder)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

test_that("the ccODP model gives the chain-ladder reserves", {
  y <- unclass(cum2incr(GenIns))        # incremental, NA in the lower triangle
  odp <- ccodp_fit(y)
  cl <- sum(predict(chainladder(GenIns))[, 10] - getLatestCumulative(GenIns))
  expect_equal(sum(odp$reserve_o), cl, tolerance = 1e-8)
  expect_equal(c(odp$alpha[1], odp$beta[1]), c(0, 0))
})

test_that("the Keras poisson loss converts to the Poisson deviance", {
  set.seed(1)
  y <- rpois(50, 3)
  mu <- runif(50, 1, 5)
  loss <- mean(mu - y * log(mu))                  # Keras 'poisson' loss
  expect_equal(keras_to_deviance(loss, y), poisson_deviance(y, mu))
})

test_that("the triangles add up", {
  trans <- data.frame(claim_no = c(1, 1, 2, 3, 3, 4),
                      occurrence_period = c(1, 1, 1, 2, 2, 3),
                      payment_period = c(1, 4, 2, 2, 3, 3),
                      payment_inflated = 1:6)
  sets <- triangle_sets(trans, 3)
  expect_equal(sum(sets$full) + sum(sets$tail), sum(trans$payment_inflated))
  expect_equal(sets$tail, c(2, 0, 0))   # claim 1 pays in development period 4
  expect_equal(sum(sets$upper, na.rm = TRUE) + sum(sets$test, na.rm = TRUE),
               sum(sets$full))
  expect_equal(sum(sets$train, na.rm = TRUE) + sum(sets$vali, na.rm = TRUE),
               sum(sets$upper, na.rm = TRUE))
  expect_equal(claims_triangle(trans, 3, tail = TRUE)[1, 3], 2)
})

test_that("the dispersion is Pearson's (glmReserve) or Paper C's eq. (5)", {
  y <- unclass(cum2incr(GenIns))
  odp <- ccodp_fit(y)
  m <- glmReserve(GenIns)$model
  # glmReserve's glm stops at epsilon 1e-8, ccodp_fit at 1e-12
  expect_equal(odp$phi_pearson,
               with(m, sum(weights * residuals^2) / df.residual),
               tolerance = 1e-4)
  expect_equal(odp$phi_deviance, deviance(m) / df.residual(m),
               tolerance = 1e-8)
  expect_equal(odp$phi, odp$phi_deviance)
  expect_equal(odp$df, 55 - 19)          # |D_I| - (I + J), I = 10, J = 9
})

test_that("the chain ladder gives the ccODP reserves", {
  y <- unclass(cum2incr(GenIns))
  expect_equal(unname(cl_reserves(y)), unname(ccodp_fit(y)$reserve_o),
               tolerance = 1e-8)
})

test_that("the ODP sample is phi times a Poisson count on the cells", {
  set.seed(1)
  cells <- !is.na(upper_triangle(matrix(1, 4, 4)))
  y <- odp_sample(matrix(10, 4, 4), 2.5, cells)
  expect_true(all(is.na(y[!cells])))
  expect_equal(y[cells] / 2.5, round(y[cells] / 2.5))
  x <- replicate(4000, odp_sample(matrix(10, 1, 1), 2.5, TRUE)[1, 1])
  expect_equal(mean(x), 10, tolerance = 0.03)         # mean mu
  expect_equal(var(x), 25, tolerance = 0.1)           # variance phi times mu
})

test_that("the E&V bootstrap of zero residuals gives the CL reserves", {
  y <- unclass(cum2incr(GenIns))
  odp <- ccodp_fit(y)
  odp$y <- ifelse(odp$cells, odp$mu, NA)          # Pearson residuals 0
  boot <- ev_bootstrap(odp, 2)
  expect_equal(unname(boot[1, ]), unname(odp$reserve_o), tolerance = 1e-8)
  expect_equal(unname(boot[2, ]), unname(odp$reserve_o), tolerance = 1e-8)
})

test_that("the RMSEP adds the process and the bootstrap variance", {
  boot <- cbind(0, c(1, 3), c(2, 2))    # accident period 1 has no reserve
  tab <- rmsep_table("x", 2, c(0, 2, 2), boot)
  expect_equal(tab$origin, c("2", "3", "total"))
  expect_equal(tab$rmsep, sqrt(2 * c(2, 2, 4) + c(2, 0, 2)))
  tab <- rmsep_table("x", 2, c(0, 2, 2), boot, factor = 1.5)
  expect_equal(tab$rmsep, sqrt(2 * c(2, 2, 4) + 1.5 * c(2, 0, 2)))
})

test_that("rolling-origin partitions split the observed cells", {
  parts <- rolling_origin(upper_triangle(matrix(1, 20, 20)), c(5, 2), 2, 2)
  expect_equal(sapply(parts, function(p) p$origin), c(15, 18, 20))
  for (p in parts) {
    known <- !is.na(p$y)
    expect_false(any(p$train & p$vali))
    expect_true(all((p$train | p$vali) == known))
    expect_true(all(rowSums(p$train) > 0) && all(colSums(p$train) > 0))
    if (!p$final) expect_false(any(known & !is.na(p$test)))
  }
})

test_that("periods without payments are masked", {
  # the cells of the periods with no payments in y, fitted or not
  m <- matrix(1, 4, 4)
  y <- upper_triangle(matrix(c(1, 0, 1, 1), 4, 4))  # nothing paid in row 2
  y[1, 4] <- 0                                     # ... and in column 4
  masked <- mask_zero_periods(m, y)
  expect_true(all(is.na(masked[2, ])) && all(is.na(masked[, 4])))
  expect_equal(sum(is.na(masked)), 7)
  #
  # 20 x 20 triangle with payments in every cell: no cell is masked
  y <- matrix(1, 20, 20)
  parts <- rolling_origin(upper_triangle(y), c(5, 2), 2, 2)
  expect_identical(mask_partitions(parts), parts)
  #
  # partition 1 (valuation date 15): development period 13 pays in its
  # validation cell (3, 13) only, development period 14 in its test cells only
  y[, 13:14] <- 0
  y[3, 13] <- 50
  y[3:7, 14] <- 40
  parts <- rolling_origin(upper_triangle(y), c(5, 2), 2, 2)
  masked <- mask_partitions(parts)
  p1 <- parts[[1]]
  m1 <- masked[[1]]
  expect_true(p1$vali[3, 13] && !m1$vali[3, 13])
  expect_equal(sum(m1$vali), sum(p1$vali) - 1)
  # the chain ladder at 15 knows period 13 (test cells kept), not period 14
  expect_equal(which(is.na(m1$test) & !is.na(p1$test), arr.ind = TRUE)[, 2],
               rep(14, 5))
  expect_identical(m1[c("y", "train")], p1[c("y", "train")])
  # scored against the ccODP of the training cells, cell (3, 13) dominates
  odp <- suppressWarnings(ccodp_fit(p1$y, cells = p1$train))
  expect_gt(poisson_deviance(ifelse(p1$vali, p1$y, NA), odp$mu),
            1000 * poisson_deviance(ifelse(m1$vali, p1$y, NA), odp$mu))
  # by the final partition both periods have payments: no cell is masked
  expect_identical(masked[[3]], parts[[3]])
})
