##########################################
#########  checks of R/data_fingerprint.R
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

test_that("the rows of a fingerprint keep 15 significant digits", {
  fp <- fingerprint_rows("cells", c("a", "b"), c(1 / 3, 123456789012345.6))
  expect_equal(names(fp), c("table", "key", "type", "value"))
  expect_equal(fp$type, c("value", "value"))
  expect_equal(fp$value, c("0.333333333333333", "123456789012346"))
  ## counts are written in full, the text of an md5 sum as it is
  expect_equal(fingerprint_rows("n", 1:2, c(399568L, 1931764L), "count")$value,
               c("399568", "1931764"))
  expect_equal(fingerprint_rows("md5", "claims.csv", "ab12", "info")$value,
               "ab12")
})

test_that("a fingerprint read back from its file has no differences", {
  fp <- rbind(fingerprint_rows("n", c("claims", "payments"), c(5, 12), "count"),
              fingerprint_rows("cells", paste("AY", 1:3), c(0, 1e9 / 7, -2.5)),
              fingerprint_rows("md5", "claims.csv", "ab12", "info"))
  file <- tempfile(fileext = ".csv")
  fwrite(fp, file)
  old <- fread(file, colClasses = "character", data.table = FALSE)
  expect_equal(nrow(fingerprint_diff(fp, old)), 0)
  ## the md5 sums are not compared
  old$value[old$type == "info"] <- "cd34"
  expect_equal(nrow(fingerprint_diff(fp, old)), 0)
})

test_that("counts are compared exactly and values to the tolerance", {
  old <- rbind(fingerprint_rows("n", "claims", 400000, "count"),
               fingerprint_rows("cells", c("a", "b", "c"), c(1e9, 1e9, 0)))
  new <- old
  ## a value 1e-10 away (relative) is the same, 1e-8 away is not
  new$value[2:3] <- sprintf("%.15g", 1e9 * (1 + c(1e-10, 1e-8)))
  out <- fingerprint_diff(new, old)
  expect_equal(out$key, "b")
  expect_equal(out$value_old, "1000000000")
  ## one claim more: a relative difference of 2.5e-6, but a count
  new <- old
  new$value[1] <- "400001"
  expect_equal(fingerprint_diff(new, old)$key, "claims")
  ## values below 1: absolute difference
  new <- old
  new$value[4] <- "1e-12"
  expect_equal(nrow(fingerprint_diff(new, old)), 0)
  new$value[4] <- "1e-06"
  expect_equal(fingerprint_diff(new, old)$key, "c")
})

test_that("a key in one fingerprint only is a difference", {
  old <- fingerprint_rows("cells", c("a", "b"), c(1, 2))
  new <- fingerprint_rows("cells", c("a", "c"), c(1, 2))
  out <- fingerprint_diff(new, old)
  expect_equal(sort(out$key), c("b", "c"))
  expect_equal(nrow(fingerprint_diff(old[1, ], old)), 1)
})
