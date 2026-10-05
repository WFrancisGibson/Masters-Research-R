## checks the age_numeric fits in data/processed against the laptop's cells:
## the runs of the grid by seed, 19 networks, the CL factors of the 3,167
## part-1 cells, coding "numeric"; lists the runs with a diverged network;
## run from the project folder:
## Rscript "Claude outputs/nncl-parallel-workers/check_cloud_fits.R" [folder]
dir <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(dir)) dir <- "."
cells <- readRDS("data/interim/nncl_synthetic_cells.rds")
n_diag <- sum(cells$i > 1 & cells$c_diag > 0)
files <- list.files(file.path(dir, "data/processed"),
                    pattern = "^nncl_synthetic_age_numeric_fit_.*[.]rds$",
                    full.names = TRUE)
runs <- gsub("^nncl_synthetic_age_numeric_fit_|[.]rds$", "", basename(files))
check <- t(sapply(files, function(file) {
  run <- readRDS(file)
  f_diag <- lapply(run$fits, function(fit) fit$f_diag)
  c(shape = length(f_diag) == 19 && all(lengths(f_diag) == n_diag),
    numeric = identical(run$age, "numeric"),
    finite = all(is.finite(unlist(f_diag))))
}))
c("part-1 cells of the laptop" = n_diag,
  "fit files" = length(runs),
  "of the right shape" = sum(check[, "shape"]),
  "coding numeric" = sum(check[, "numeric"]),
  "with a diverged network" = sum(!check[, "finite"]))
## runs of the grid by seed (60 each) and the main runs
table(gsub("^.*_s", "", grep("^grid_", runs, value = TRUE)))
grep("^grid_", runs, value = TRUE, invert = TRUE)
## runs of the wrong shape or coding, and runs with a diverged network
runs[!check[, "shape"] | !check[, "numeric"]]
runs[!check[, "finite"]]
