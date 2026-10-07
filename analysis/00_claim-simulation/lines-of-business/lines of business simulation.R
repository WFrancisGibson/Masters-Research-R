##########################################
#########  Six lines of business: individual claims simulation
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), SAJ 2020(1):1-29,
#########  Appendix A, Listings 1-3; the simulated data of Harkonen (2021),
#########  Master Thesis 2021:4, Stockholm University, Section 3.1
##########################################

## the data set of this script, all its LoBs: no unit, whatever the session
## inherits (the paths of a unit are <dataset>/<unit>)
Sys.setenv(DATASET = "lob6", UNIT = "")
source(here::here("analysis", "00_setup.R"))
library(MASS)          # mvrnorm in Feature.Generation
library(doParallel)    # foreach and parallel in Simulation.Machine

sim <- cfg$lob$simulation
## the original machine V1 of Gabrielli & Wuthrich (2018), unmodified
machine_dir <- here::here("analysis", "00_claim-simulation",
                          "Simulation.Machine.V1")
out_dir <- file.path(paths$raw, cfg$data$dir)
n_ay <- cfg$data$n_dev                         # I = 12, development years 0..11
ay_lab <- cfg$data$first_ay + 1:n_ay - 1       # 1994..2005
last_ay <- max(ay_lab)                         # 2005, the valuation date I
units <- cfg$data$scale                        # payments in 1'000
pay_cols <- sprintf("Pay%02d", 0:(n_ay - 1))

##########################################
#########  random number generator
##########################################

## Paper C is of 2018 (R < 3.6): sample.kind "Rounding" in this session and
## in the machine's workers (machine_rng_rounding, R/lob_simulation.R)
if (sim$rng_rounding) machine_rng_rounding()
RNGkind()
## a worker must sample as this session does
cl <- makeCluster(1)
worker_kind <- clusterEvalQ(cl, RNGkind()[3])[[1]]
stopCluster(cl)
stopifnot(worker_kind == RNGkind()[3])

##########################################
#########  simulate the claims (Listing 1)
##########################################

## the machine reads its parameter files from the working directory
## ("./Parameters/...") and the workers inherit it; after an error restart R
old_wd <- setwd(machine_dir)
source("Functions.V1.R")
## the machine starts detectCores() - 1 workers and gives its one block to
## one of them: this function, found before the one of parallel, makes it
## start sim$workers
detectCores <- function() sim$workers + 1  # nolint: object_name_linter.
t0 <- Sys.time()
claims <- lob_simulate(sim)
Sys.time() - t0
setwd(old_wd)
Sys.unsetenv("R_PROFILE_USER")
RNGkind(sample.kind = "default")

##########################################
#########  training and validation sets (Listing 2)
##########################################

## the claims, ordered by LoB and accident year, go alternately to the
## training set (vali = 1) and the validation set (vali = 2): both receive
## equally many claims per LoB and accident year. The paper drops the column
## again; here it stays in claims.csv
claims <- claims[order(claims$LoB, claims$AY), ]
claims$vali <- rep(c(1, 2), length.out = nrow(claims))

## 33 columns: ClNr, LoB (1-6), cc, AY, AQ, age, inj_part, RepDel,
## Pay00..Pay11, Open00..Open11, vali; written first, the rest of the script
## is quick to repeat from this file
dir.create(out_dir, showWarnings = FALSE)
fwrite(claims, file.path(out_dir, "claims.csv"))

##########################################
#########  claims reserving triangles (Listing 3)
##########################################

## payments by LoB, accident year AY and development year DY; the cells
## AY + DY <= 2005 are the upper triangles D_I known at the end of 2005, the
## other cells the true outstanding payments; the same for the two sets
pay <- as.matrix(claims[, pay_cols])
train <- claims$vali == 1
tri <- lob_triangles(pay, claims$LoB, claims$AY)
tri_train <- lob_triangles(pay[train, ],
                           claims$LoB[train],
                           claims$AY[train])
tri_vali <- lob_triangles(pay[!train, ],
                          claims$LoB[!train],
                          claims$AY[!train])
## every LoB has claims of every accident year in both sets (the table below
## fills the squares column by column), and the two sets add up
stopifnot(sapply(c(tri_train, tri_vali), nrow) == n_ay,
          isTRUE(all.equal(unlist(tri_train) + unlist(tri_vali),
                           unlist(tri))))
## smallest observed cell of the upper triangles by LoB, in 1'000 (own
## check, not in the paper): recoveries can make a cell negative, and the
## quasi-Poisson fits of the ccODP and the bCCNN stop at a negative cell
min_cell <- sapply(list(all = tri, training = tri_train, validation = tri_vali),
                   function(set) {
                     sapply(set, function(y) {
                       min(upper_triangle(y), na.rm = TRUE)
                     })
                   })
round(min_cell / units, 3)
## one row per LoB, AY and DY, paid in 1'000 (line 5)
dat0 <- data.frame(LoB = rep(as.integer(names(tri)), each = n_ay^2),
                   AY = rep(ay_lab, times = n_ay * length(tri)),
                   DY = rep(rep(0:(n_ay - 1), each = n_ay),
                            times = length(tri)),
                   paid = unlist(tri, use.names = FALSE) / units,
                   paid_train = unlist(tri_train, use.names = FALSE) / units,
                   paid_vali = unlist(tri_vali, use.names = FALSE) / units)
fwrite(dat0, file.path(out_dir, "triangles.csv"))

##########################################
#########  claim counts and payments by reporting and payment delay
#########  Harkonen (2021), Sections 2.1 and 3.1, as Lindholm et al. (2020)
##########################################

## N: number of claims by LoB, accident year i and reporting delay j (RepDel);
## X: their payments (in 1'000) by payment delay k = DY - j after reporting;
## both by set (vali): the full data is the sum over the two sets. A cell
## without claims has no row. The payments stay as simulated: Harkonen sets
## the negative X of a cell to zero for the Poisson loss
setDT(claims)
by_delay <- claims[,
                   c(list(N = .N), lapply(.SD, sum)),
                   keyby = .(LoB, AY, RepDel, vali),
                   .SDcols = pay_cols]
counts <- by_delay[, c("LoB", "AY", "RepDel", "vali", "N"), with = FALSE]
payments <- melt(by_delay,
                 id.vars = c("LoB", "AY", "RepDel", "vali"),
                 measure.vars = pay_cols,
                 variable.name = "DY",
                 value.name = "X")
payments$PayDel <- as.numeric(substr(payments$DY, 4, 5)) - payments$RepDel
payments$X <- payments$X / units
## the machine pays nothing before the reporting year
stopifnot(payments$X[payments$PayDel < 0] == 0)
payments <- payments[PayDel >= 0, .(LoB, AY, RepDel, PayDel, vali, X)]
setkey(payments, LoB, AY, RepDel, PayDel, vali)
fwrite(counts, file.path(out_dir, "counts.csv"))
fwrite(payments, file.path(out_dir, "payments.csv"))

##########################################
#########  checks against the papers
##########################################

## claims per LoB (Paper C Table 1, Harkonen Table 1); true reserves and
## chain-ladder reserves at the end of 2005 in 1'000 (Paper C Table 2). The
## claim counts depend on the seed only, the reserves on sample.kind as well
paper <- rbind(claims = c(250040, 250197, 99969, 249683, 249298, 99701),
               true_reserves = c(39689, 37037, 16878, 71630, 72548, 31117),
               cl_reserves = c(38569, 35460, 15692, 67574, 70166, 29409))
colnames(paper) <- paste("LoB", names(tri))
res <- lob_reserves(tri) / units
simulated <- rbind(claims = as.numeric(table(claims$LoB)),
                   true_reserves = res[, "true"],
                   cl_reserves = res[, "cl"])
check <- paper_check(simulated, paper)
check
## claims reported by the end of 2005 (AY + RepDel <= 2005) and after
table(LoB = claims$LoB, reported = claims$AY + claims$RepDel <= last_ay)

fwrite(check, file.path(out_dir, "summary.csv"))
