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
