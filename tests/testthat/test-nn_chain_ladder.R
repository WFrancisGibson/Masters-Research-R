##########################################
#########  checks of the NN chain ladder functions (R/nn_chain_ladder.R)
#########  Wuthrich (2018), EAJ 8:407-436
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)
library(ChainLadder)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

## toy portfolio: one LoB, I = 4 accident years, development years 0..3;
## cells (accident year, feature) with cumulative payments, NA = not observed
toy <- function(cum, ay) {
  cum[ay + col(cum) - 1 > 4] <- NA
  vol <- rowsum(cum, ay)                         # the LoB triangle
  list(cum = cum,
       ay = ay,
       vol = vol,
       c_diag = cum[cbind(seq_along(ay), 5 - ay)])  # C_{i,I-i}(x)
}

test_that("(5.1) with the CL factors gives the CL reserves (Prop. 2.2)", {
  set.seed(1)
  cum <- t(apply(matrix(runif(32, 1, 10), 8, 4), 1, cumsum))
  d <- toy(cum, ay = rep(1:4, 2))
  f <- sapply(1:3, function(j) {
    sum(d$vol[1:(4 - j), j + 1]) / sum(d$vol[1:(4 - j), j])
  })
  f_prod <- sapply(4 - d$ay, function(m) prod(f[seq_len(3 - m) + m]))
  # no zero claims features: every zero set is empty, part 2 = 0
  ult_zero <- matrix(c(0, sapply(2:4, function(i) {
    nncl_zero_claims_factors(d$cum, d$ay, d$vol, i)$ultimate
  })), nrow = 1)
  expect_equal(ult_zero, matrix(0, 1, 4))
  res <- nncl_reserves(rep(1, 8), d$ay, d$c_diag, f_prod, ult_zero)
  tri <- as.triangle(d$vol)
  cl <- predict(chainladder(tri))[, 4] - getLatestCumulative(tri)
  expect_equal(res$reserve, as.numeric(cl))
})

test_that("zero claims factors of Section 4.2 match a hand calculation", {
  cum <- rbind(c(5, 8, 9, 9),       # AY 1, x = a
               c(0, 0, 2, 3),       # AY 1, x = b: zero at development year 1
               c(4, 6, 7, 7),       # AY 2, x = a
               c(0, 0, 1, 1),       # AY 2, x = b: zero at development year 1
               c(3, 5, 6, 6),
               c(0, 0, 1, 1),
               c(2, 3, 4, 4),
               c(0, 1, 1, 1))
  d <- toy(cum, ay = rep(1:4, each = 2))
  # accident year i = 3, m = I - i = 1: g_1 = (2 + 1) / (8 + 6), g_2 = 3 / 2
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3)
  expect_equal(z$factors$g, c(3 / 14, 3 / 2))
  expect_equal(z$ultimate, 5 * 3 / 14 * 3 / 2)
  # no development of the zero set in accident year 1: g_2 = 0/0 = 1
  d$cum[2, ] <- 0
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3)
  expect_equal(z$factors$g, c(1 / 14, 1))
  # a first payment at development year 3: g_2 = 3/0 takes the pooled ratio
  d$cum[2, 4] <- 3
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3, g_pooled = c(NA, 2))
  expect_equal(z$factors$g, c(1 / 14, 2))
  expect_equal(z$factors$pooled, c(FALSE, TRUE))
  expect_equal(z$ultimate, 5 / 14 * 2)
})

test_that("(5.1) stops on a zero claims factor with a zero denominator", {
  # a positive numerator over a zero denominator ('all denominators
  # positive', Section 4.2) gives an infinite reserve
  expect_error(nncl_reserves(1, 2, 0, 1, matrix(c(0, Inf), 1, 2)))
})
