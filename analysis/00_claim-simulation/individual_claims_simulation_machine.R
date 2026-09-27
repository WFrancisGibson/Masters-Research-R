##########################################
#########  Individual claims simulation machine
#########  Gabrielli & Wuthrich (2018), Risks 6(2):29, machine V1;
#########  the portfolio of Wuthrich (2018), EAJ 8:407-436, Listing 1
##########################################

source(here::here("analysis", "00_setup.R"))
library(MASS)          # mvrnorm in Feature.Generation
library(doParallel)    # foreach and parallel in Simulation.Machine

sim <- cfg$nncl$simulation
## the original machine V1, unmodified
machine_dir <- here::here("analysis", "00_claim-simulation",
                          "Simulation.Machine.V1")
out_dir <- file.path(paths$raw, cfg$nncl$data_dir)
last_ay <- cfg$nncl$first_ay + cfg$nncl$n_ay - 1   # 2005, the valuation date I

##########################################
#########  random number generator
##########################################

## the paper ran R < 3.6, whose sample() used sample.kind "Rounding"; the
## machine calls sample() in the master and in its PSOCK workers, fresh Rscript
## sessions that read the profile R_PROFILE_USER points to
if (sim$rng_rounding) {
  RNGkind(sample.kind = "Rounding")
  profile <- tempfile(fileext = ".R")
  writeLines('RNGkind(sample.kind = "Rounding")', profile)
  Sys.setenv(R_PROFILE_USER = profile)
}
RNGkind()
## sample.kind of a worker
cl <- makeCluster(1)
clusterEvalQ(cl, RNGkind()[3])
stopCluster(cl)

##########################################
#########  simulate the claims (Listing 1)
##########################################

## the machine reads its parameter files from the working directory
## ("./Parameters/...") and the workers inherit it; after an error restart R
old_wd <- setwd(machine_dir)
source("Functions.V1.R")
t0 <- Sys.time()
features <- Feature.Generation(V = sim$expected_claims,
                               LoB.dist = sim$lob_dist,
                               inflation = sim$growth,
                               seed1 = sim$seed1)
## one block (npb = number of claims): every block reuses the same seeds
claims <- Simulation.Machine(features = features,
                             npb = nrow(features),
                             seed1 = sim$seed1,
                             std1 = sim$std1,
                             std2 = sim$std2)
Sys.time() - t0
setwd(old_wd)
Sys.unsetenv("R_PROFILE_USER")
RNGkind(sample.kind = "default")

##########################################
#########  checks against the paper and outputs
##########################################

## claims reported by the end of 2005 (AY + RepDel <= 2005) are the data at
## time I; the claim count does not depend on sample.kind, the others do
setDT(claims)
reported <- claims$AY + claims$RepDel <= last_ay
counts <- c("claims (paper 5,003,204)" = nrow(claims),
            "reported by 2005 (paper 4,970,856)" = sum(reported),
            "reported after 2005 (paper 32,348)" = sum(!reported),
            "LoB 1, AY 1994, Pay00 in 1'000 (paper Table 4: 70,866)" =
              claims[LoB == "1" & AY == 1994, sum(Pay00)] / 1000)
round(counts)

## 32 columns: ClNr, LoB, cc, AY, AQ, age, inj_part, RepDel, Pay00..Pay11,
## Open00..Open11
dir.create(out_dir, showWarnings = FALSE)
fwrite(claims, file.path(out_dir, "claims.csv"))
fwrite(data.frame(quantity = names(counts), value = unname(counts)),
       file.path(out_dir, "summary.csv"))
