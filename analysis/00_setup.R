##########################################
#########  Masters research: project setup
#########  every analysis script sources this file first
##########################################

suppressPackageStartupMessages({
  library(data.table)
  library(ChainLadder)
  library(ggplot2)
})

## settings (seed, paths, hyper-parameters) from config.yml
cfg <- config::get(file = here::here("config.yml"))
paths <- lapply(cfg$paths, here::here)
for (p in paths) dir.create(p, showWarnings = FALSE, recursive = TRUE)
set.seed(cfg$seed)

## functions in R/
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

## package versions of the latest run (thesis appendix)
writeLines(capture.output(sessionInfo()),
           file.path(paths$logs, "sessionInfo.txt"))
