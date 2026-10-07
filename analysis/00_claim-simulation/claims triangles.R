##########################################
#########  Claims triangles of the data set
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Listings 2 and 3
##########################################

## the triangles the Mack, ODP GLM and bCCNN scripts read, built once per
## data set from its simulated claims: triangles.rds in paths$interim, a list
## of n x n matrices of incremental payments in the unit of the simulation
## (rows accident periods, columns development periods 1..n):
## full (the square), upper (observed at the valuation date), test (the true
## outstanding payments), train and vali (upper triangles of the two halves
## of Paper C's 50/50 claims split) and tail (the payments after development
## period n by accident period, in no triangle). The machine data sets have
## one such file per LoB (units lob1, lob2, ...) and one of all LoBs (unit
## lob_all: arrays n x n x LoBs)
source(here::here("analysis", "00_setup.R"))

n <- cfg$data$n_dev

##########################################
#########  SynthETIC data sets: one triangle
##########################################

if (cfg$data$generator == "synthetic") {
  trans <- fread(file.path(paths$raw, cfg$data$dir, "transactions.csv"),
                 select = c("claim_no", "occurrence_period", "payment_period",
                            "payment_inflated"), data.table = FALSE)
  sets <- triangle_sets(trans, n)
  saveRDS(sets, file.path(paths$interim, "triangles.rds"))
  ## observed, outstanding and late payments in units of cfg$data$scale
  round(c("observed" = sum(sets$upper, na.rm = TRUE),
          "true outstanding" = sum(sets$test, na.rm = TRUE),
          "after the last development period" = sum(sets$tail),
          "training half" = sum(sets$train, na.rm = TRUE),
          "validation half" = sum(sets$vali, na.rm = TRUE)) / cfg$data$scale,
        1)
}

##########################################
#########  machine data sets: one triangle per LoB, and all LoBs
##########################################

if (cfg$data$generator == "machine") {
  ## the units are written from the data set: run it with UNIT empty
  stopifnot(cfg$unit == "")
  data_dir <- file.path(paths$raw, cfg$data$dir)
  pay_cols <- sprintf("Pay%02d", 0:(n - 1))
  claims <- fread(file.path(data_dir, "claims.csv"))
  ## Paper C Listing 2: the training half (vali = 1) and the validation half
  ## (vali = 2), the column vali of "lines of business simulation.R"; machine4
  ## has no such column: the split itself (lob_split, R/lob_simulation.R)
  if (is.null(claims$vali)) claims$vali <- lob_split(claims$LoB, claims$AY)
  pay <- as.matrix(claims[, pay_cols, with = FALSE])
  storage.mode(pay) <- "double"       # fread reads whole numbers: no overflow
  train <- claims$vali == 1
  ## Paper C Listing 3: the AY x DY squares by LoB of all claims and of the
  ## two halves; the machine pays nothing after development year n - 1 (no
  ## tail)
  squares <- list(full = lob_triangles(pay, claims$LoB, claims$AY),
                  train = lob_triangles(pay[train, ],
                                        claims$LoB[train],
                                        claims$AY[train]),
                  vali = lob_triangles(pay[!train, ],
                                       claims$LoB[!train],
                                       claims$AY[!train]))
  lobs <- names(squares$full)
  sets <- lapply(lobs, function(l) {
    s <- lapply(squares, function(set) {
      matrix(set[[l]], n, n, dimnames = list(origin = 1:n, dev = 1:n))
    })
    list(full = s$full,
         upper = upper_triangle(s$full),
         test = lower_triangle(s$full),
         train = upper_triangle(s$train),
         vali = upper_triangle(s$vali),
         tail = rep(0, n))
  })
  names(sets) <- paste0("lob", lobs)
  ## all LoBs: the same elements with the LoB as last dimension
  elements <- c("full", "upper", "test", "train", "vali")
  lob_all <- lapply(elements, function(e) {
    array(sapply(sets, function(s) s[[e]]),
          c(n, n, length(lobs)),
          dimnames = list(origin = 1:n, dev = 1:n, lob = lobs))
  })
  names(lob_all) <- elements
  lob_all$tail <- matrix(0,
                         n,
                         length(lobs),
                         dimnames = list(origin = 1:n, lob = lobs))
  ## triangles.csv of "lines of business simulation.R" (lob6) holds the same
  ## squares in units of cfg$data$scale, rows by LoB, DY and AY
  if (file.exists(file.path(data_dir, "triangles.csv"))) {
    csv <- fread(file.path(data_dir, "triangles.csv"), data.table = FALSE)
    obs <- !is.na(lob_all$upper)
    scale <- cfg$data$scale
    stopifnot(
      isTRUE(all.equal(as.vector(lob_all$full), csv$paid * scale)),
      isTRUE(all.equal(lob_all$train[obs], csv$paid_train[obs] * scale)),
      isTRUE(all.equal(lob_all$vali[obs], csv$paid_vali[obs] * scale))
    )
  }
  for (u in c(names(sets), "lob_all")) {
    dir.create(file.path(paths$interim, u), showWarnings = FALSE)
  }
  for (u in names(sets)) {
    saveRDS(sets[[u]], file.path(paths$interim, u, "triangles.rds"))
  }
  saveRDS(lob_all, file.path(paths$interim, "lob_all", "triangles.rds"))
  ## observed and outstanding payments and the smallest observed cell of
  ## the triangle and of its halves (a negative cell stops the quasi-Poisson
  ## fits), in units of cfg$data$scale
  round(sapply(sets, function(s) {
    c("observed" = sum(s$upper, na.rm = TRUE),
      "true outstanding" = sum(s$test, na.rm = TRUE),
      "training half" = sum(s$train, na.rm = TRUE),
      "validation half" = sum(s$vali, na.rm = TRUE),
      "smallest cell" = min(s$upper, na.rm = TRUE),
      "smallest cell, training half" = min(s$train, na.rm = TRUE),
      "smallest cell, validation half" = min(s$vali, na.rm = TRUE))
  }) / cfg$data$scale, 3)
}
