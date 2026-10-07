##########################################
#########  Masters research: project setup
#########  every analysis script sources this file first
##########################################

suppressPackageStartupMessages({
  library(data.table)
  library(ChainLadder)
  library(ggplot2)
})

## settings (seed, paths, hyper-parameters) from config.yml; cfg$data is the
## block of the data set of this session (config.yml datasets, environment
## variable DATASET)
cfg <- config::get(file = here::here("config.yml"))
cfg$data <- cfg$datasets[[cfg$dataset]]

## the simulated claims of all data sets are in paths$raw; the interim files,
## fits and outputs of a data set, and of a unit of it (environment variable
## UNIT), are in their own folders under cfg$run_root
run_dir <- if (cfg$unit == "") cfg$dataset else
  file.path(cfg$dataset, cfg$unit)
paths <- lapply(cfg$paths, function(p) here::here(cfg$run_root, p, run_dir))
paths$raw <- here::here(cfg$paths$raw)
for (p in paths) dir.create(p, showWarnings = FALSE, recursive = TRUE)
set.seed(cfg$seed)

## Python side of keras3 (TensorFlow, CPU). On the VM the launcher names the
## environment that setup_vm.ps1 built from requirements.txt
## (RETICULATE_PYTHON) and these lines have no effect; on another computer
## reticulate builds it with uv from the pins declared here. keras3 drops a
## tensorflow requirement when it loads, so they are declared after its load
py_req <- trimws(sub("#.*", "", readLines(here::here("requirements.txt"))))
py_req <- py_req[py_req != ""]
reticulate::py_require(python_version = "3.12")
setHook(packageEvent("keras3", "onLoad"),
        function(...) reticulate::py_require(py_req))

## functions in R/
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

## package versions of the latest run (thesis appendix); not from the worker
## sessions of the final run (RUN_SLOT), which would all write it at once
if (Sys.getenv("RUN_SLOT") == "") {
  writeLines(capture.output(sessionInfo()),
             file.path(paths$logs, "sessionInfo.txt"))
}
