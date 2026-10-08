##########################################
#########  Fingerprint of the simulated claims of a data set
#########  own design, not in the papers: the final run simulates the claims
#########  again on another computer and stops if they are not the laptop's
##########################################

## counts and sums of the simulated claims of the data set of this session
## (environment variable DATASET), one row each: table, key, type and value
## (15 significant digits). Without fingerprints/<dataset>.csv (tracked in
## git) the script writes it; with it, the script compares: the same keys,
## the counts (type count) exactly, the sums (type value) to 1e-9, and it
## stops at a difference. The md5 sums of the files (type info) are not
## compared: they change with the line ends and the digits of fwrite.
## With the argument check (the final run) it only compares:
##   Rscript "<this script>" check
source(here::here("analysis", "00_setup.R"))

data_dir <- file.path(paths$raw, cfg$data$dir)
fp_file <- here::here("analysis", "00_claim-simulation", "fingerprints",
                      paste0(cfg$dataset, ".csv"))
n <- cfg$data$n_dev

## check: on the computer of the final run a missing fingerprint is a
## failure (the claims could not be compared with the laptop's), not a file
## to write
check <- "check" %in% commandArgs(trailingOnly = TRUE)
stopifnot("no fingerprint file of this data set to check against" =
            !check || file.exists(fp_file))

##########################################
#########  SynthETIC data sets: claims.csv and transactions.csv
##########################################

if (cfg$data$generator == "synthetic") {
  files <- c("claims.csv", "transactions.csv")
  features <- c("Legal Representation", "Injury Severity", "Age of Claimant",
                "Vehicle type", "Business use")
  claims <- fread(file.path(data_dir, "claims.csv"))
  trans <- fread(file.path(data_dir, "transactions.csv"),
                 select = c("claim_no", "occurrence_period", "payment_period",
                            "payment_inflated"),
                 data.table = FALSE)
  ## the n x n square of the incremental payments, the payments after
  ## development period n and the observed triangle of the training half of
  ## Paper C's claims split (triangle_sets, R/triangles.R)
  sets <- triangle_sets(trans, n)
  cell <- paste("AY", row(sets$full), "DY", col(sets$full))
  obs <- which(!is.na(sets$train))
  ## by accident period; reported: notified by the valuation date n
  by_ay <- claims[, .(claims = .N,
                      reported = sum(occurrence_time + notidel <= n),
                      claim_size = sum(claim_size),
                      notidel = sum(notidel),
                      setldel = sum(setldel)),
                  keyby = .(AY = occurrence_period)]
  by_ay$AY <- paste("AY", by_ay$AY)
  ## by level of the five features: claims and all their payments
  pay <- rowsum(trans$payment_inflated, trans$claim_no)
  claims$paid <- pay[match(claims$claim_no, as.integer(rownames(pay))), 1]
  by_level <- rbindlist(lapply(features, function(v) {
    claims[, .(claims = .N, paid = sum(paid)),
           keyby = .(level = paste(v, "=", get(v)))]
  }))
  ## the checksums change if the claims or the payments change places
  fp <- rbind(
    fingerprint_rows("portfolio",
                     c("claims", "payments"),
                     c(nrow(claims), nrow(trans)),
                     "count"),
    fingerprint_rows("checksum",
                     c("sum of claim_no x claim_size",
                       "sum of row number x payment_inflated"),
                     c(sum(claims$claim_no * claims$claim_size),
                       sum(seq_len(nrow(trans)) * trans$payment_inflated))),
    fingerprint_rows("incremental payments", cell, as.vector(sets$full)),
    fingerprint_rows("payments after the last development period",
                     paste("AY", 1:n),
                     sets$tail),
    fingerprint_rows("incremental payments of the training half",
                     cell[obs],
                     sets$train[obs]),
    fingerprint_rows("claims by accident period",
                     by_ay$AY,
                     by_ay$claims,
                     "count"),
    fingerprint_rows("claims reported by the valuation date",
                     by_ay$AY,
                     by_ay$reported,
                     "count"),
    fingerprint_rows("claim_size by accident period",
                     by_ay$AY,
                     by_ay$claim_size),
    fingerprint_rows("notidel by accident period", by_ay$AY, by_ay$notidel),
    fingerprint_rows("setldel by accident period", by_ay$AY, by_ay$setldel),
    fingerprint_rows("claims by feature level",
                     by_level$level,
                     by_level$claims,
                     "count"),
    fingerprint_rows("payments by feature level",
                     by_level$level,
                     by_level$paid)
  )
}

##########################################
#########  machine data sets (lob6, machine4): claims.csv
##########################################

if (cfg$data$generator == "machine") {
  files <- "claims.csv"
  pay_cols <- sprintf("Pay%02d", 0:(n - 1))
  claims <- fread(file.path(data_dir, "claims.csv"))
  ## the training half of Paper C Listing 2: the column vali of "lines of
  ## business simulation.R", for machine4 the split itself
  if (is.null(claims$vali)) claims$vali <- lob_split(claims$LoB, claims$AY)
  pay <- as.matrix(claims[, pay_cols, with = FALSE])
  storage.mode(pay) <- "double"       # fread reads whole numbers: no overflow
  claims$paid <- rowSums(pay)
  train <- claims$vali == 1
  ## Paper C Listing 3: the AY x DY squares of the payments by LoB, of all
  ## claims and of the training half
  tri <- lob_triangles(pay, claims$LoB, claims$AY)
  tri_train <- lob_triangles(pay[train, ],
                             claims$LoB[train],
                             claims$AY[train])
  cell <- paste("LoB", rep(names(tri), each = n^2),
                "AY", rep(rownames(tri[[1]]), times = n * length(tri)),
                "DY", rep(rep(colnames(tri[[1]]), each = n),
                          times = length(tri)))
  by_lob <- claims[, .N, keyby = LoB]
  by_delay <- claims[, .N, keyby = .(LoB, AY, RepDel)]
  by_cc <- claims[, .(paid = sum(paid)), keyby = .(LoB, cc)]
  fp <- rbind(
    fingerprint_rows("claims by LoB",
                     paste("LoB", by_lob$LoB),
                     by_lob$N,
                     "count"),
    fingerprint_rows("checksum",
                     "sum of ClNr x payments",
                     sum(claims$ClNr * claims$paid)),
    fingerprint_rows("incremental payments", cell, unlist(tri)),
    fingerprint_rows("incremental payments of the training half",
                     cell,
                     unlist(tri_train)),
    fingerprint_rows("claims by LoB accident year and reporting delay",
                     paste("LoB", by_delay$LoB, "AY", by_delay$AY,
                           "RepDel", by_delay$RepDel),
                     by_delay$N,
                     "count"),
    fingerprint_rows("payments by LoB and claims code",
                     paste("LoB", by_cc$LoB, "cc", by_cc$cc),
                     by_cc$paid)
  )
}

##########################################
#########  write or compare
##########################################

fp <- rbind(fp,
            fingerprint_rows("md5 of the file",
                             files,
                             unname(tools::md5sum(file.path(data_dir, files))),
                             "info"))
if (file.exists(fp_file)) {
  old <- fread(fp_file, colClasses = "character", data.table = FALSE)
  differences <- fingerprint_diff(fp, old)
  ## the first rows that differ, then stop
  if (nrow(differences) > 0) print(head(differences, 20))
  stopifnot(nrow(differences) == 0)
  cat("fingerprint of ", cfg$dataset, ": identical (",
      sum(fp$type != "info"), " rows compared)\n", sep = "")
} else {
  dir.create(dirname(fp_file), showWarnings = FALSE)
  fwrite(fp, fp_file)
  cat("fingerprint of ", cfg$dataset, ": written (", nrow(fp), " rows)\n",
      sep = "")
}
