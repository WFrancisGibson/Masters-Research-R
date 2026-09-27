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
