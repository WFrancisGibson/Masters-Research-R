##########################################
#########  NN chain ladder on the SynthETIC portfolio: cells, network
#########  inputs, homogeneous model and zero claims features
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Sections 2, 3.3 and 4.2
#########  data: SynthETIC, Avanzi, Taylor, Wang & Wong (2021)
##########################################

## what the runs of "NN chain ladder SynthETIC fit.R" share, computed once
## per data set and coding of Age of Claimant (no Keras needed): the cells
## and the zero claims rules of "NN chain ladder fit.R" on the claims of
## analysis/00_claim-simulation/SynthETIC claims simulation.R. Run it for
## both codings before the fit sessions of the data set start, one session
## at a time: the cells, the homogeneous model and the zero claims features
## are the same files under both codings, written again by either (with
## save_run(), R/runs.R: a file is replaced whole, a session that starts
## meanwhile reads the one before, never half a file)
source(here::here("analysis", "00_setup.R"))
stopifnot(cfg$data$generator == "synthetic")

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # tables in millions
features <- c("Legal Representation", "Injury Severity", "Age of Claimant",
              "Vehicle type", "Business use")
## Age of Claimant as four dummies or as an ordinal score
## (R_CONFIG_ACTIVE=age_numeric); the network inputs and the fits of the two
## codings are saved apart (tag)
age <- cfg$nncl$synthetic$age
tag <- cfg$nncl$synthetic$tag

##########################################
#########  cells (i, x) and cumulative payments C_{i,j}(x)
##########################################

## claims and payments of the annual 20 x 20 portfolio; accident year
## i = 1..I, development year j = 0..J (the triangles' DY 1..20)
claims <- fread(file.path(paths$raw, cfg$data$dir, "claims.csv"),
                select = c("claim_no", "occurrence_period", "occurrence_time",
                           "notidel", features))
trans <- fread(file.path(paths$raw, cfg$data$dir, "transactions.csv"),
               select = c("claim_no", "occurrence_period", "payment_period",
                          "payment_inflated"))
claims$i <- claims$occurrence_period
# known at the end of year I
claims$reported <- claims$occurrence_time + claims$notidel <= n_ay

## cells: all claims of accident year i with feature x (Section 2), ordered
## by i and the features (the row order of the Keras split)
cells <- claims[, .(n_claims = .N, n_reported = sum(reported)),
                keyby = c("i", features)]
claims$cell <- cells[claims, on = c("i", features), which = TRUE]
trans$cell <- claims$cell[match(trans$claim_no, claims$claim_no)]
trans$j <- trans$payment_period - trans$occurrence_period

## C_{i,j}(x): the upper triangle i + j <= I is the data, the lower triangle
## the truth; the payments after development year J are in no triangle
## (reported apart, as in the Mack and bCCNN scripts)
paid <- trans[j < n_ay, .(paid = sum(payment_inflated)), by = .(cell, j)]
cum <- matrix(0,
              nrow(cells),
              n_ay,
              dimnames = list(NULL, paste0("cum_", 0:(n_ay - 1))))
cum[cbind(paid$cell, paid$j + 1)] <- paid$paid
for (j in 2:n_ay) cum[, j] <- cum[, j - 1] + cum[, j]
cells <- cbind(cells, cum)
cells$c_diag <- cum[cbind(seq_len(nrow(cum)), n_ay - cells$i + 1)]  # C_{i,I-i}
observed <- outer(cells$i, 0:(n_ay - 1), "+") <= n_ay
save_run(cells, file.path(paths$interim, "nncl_synthetic_cells.rds"))

## the cells add up to the triangle of the Mack, ODP GLM and bCCNN scripts
stopifnot(isTRUE(all.equal(unname(rowsum(cum, cells$i)),
                           unname(t(apply(claims_triangle(trans, n_ay),
                                          1,
                                          cumsum))))))

## SynthETIC pays no recoveries: the zero claims features (<= 0) are the
## cells without a payment up to the diagonal
c("cells" = nrow(cells),
  "feature values x" = uniqueN(cells[, features, with = FALSE]),
  "observed cells with C < 0" = sum(cum < 0 & observed),
  "diagonal cells with C = 0" = sum(cells$c_diag == 0),
  "claims of these cells" = sum(cells$n_claims[cells$c_diag == 0]),
  "payments after development year J" =
    round(sum(trans$payment_inflated[trans$j >= n_ay]) / units))
round(c("claims not reported at the end of year I (%)" =
          100 * mean(!claims$reported)), 1)
rm(claims, trans, paid)

##########################################
#########  feature pre-processing (Section 3.3)
##########################################

## (i) dummy coding of the covariates, reference label the one with the most
## reported claims; (ii) age "dummy": none of them is continuous, no
## MinMaxScaler; age "numeric": Age of Claimant is an ordinal score in place
## of its four dummies, the midpoint of its band scaled to [-1, 1] by the
## MinMaxScaler (3.8) (used as for a continuous feature, but the input still
## takes five values: the simulation has no age within a band)
x_cells <- NULL
for (v in features) {
  if (v == "Age of Claimant" && age == "numeric") {
    x_v <- unlist(cfg$nncl$synthetic$age_midpoints)[cells[[v]]]
    x_v <- 2 * (x_v - min(x_v)) / (max(x_v) - min(x_v)) - 1
    cat(v, ": numeric, scaled midpoints ",
        paste(round(sort(unique(x_v)), 3), collapse = " "), "\n", sep = "")
    x_cells <- cbind(x_cells, unname(x_v))
  } else {
    n_lab <- cells[, .(n = sum(n_reported)), by = v]
    ref <- n_lab[[v]][which.max(n_lab$n)]
    cat(v, ": ", nrow(n_lab), " labels, reference label ", ref, "\n", sep = "")
    lab <- relevel(factor(cells[[v]]), ref = as.character(ref))
    x_cells <- cbind(x_cells, model.matrix(~lab)[, -1])
  }
}
d <- ncol(x_cells)      # dummy: 14 = 1, 5, 4, 3 and 1 of the five covariates;
d                       # numeric: 11 = 1, 5, 1, 3 and 1

## the networks only see the feature value x of a cell: x holds the inputs
## of the feature values of the portfolio (in the order of the cells, the
## same under both codings) and x_id the feature value of every cell, so
## that a run keeps the CL factors of the feature values, f(x), and the
## factor of a cell is element x_id of them
values <- unique(cells[, features, with = FALSE])
x_id <- values[cells, on = features, which = TRUE]
x <- x_cells[match(seq_len(nrow(values)), x_id), ]
stopifnot(all(x[x_id, ] == x_cells))

## learning cells of development period j: i <= I - j, C_{i,j-1}(x) > 0;
## part-1 diagonal cells: accident years i > 1 with C_{i,I-i}(x) > 0
learn_rows <- lapply(1:(n_ay - 1), function(j) {
  which(cells$i <= n_ay - j & cum[, j] > 0)
})
diag_rows <- which(cells$i > 1 & cells$c_diag > 0)
save_run(list(x = x,
              x_id = x_id,
              learn_rows = learn_rows,
              diag_rows = diag_rows),
         file.path(paths$interim, paste0(tag, "_inputs.rds")))

##########################################
#########  homogeneous model (Table 5, first block)
##########################################

## Mack's CL factor minimises (3.1) without features:
## f_{j-1} = sum C_{i,j}(x) / sum C_{i,j-1}(x) over the learning cells;
## steps: gradient descent steps per epoch on Keras's training rows (the
## paper's j = 1: 184). With at most 480 feature values a year the batch of
## Listing 2 holds all rows: one step per epoch, 100 steps per network
vali_split <- cfg$nncl$training$validation_split
homogeneous <- data.frame(j = 1:(n_ay - 1), n_cells = lengths(learn_rows))
homogeneous$steps <- ceiling(floor(homogeneous$n_cells * (1 - vali_split)) /
                               cfg$nncl$training$batch_size)
homogeneous$f_hom <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  sum(cum[r, j + 1]) / sum(cum[r, j])
})
homogeneous$loss <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  sum((cum[r, j + 1] - homogeneous$f_hom[j] * cum[r, j])^2 / cum[r, j])
})
save_run(homogeneous,
         file.path(paths$processed, "nncl_synthetic_homogeneous.rds"))
cbind(homogeneous[, 1:3],
      f_hom = round(homogeneous$f_hom, 4),
      loss_millions = round(homogeneous$loss / units, 1))

## Section 4: feature values x with a positive C_{i,0}(x), i <= I - 1, and
## the accident years of Keras's validation rows (j = 1)
r <- learn_rows[[1]]
c("feature values x with C_{i,0}(x) > 0" = uniqueN(x_id[r]),
  "learning cells j = 1" = length(r))
range(cells$i[r[-seq_len(floor(length(r) * (1 - vali_split)))]])

##########################################
#########  zero claims features (Section 4.2)
##########################################

## the rules of "NN chain ladder fit.R" for the one portfolio (a single
## LoB): per accident year i = 2..I the CL factors g^(i) of the zero claims
## features and their ultimate C_{i,I-i} prod g^(i); only the observed upper
## triangle enters (NA elsewhere)
zero <- nncl_zero_claims(ifelse(observed, cum, NA),
                         cells$i,
                         rep(1, nrow(cells)))
stopifnot(all(is.finite(zero$ult_zero)))
save_run(zero, file.path(paths$processed, "nncl_synthetic_zero_claims.rds"))

## a positive numerator over a zero denominator: the ratio pooled over the
## accident years (own rule, not in the paper); behind a first factor
## g_{I-i} = 0 (g_first) it does not count: ultimate 0
pooled <- zero$factors[zero$factors$pooled, ]
pooled$g_first <- zero$factors$g[match(paste(pooled$i, n_ay - pooled$i),
                                       paste(zero$factors$i, zero$factors$j))]
pooled

## zero claims reserve (part 2 of (5.1); no recoveries: the ultimates), in
## total and of the accident years with a pooled factor
round(zero$ult_zero / units, 1)
c("zero claims factors" = nrow(zero$factors),
  "pooled" = nrow(pooled),
  "pooled, g_first > 0" = sum(pooled$g_first > 0))
round(c("zero claims reserve" = sum(zero$ult_zero),
        "of the accident years with a pooled factor" =
          sum(zero$ult_zero[1, unique(pooled$i)])) / units, 1)
