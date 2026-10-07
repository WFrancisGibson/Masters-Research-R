##########################################
#########  checks of the scripts of analysis/00_claim-simulation
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)

## the scripts of the folder and of lines-of-business (not the machine V1 of
## Gabrielli & Wuthrich, third-party code)
sim_dir <- here::here("analysis", "00_claim-simulation")
lob_dir <- file.path(sim_dir, "lines-of-business")
scripts <- list.files(c(sim_dir, lob_dir), pattern = "\\.R$", full.names = TRUE)

test_that("the simulation scripts have the extension .R and parse", {
  ## one SynthETIC script: its three predecessors are gone, two of them had
  ## no extension
  files <- setdiff(list.files(sim_dir),
                   list.dirs(sim_dir, full.names = FALSE, recursive = FALSE))
  expect_equal(tools::file_ext(files), rep("R", length(files)))
  expect_true("SynthETIC claims simulation.R" %in% files)
  for (f in scripts) expect_error(parse(file = f), NA)
})

test_that("a script that sets its data set also clears the unit", {
  ## such a script simulates or describes all LoBs of its data set; with a
  ## UNIT left in the session its files would go to <dataset>/<unit>
  ## (analysis/00_setup.R)
  lines <- unlist(lapply(scripts, readLines, warn = FALSE))
  calls <- grep("Sys.setenv(DATASET", lines, fixed = TRUE, value = TRUE)
  expect_gt(length(calls), 0)
  expect_equal(grepl("UNIT = \"\")", calls, fixed = TRUE),
               rep(TRUE, length(calls)))
})
