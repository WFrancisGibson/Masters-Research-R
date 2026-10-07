##########################################
#########  Six lines of business: simulations with different seeds
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Appendix A, Table 8
#########  and Figures 9-10 (SSRN version of 2018: Table 7, Figures 7-8)
##########################################

## the data set of this script, all its LoBs: no unit, whatever the session
## inherits (the paths of a unit are <dataset>/<unit>)
Sys.setenv(DATASET = "lob6", UNIT = "")
source(here::here("analysis", "00_setup.R"))
library(MASS)          # mvrnorm in Feature.Generation
library(doParallel)    # foreach and parallel in Simulation.Machine

sim <- cfg$lob$simulation
machine_dir <- here::here("analysis", "00_claim-simulation",
                          "Simulation.Machine.V1")
pay_cols <- sprintf("Pay%02d", 0:(cfg$data$n_dev - 1))
## the paper: seeds 1 to 100, the selected simulation (seed 75) among them
seeds <- union(seq_len(cfg$lob$seed_study$seeds), sim$seed1)

##########################################
#########  random number generator
##########################################

## as in "lines of business simulation.R"
if (sim$rng_rounding) machine_rng_rounding()
RNGkind()
cl <- makeCluster(1)
worker_kind <- clusterEvalQ(cl, RNGkind()[3])[[1]]
stopCluster(cl)
stopifnot(worker_kind == RNGkind()[3])

##########################################
#########  simulate (Listing 1 with seed1 = 1, ..., 100)
##########################################

## per seed and LoB: number of claims, true reserves and chain-ladder
## reserves at the end of 2005, as simulated (not in 1'000). One file per
## seed: a stopped run resumes at the first missing one, and several R
## sessions share the seeds (claim_run, R/runs.R); delete the files after a
## change of cfg$lob$simulation. Table 8 and the figures: "lines of business
## seed study analysis.R"
old_wd <- setwd(machine_dir)
source("Functions.V1.R")
detectCores <- function() sim$workers + 1  # nolint: object_name_linter.
for (s in seeds) {
  run_file <- file.path(paths$processed,
                        sprintf("lob_seed_study_%03d.rds", s))
  if (!claim_run(run_file)) next
  t0 <- Sys.time()
  claims <- lob_simulate(sim, seed = s)
  tri <- lob_triangles(as.matrix(claims[, pay_cols]), claims$LoB, claims$AY)
  seconds <- as.numeric(Sys.time() - t0, units = "secs")
  save_run(list(seed = s,
                reserves = cbind(claims = as.numeric(table(claims$LoB)),
                                 lob_reserves(tri)),
                seconds = seconds,
                info = run_info()),
           run_file)
  cat(format(Sys.time(), "%H:%M"), "seed", s, "done in", round(seconds),
      "seconds\n")
}
setwd(old_wd)
Sys.unsetenv("R_PROFILE_USER")
RNGkind(sample.kind = "default")
