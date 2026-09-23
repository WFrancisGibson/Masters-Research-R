# Checks for R/classical_models.R. From the project root:
#   Rscript -e "testthat::test_file('tests/testthat/test-classical_models.R')"
library(testthat)
suppressPackageStartupMessages(library(ChainLadder))
source(here::here("R", "classical_models.R"))

test_that("each wrapper reproduces its package function with the package defaults", {
  m <- MackChainLadder(RAA)
  f <- fit_mack(RAA)
  expect_equal(f$by_origin$ibnr, summary(m)$ByOrigin$IBNR)
  expect_equal(f$by_origin$se, summary(m)$ByOrigin$Mack.S.E)
  expect_equal(f$total[["se"]], unname(m$Total.Mack.S.E))

  cl <- fit_chainladder(RAA)
  expect_equal(unname(cl$factors), unname(attr(ata(RAA), "vwtd")))
  expect_equal(unclass(cl$full_triangle), unclass(predict(chainladder(RAA))))

  g <- glmReserve(GenIns)
  gf <- fit_glm_reserve(GenIns)
  expect_equal(gf$total[["ibnr"]], g$summary["total", "IBNR"])
  expect_equal(gf$total[["se"]], g$summary["total", "S.E"])
})

test_that("chainladder delta = 1, Mack alpha = 1 and the ODP GLM give one reserve", {
  cl <- fit_chainladder(GenIns)$total[["ibnr"]]
  mk <- fit_mack(GenIns)$total[["ibnr"]]
  gl <- fit_glm_reserve(GenIns)$total[["ibnr"]]
  expect_equal(cl, mk, tolerance = 1e-10)
  expect_equal(gl, mk, tolerance = 1e-6)
})

test_that("delta = 2 - alpha", {
  expect_equal(fit_chainladder(RAA, delta = 2)$total[["ibnr"]],
               fit_mack(RAA, alpha = 0)$total[["ibnr"]])
  expect_equal(fit_chainladder(RAA, delta = 0)$total[["ibnr"]],
               fit_mack(RAA, alpha = 2)$total[["ibnr"]])
})

test_that("origin results add up to the totals", {
  for (f in list(fit_chainladder(GenIns), fit_mack(GenIns), fit_glm_reserve(GenIns))) {
    expect_equal(sum(f$by_origin$ibnr), f$total[["ibnr"]], tolerance = 1e-6)
    expect_equal(nrow(f$by_origin), nrow(GenIns))
  }
})

test_that("incremental, data.frame and full-square inputs give the same fit", {
  ref <- fit_mack(GenIns)$total
  expect_equal(fit_mack(cum2incr(GenIns), cum = FALSE)$total, ref)

  df <- data.frame(AY = rownames(GenIns), unclass(GenIns)[, ], check.names = FALSE)
  expect_equal(fit_mack(df)$total, ref)

  full <- fit_mack(GenIns)$full_triangle            # a completed square: holds the future
  expect_message(p <- prepare_triangle(full), "set to NA")
  expect_equal(as.numeric(p), as.numeric(GenIns))
  expect_equal(fit_mack(full)$total, ref)
})

test_that("options reach the package functions", {
  expect_gt(fit_mack(RAA, tail = TRUE)$total[["ibnr"]], fit_mack(RAA)$total[["ibnr"]])
  expect_false(isTRUE(all.equal(fit_mack(RAA, mse.method = "Independence")$total[["se"]],
                                fit_mack(RAA)$total[["se"]])))
  gam <- fit_glm_reserve(GenIns, var.power = 2)
  expect_false(isTRUE(all.equal(gam$total[["se"]], fit_glm_reserve(GenIns)$total[["se"]])))
  tw <- fit_glm_reserve(GenIns, var.power = NULL)
  expect_true(tw$var_power > 1 && tw$var_power < 2)
  set.seed(1)
  bt <- suppressWarnings(fit_glm_reserve(GenIns, mse.method = "bootstrap", nsim = 50))
  expect_length(bt$simulations$total, 50)
})

test_that("a triangle that already has NA is used as it is (not re-masked)", {
  q12 <- qpaid[, 1:12]         # annual origins x quarterly dev: diagonal is not i + j = n + 1
  expect_equal(fit_mack(q12)$total[["ibnr"]],
               sum(summary(MackChainLadder(q12))$ByOrigin$IBNR))
  expect_error(prepare_triangle(q12, mask_future = TRUE), "already has NA")
  expect_error(prepare_triangle(matrix(1, 3, 5)), "full 3 x 5 rectangle")
  expect_silent(prepare_triangle(matrix(1, 3, 5), mask_future = FALSE))
})

test_that("wide, long, row-name and integer64 inputs are read correctly", {
  ref <- fit_mack(GenIns)$total
  v_names <- as.data.frame(unname(unclass(GenIns)))              # columns V1..V10
  expect_equal(fit_mack(v_names)$total, ref)
  expect_equal(fit_mack(as.data.frame(GenIns))$total, ref)       # long.triangle
  expect_error(fit_mack(GenInsLong), "does not look like a wide triangle")
  expect_equal(fit_mack(GenInsLong, format = "long",
                        long_cols = c(origin = "accyear", dev = "devyear",
                                      value = "incurred claims"))$total, ref)
  rn <- as.data.frame(unclass(RAA))                              # origins in row names
  expect_equal(fit_mack(rn)$by_origin$origin[1], "1981")
  skip_if_not_installed("bit64")
  i64 <- as.data.frame(lapply(as.data.frame(unclass(GenIns) * 1000), bit64::as.integer64))
  i64 <- cbind(AY = 1:10, i64)
  expect_equal(fit_mack(i64)$total[["ibnr"]], 1000 * ref[["ibnr"]], tolerance = 1e-10)
})

test_that("fit_mack keeps origins whose latest value is 0", {
  r0 <- RAA; r0[10, 1] <- 0
  expect_equal(nrow(fit_mack(r0)$by_origin), 10)
})

test_that("an NA inside observed increments stops instead of truncating the row", {
  g_inc <- cum2incr(GenIns); g_inc[3, 4] <- NA
  expect_error(fit_mack(g_inc, cum = FALSE), "NA cell")
})

test_that("an exposure attribute on the input reaches glmReserve", {
  g <- GenIns; attr(g, "exposure") <- (1:10) * 1000
  expect_equal(coef(fit_glm_reserve(g)$model$model), coef(glmReserve(g)$model))
})

test_that("fit_glm_reserve stops clearly on negative increments", {
  expect_error(fit_glm_reserve(RAA), "negative incremental")   # RAA 1982 dev 7 = -103
})

test_that("the simulated triangle.csv (full square) is masked before fitting", {
  path <- here::here("data", "raw", "claim-simulation", "triangle.csv")
  skip_if_not(file.exists(path))
  tri <- data.table::fread(path)
  expect_message(f <- fit_mack(tri, cum = FALSE, est.sigma = "Mack"), "780 cells")
  # triangle.csv lumps dev > 40 into column 40 (runoff = 1); chain ladder reserve
  # on it, as found in R model/Chain ladder on claims simulation environment 1
  expect_equal(f$total[["ibnr"]], 7433102318, tolerance = 1e-9)
})
