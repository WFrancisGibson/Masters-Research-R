# Project setup: source this as the FIRST line of every analysis script
#
#   source(here::here("analysis", "00_setup.R"))
#
# It attaches the shared packages, reads config.yml, builds the project paths,
# sets the seed and loads the functions in R/. Packages only one strand needs
# (SynthETIC, keras3, ...) are loaded in that script, after this line.
# Installing packages is a one-off
# (renv::init() / renv::restore()), not done here.

# Shared packages
# data.table after tidyverse so data.table's between(), first(), last() win.
# Keep these as literal library() calls:
# renv finds dependencies by scanning them.
suppressPackageStartupMessages({
  library(tidyverse)
  library(data.table)
  library(dplyr)
  library(ChainLadder)
  library(ggplot2)
  library(SynthETIC)
  library(stats)
  library(keras3)

})


# config and here are only ever called with ::
# (library(config) would mask base get() and merge(),
# which data.table code uses)
cfg <- config::get(file = here::here("config.yml"))

# Project paths from config.yml, e.g. paths$raw, paths$tables, paths$logs
paths <- lapply(cfg$paths, here::here)
invisible(lapply(paths, dir.create, showWarnings = FALSE, recursive = TRUE))

set.seed(cfg$seed)

# Functions in R/ (functions only, no top-level code)
for (f in list.files(here::here("R"),
                     pattern = "\\.[Rr]$", full.names = TRUE)) {
  source(f)
}

# Package versions of the latest run, for the thesis appendix
writeLines(capture.output(sessionInfo()),
           file.path(paths$logs, "sessionInfo.txt"))
