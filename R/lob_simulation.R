##########################################
#########  Six lines of business from the individual claims simulation machine
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Appendix A,
#########  Listings 1 and 3; machine V1: Gabrielli & Wuthrich (2018)
##########################################

## the paper's data come from R < 3.6, whose sample() used sample.kind
## "Rounding": set it in this session and, through the profile R_PROFILE_USER
## points to, in the PSOCK workers of the machine (fresh Rscript sessions)
machine_rng_rounding <- function() {
  RNGkind(sample.kind = "Rounding")
  profile <- tempfile(fileext = ".R")
  writeLines('RNGkind(sample.kind = "Rounding")', profile)
  Sys.setenv(R_PROFILE_USER = profile)
}

## Listing 1: the individual claims of LoBs 1-6, simulated with one seed;
## needs Functions.V1.R sourced and the machine's folder as working directory;
## sim: cfg$lob$simulation. The machine has four LoBs: 1 and 2 share a feature
## distribution, as do 3 and 4, and each LoB has its own claims development
lob_simulate <- function(sim, seed = sim$seed1) {
  ## lines 6-10: features of the machine's LoBs 1-4
  features <- Feature.Generation(V = sim$large$expected_claims,
                                 LoB.dist = sim$large$lob_dist,
                                 inflation = sim$large$growth,
                                 seed1 = seed)
  ## lines 12-15: LoBs 1 and 4 are the machine's LoBs 1 and 4; one block
  ## (npb = number of claims): every block would reuse the same seeds
  f1 <- features[which(features$LoB %in% c("1", "4")), ]
  out1 <- Simulation.Machine(features = f1,
                             npb = nrow(f1),
                             seed1 = seed,
                             std1 = sim$std1,
                             std2 = sim$std2)
  out1$LoB <- c(1, 4)[as.numeric(out1$LoB)]
  ## lines 17-21: LoBs 2 and 5 have the features of the machine's LoBs 2 and
  ## 3 and the claims development of its LoBs 1 and 4 (line 19; as.numeric of
  ## the factor with levels 1-4 gives 2 and 3)
  f2 <- features[which(features$LoB %in% c("2", "3")), ]
  f2$LoB <- as.factor(c(1, 1, 4)[as.numeric(f2$LoB)])
  out2 <- Simulation.Machine(features = f2,
                             npb = nrow(f2),
                             seed1 = seed,
                             std1 = sim$std1,
                             std2 = sim$std2)
  out2$LoB <- c(2, 5)[as.numeric(out2$LoB)]
  ## lines 24-32: LoBs 3 and 6 are the machine's LoBs 1 and 4 of a smaller
  ## portfolio that grows faster (the factor has the levels 1 and 4 only)
  f3 <- Feature.Generation(V = sim$small$expected_claims,
                           LoB.dist = sim$small$lob_dist,
                           inflation = sim$small$growth,
                           seed1 = seed)
  out3 <- Simulation.Machine(features = f3,
                             npb = nrow(f3),
                             seed1 = seed,
                             std1 = sim$std1,
                             std2 = sim$std2)
  out3$LoB <- c(3, 6)[as.numeric(out3$LoB)]
  ## lines 22 and 33; the claim numbers ClNr start again at 1 in out3, so a
  ## claim is identified by LoB and ClNr
  rbind(out1, out2, out3)
}

## Listing 3: the payments pay (claims x development years) added up by LoB
## and accident year; a list by LoB of the AY x DY squares (upper and lower
## triangle)
lob_triangles <- function(pay, lob, ay) {
  lapply(split(seq_along(lob), lob), function(rows) {
    tri <- rowsum(pay[rows, , drop = FALSE], ay[rows])
    dimnames(tri) <- list(AY = rownames(tri), DY = seq_len(ncol(tri)) - 1)
    tri
  })
}

## true reserves (the payments of the lower triangle) and chain-ladder
## reserves of the upper triangle, by LoB; tri: the list of lob_triangles
lob_reserves <- function(tri) {
  t(sapply(tri, function(y) {
    c(true = sum(lower_triangle(y), na.rm = TRUE),
      cl = sum(cl_reserves(upper_triangle(y))))
  }))
}

## simulated values next to those of a paper and their difference; simulated
## and paper: matrices quantity x LoB; digits: the decimals of the paper, one
## number or one per quantity
paper_check <- function(simulated, paper, digits = 0) {
  simulated <- round(simulated, digits)
  out <- rbind(simulated, paper, simulated - paper)
  colnames(out) <- colnames(paper)
  out <- data.frame(quantity = rep(rownames(paper), times = 3),
                    source = rep(c("simulated", "paper", "difference"),
                                 each = nrow(paper)),
                    out,
                    row.names = NULL,
                    check.names = FALSE)
  out[order(rep(seq_len(nrow(paper)), times = 3)), ]
}
