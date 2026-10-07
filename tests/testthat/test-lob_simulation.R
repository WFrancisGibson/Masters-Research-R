##########################################
#########  checks of R/lob_simulation.R
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

test_that("the triangles by LoB give the true and the CL reserves", {
  ## five claims, two LoBs, accident years 1994-1995, development years 0-1
  pay <- matrix(c(10, 20, 30, 4, 6,
                  5, 8, 15, 2, 3),
                ncol = 2,
                dimnames = list(NULL, c("Pay00", "Pay01")))
  lob <- c(1, 1, 1, 2, 2)
  ay <- c(1994, 1995, 1994, 1995, 1994)
  tri <- lob_triangles(pay, lob, ay)
  expect_equal(names(tri), c("1", "2"))
  expect_equal(dimnames(tri[["1"]]),
               list(AY = c("1994", "1995"), DY = c("0", "1")))
  expect_equal(unname(tri[["1"]]), matrix(c(40, 20, 20, 8), 2))
  expect_equal(unname(tri[["2"]]), matrix(c(6, 4, 3, 2), 2))
  ## lower triangle: cell (1995, 1); CL factor 60 / 40 and 9 / 6
  expect_equal(lob_reserves(tri),
               matrix(c(8, 2, 10, 2),
                      2,
                      dimnames = list(c("1", "2"), c("true", "cl"))))
  ## a run of "lines of business seed study.R": the claims next to the
  ## reserves; its analysis script reads the rows by LoB and these columns
  run <- cbind(claims = as.numeric(table(lob)), lob_reserves(tri))
  expect_equal(dimnames(run), list(c("1", "2"), c("claims", "true", "cl")))
  expect_equal(run[, "claims"], c("1" = 3, "2" = 2))
})

test_that("the check against a paper rounds by quantity", {
  paper <- matrix(c(1.3, 10, 2.3, 21),
                  2,
                  dimnames = list(c("a", "b"), c("LoB 1", "LoB 2")))
  out <- paper_check(matrix(c(1.26, 10.4, 2.34, 19.6), 2),
                     paper,
                     digits = c(1, 0))
  expect_equal(out$quantity, rep(c("a", "b"), each = 3))
  expect_equal(out$source,
               rep(c("simulated", "paper", "difference"), times = 2))
  expect_equal(out[["LoB 1"]], c(1.3, 1.3, 0, 10, 10, 0))
  expect_equal(out[["LoB 2"]], c(2.3, 2.3, 0, 20, 21, -1))
})

test_that("the claims split alternates within LoB and accident year", {
  ## seven claims in any order: sorted by LoB and accident year (ties in the
  ## order given) they are the claims 2, 5, 1, 4, 3, 7, 6
  lob <- c(1, 1, 2, 1, 1, 2, 2)
  ay <- c(1995, 1994, 1994, 1995, 1994, 1995, 1994)
  vali <- lob_split(lob, ay)
  expect_equal(vali, c(1, 1, 1, 2, 2, 1, 2))
  ## Paper C Listing 2: sort the claims, then alternate
  o <- order(lob, ay)
  expect_equal(vali[o], rep(c(1, 2), length.out = 7))
  ## sorted claims get 1, 2, 1, 2, ... as "lines of business simulation.R"
  expect_equal(lob_split(lob[o], ay[o]), rep(c(1, 2), length.out = 7))
})
