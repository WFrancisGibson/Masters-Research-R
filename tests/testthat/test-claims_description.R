##########################################
#########  checks of the claims description functions in
#########  R/claims_description.R
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)
library(ChainLadder)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

test_that("the relativity of a combination is the product over the pairs", {
  rel <- data.frame(factor_i = c("a", "a", "a", "a", "a", "a", "b", "b"),
                    factor_j = c("a", "a", "b", "b", "b", "b", "b", "b"),
                    level_ik = c("x", "y", "x", "x", "y", "y", "u", "v"),
                    level_jl = c("x", "y", "u", "v", "u", "v", "u", "v"),
                    relativity = c(2, 3, 1, 0.5, 0, 1, 5, 7))
  combos <- expand.grid(a = c("x", "y"), b = c("u", "v"))
  # (x, u): 2 * 1 * 5; (y, u): 3 * 0 * 5; (x, v): 2 * 0.5 * 7; (y, v): 3 * 7
  expect_equal(combo_relativity(combos, rel), c(10, 0, 7, 21))
})

test_that("the relativities agree with SynthETIC's on its test covariates", {
  skip_if_not_installed("SynthETIC")
  cov <- SynthETIC::test_covariates_obj
  combos <- expand.grid(cov$factors)
  cov_data <- SynthETIC::covariates_data(cov, data = combos)
  for (k in c("freq", "sev")) {
    rel <- cov[[paste0("relativity_", k)]]
    expect_equal(combo_relativity(combos, rel),
                 unname(SynthETIC::covariates_relativity(cov_data, k)))
  }
})

test_that("the chain-ladder factors are Mack's", {
  cum <- unclass(GenIns)
  full <- predict(chainladder(GenIns))           # any completed triangle
  f <- cl_factors(unclass(full))
  expect_equal(f, unname(sapply(chainladder(GenIns)$Models, coef)))
  expect_equal(f[1], sum(cum[1:9, 2]) / sum(cum[1:9, 1]))
})

test_that("Cramer's V is 0 for independent and 1 for identical variables", {
  a <- rep(c("x", "y", "z"), each = 4)
  b <- rep(c("u", "v"), times = 6)
  expect_equal(cramers_v(a, b), 0)
  expect_equal(cramers_v(a, a), 1)
  expect_equal(cramers_v(b, a), cramers_v(a, b))
})

test_that("the Gini coefficient is 0 for equal amounts", {
  expect_equal(gini(rep(5, 10)), 0)
  expect_equal(gini(c(0, 0, 0, 1)), 0.75)        # (n - 1) / n: one has all
})

test_that("the summaries by level stack the rows once per feature", {
  d <- data.table(a = factor(c("x", "y", "x"), levels = c("y", "x")),
                  b = factor(c("u", "u", "v"), levels = c("u", "v")),
                  amount = 1:3)
  long <- level_long(d, c("a", "b"))
  expect_equal(nrow(long), 6)
  expect_equal(levels(long$level), c("y", "x", "u", "v"))
  tab <- long[, .(amount = sum(amount)), keyby = .(feature, level)]
  expect_equal(as.character(tab$level), c("y", "x", "u", "v"))
  expect_equal(tab$amount, c(2, 4, 3, 3))
})

test_that("the log-linear model recovers multiplicative effects", {
  x <- expand.grid(a = c("x", "y"), b = c("u", "v", "w"), rep = 1:50)[, 1:2]
  mult <- c(x = 1, y = 2)[as.character(x$a)] *
    c(u = 1, v = 0.5, w = 3)[as.character(x$b)]
  # without noise the effects are exact; the reference level is not the first
  fit <- log_linear_effects(10 * mult, x, c("y", "u"))
  expect_equal(fit$feature, c("a", "b", "b"))
  expect_equal(fit$level, c("x", "v", "w"))
  expect_equal(fit$estimate, c(0.5, 0.5, 3))
  set.seed(1)
  fit <- log_linear_effects(10 * mult * rlnorm(nrow(x), 0, 0.5), x,
                            c("x", "u"))
  expect_true(all(fit$lower < c(2, 0.5, 3) & c(2, 0.5, 3) < fit$upper))
})

test_that("the variance shares add up for independent factors", {
  x <- expand.grid(a = c("x", "y"), b = c("u", "v", "w"), rep = 1:20)[, 1:2]
  set.seed(1)
  y <- c(x = 0, y = 2)[as.character(x$a)] +
    c(u = 0, v = 1, w = 3)[as.character(x$b)] + rnorm(nrow(x))
  r2 <- r2_features(y, x)
  expect_equal(r2$term, c("a", "b", "additive", "saturated"))
  # balanced design: one-way = drop-one, and they add up to the additive R2
  expect_equal(r2$one_way[1:2], r2$drop_one[1:2])
  expect_equal(sum(r2$one_way[1:2]), r2$r2[3])
  expect_equal(r2$r2[3], summary(lm(y ~ a + b, data = x))$r.squared)
  expect_equal(r2$r2[4], summary(lm(y ~ a * b, data = x))$r.squared)
})

test_that("the portfolio at the valuation date adds up", {
  dir <- file.path(tempdir(), "portfolio")
  dir.create(dir, showWarnings = FALSE)
  # claim 1: paid in years 1 and 3; claim 2: reported in year 3, open
  fwrite(data.frame(claim_no = 1:2,
                    occurrence_period = c(1, 2),
                    occurrence_time = c(0.5, 1.8),
                    notidel = c(0.2, 0.4),
                    setldel = c(2, 1.5),
                    f = c("b", "a")),
         file.path(dir, "claims.csv"))
  fwrite(data.frame(claim_no = c(1, 1, 2),
                    occurrence_period = c(1, 1, 2),
                    occurrence_time = c(0.5, 0.5, 1.8),
                    payment_time = c(0.9, 2.7, 3.7),
                    payment_period = c(1, 3, 4),
                    payment_size = c(10, 20, 5),
                    payment_inflated = c(11, 22, 6)),
         file.path(dir, "transactions.csv"))
  saveRDS(list(factors = list(f = c("b", "a"))),
          file.path(dir, "covariates_5factor.rds"))
  port <- synthetic_portfolio(dir, 3)
  expect_equal(port$features, "f")
  expect_equal(levels(port$claims$f), c("b", "a"))
  expect_equal(port$claims$ultimate, c(33, 6))
  expect_equal(port$claims$paid, c(33, 0))
  expect_equal(port$claims$outstanding, c(0, 6))
  expect_equal(port$claims$rep_delay, c(0, 1))
  expect_equal(as.character(port$claims$status), c("closed", "open"))
  expect_equal(port$claims$lag_paid, c(11 * 0.4 + 22 * 2.2, 6 * 1.9))
  expect_equal(port$trans$dev, c(1, 3, 3))
  expect_equal(as.character(synthetic_portfolio(dir, 2)$claims$status),
               c("open", "unreported"))
})
