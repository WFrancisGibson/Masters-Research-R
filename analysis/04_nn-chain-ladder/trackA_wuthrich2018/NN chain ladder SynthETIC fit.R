##########################################
#########  NN chain ladder on the SynthETIC portfolio: CL factor networks
#########  and zero claims features
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Sections 3-4, Appendix 2 (Listing 2)
#########  data: SynthETIC, Avanzi, Taylor, Wang & Wong (2021)
##########################################

## the networks, runs and zero claims rules of "NN chain ladder fit.R" on the
## claims of analysis/00_claim-simulation/short_tailed_claims.R
source(here::here("analysis", "00_setup.R"))
library(keras3)

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # tables in millions
features <- c("Legal Representation", "Injury Severity", "Age of Claimant",
              "Vehicle type", "Business use")
## Age of Claimant as four dummies or as an ordinal score
## (R_CONFIG_ACTIVE=age_numeric); the fits of the two codings are saved apart
## (tag)
age <- cfg$nncl$synthetic$age
tag <- cfg$nncl$synthetic$tag

## hyper-parameters of Listing 2 (Appendix 2) and of the sensitivity runs
## S1-S3 at q_main, each adding one change; S4 (balance correction) below
param <- list(activation = cfg$nncl$model$activation,
              optimizer = "rmsprop",
              learning_rate = cfg$nncl$sensitivity$learning_rate,
              epochs = cfg$nncl$training$epochs,
              batch_size = cfg$nncl$training$batch_size,
              validation_split = cfg$nncl$training$validation_split,
              early_stop = FALSE,
              patience = cfg$nncl$sensitivity$patience,
              seed = cfg$seed)
param_s1 <- modifyList(param, list(optimizer = "adam"))
param_s2 <- modifyList(param_s1,
                       list(early_stop = TRUE,
                            epochs = cfg$nncl$sensitivity$max_epochs))
q_main <- cfg$nncl$model$q_main
runs <- list()
for (q in cfg$nncl$model$q) {
  runs[[paste0("paper_q", q)]] <- list(q = q, param = param, cl_start = FALSE)
}
runs$s1_adam <- list(q = q_main, param = param_s1, cl_start = FALSE)
runs$s2_early_stop <- list(q = q_main, param = param_s2, cl_start = FALSE)
runs$s3_cl_start <- list(q = q_main, param = param_s2, cl_start = TRUE)
runs <- runs[cfg$nncl$runs]

## hidden layers and optimisers (own design, not in the paper): every
## combination of hidden layers, optimiser and training; training "paper" is
## Listing 2's (100 epochs, random start), "cl_start" that of S3 (early
## stopping, output started in the homogeneous CL factor); every run is
## fitted with every seed (the spread over the seeds, nagging predictors)
grid_cfg <- cfg$nncl$synthetic
seeds <- cfg$seed + seq_len(grid_cfg$seeds) - 1
for (h in grid_cfg$hidden) {
  for (o in names(grid_cfg$optimizers)) {
    for (tr in grid_cfg$training) {
      for (s in seeds) {
        p <- modifyList(if (tr == "paper") param else param_s2,
                        list(optimizer = o,
                             learning_rate = grid_cfg$optimizers[[o]],
                             momentum = grid_cfg$momentum,
                             seed = s))
        run_name <- paste0("grid_", paste(h, collapse = "-"), "_", o, "_", tr,
                           "_s", s)
        runs[[run_name]] <- list(q = h, param = p, cl_start = tr == "cl_start")
      }
    }
  }
}

##########################################
#########  cells (i, x) and cumulative payments C_{i,j}(x)
##########################################

## claims and payments of the annual 20 x 20 portfolio; accident year
## i = 1..I, development year j = 0..J (the triangles' DY 1..20)
claims <- fread(file.path(paths$raw, cfg$data$annual_dir, "claims.csv"),
                select = c("claim_no", "occurrence_period", "occurrence_time",
                           "notidel", features))
trans <- fread(file.path(paths$raw, cfg$data$annual_dir, "transactions.csv"),
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
saveRDS(cells, file.path(paths$interim, "nncl_synthetic_cells.rds"))

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
x <- NULL
for (v in features) {
  if (v == "Age of Claimant" && age == "numeric") {
    x_v <- unlist(cfg$nncl$synthetic$age_midpoints)[cells[[v]]]
    x_v <- 2 * (x_v - min(x_v)) / (max(x_v) - min(x_v)) - 1
    cat(v, ": numeric, scaled midpoints ",
        paste(round(sort(unique(x_v)), 3), collapse = " "), "\n", sep = "")
    x <- cbind(x, unname(x_v))
  } else {
    n_lab <- cells[, .(n = sum(n_reported)), by = v]
    ref <- n_lab[[v]][which.max(n_lab$n)]
    cat(v, ": ", nrow(n_lab), " labels, reference label ", ref, "\n", sep = "")
    lab <- relevel(factor(cells[[v]]), ref = as.character(ref))
    x <- cbind(x, model.matrix(~lab)[, -1])
  }
}
d <- ncol(x)            # dummy: 14 = 1, 5, 4, 3 and 1 of the five covariates;
d                       # numeric: 11 = 1, 5, 1, 3 and 1

## learning cells of development period j: i <= I - j, C_{i,j-1}(x) > 0;
## part-1 diagonal cells: accident years i > 1 with C_{i,I-i}(x) > 0
learn_rows <- lapply(1:(n_ay - 1), function(j) {
  which(cells$i <= n_ay - j & cum[, j] > 0)
})
diag_rows <- which(cells$i > 1 & cells$c_diag > 0)
x_diag <- x[diag_rows, ]

##########################################
#########  homogeneous model (Table 5, first block)
##########################################

## Mack's CL factor minimises (3.1) without features:
## f_{j-1} = sum C_{i,j}(x) / sum C_{i,j-1}(x) over the learning cells;
## steps: gradient descent steps per epoch on Keras's training rows (the
## paper's j = 1: 184). With at most 480 feature values a year the batch of
## Listing 2 holds all rows: one step per epoch, 100 steps per network
homogeneous <- data.frame(j = 1:(n_ay - 1), n_cells = lengths(learn_rows))
homogeneous$steps <- ceiling(floor(homogeneous$n_cells *
                                     (1 - param$validation_split)) /
                               param$batch_size)
homogeneous$f_hom <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  sum(cum[r, j + 1]) / sum(cum[r, j])
})
homogeneous$loss <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  sum((cum[r, j + 1] - homogeneous$f_hom[j] * cum[r, j])^2 / cum[r, j])
})
saveRDS(homogeneous,
        file.path(paths$processed, "nncl_synthetic_homogeneous.rds"))
cbind(homogeneous[, 1:3],
      f_hom = round(homogeneous$f_hom, 4),
      loss_millions = round(homogeneous$loss / units, 1))

## Section 4: feature values x with a positive C_{i,0}(x), i <= I - 1, and
## the accident years of Keras's validation rows (j = 1)
r <- learn_rows[[1]]
c("feature values x with C_{i,0}(x) > 0" =
    uniqueN(cells[r, features, with = FALSE]),
  "learning cells j = 1" = length(r))
range(cells$i[r[-seq_len(floor(length(r) *
                                 (1 - param$validation_split)))]])

##########################################
#########  CL factor networks (Section 3, Listing 2)
##########################################

## one network per development period j; a finished run (its .rds) is not
## refitted; the networks of the first seed go to models/<tag>/
model_dir <- file.path(paths$models, tag)
dir.create(model_dir, showWarnings = FALSE)
for (run_name in names(runs)) {
  run_file <- file.path(paths$processed,
                        paste0(tag, "_fit_", run_name, ".rds"))
  if (file.exists(run_file)) next
  run <- runs[[run_name]]
  fits <- list()
  for (j in 1:(n_ay - 1)) {
    r <- learn_rows[[j]]
    # payments in millions: the mse loss and its gradients stay moderate,
    # which sgd needs (the adaptive optimisers are unaffected by the unit)
    c_prev <- cum[r, j] / units
    # Listing 2: responses C_j / sqrt(C_{j-1}), volumes sqrt(C_{j-1})
    y <- cum[r, j + 1] / units / sqrt(c_prev)
    w <- matrix(sqrt(c_prev), ncol = 1)
    # S3: output started in the homogeneous CL factor of the training rows
    f_start <- NULL
    if (run$cl_start) {
      train <- seq_len(floor(length(r) * (1 - param$validation_split)))
      f_start <- sum(cum[r[train], j + 1]) / sum(cum[r[train], j])
    }
    fit <- nncl_fit(x[r, ], y, w, x_diag, run$q, run$param, f_start)
    if (run$param$seed == cfg$seed) {
      save_model(fit$model,
                 file.path(model_dir, paste0(run_name, "_j", j, ".keras")),
                 overwrite = TRUE)
    }
    fit$model <- NULL
    # the losses L'_j (6.1) back in the payments' unit
    for (k in c("loss", "loss_train", "loss_vali")) fit[[k]] <- units * fit[[k]]
    fits[[j]] <- fit
    cat(sprintf(paste("%s j = %d: %.0f s, epochs %d/%d, loss %.1f",
                      "(homogeneous %.1f)\n"),
                run_name,
                j,
                fit$run_time,
                fit$epochs_used,
                fit$epochs_run,
                fit$loss / units,
                homogeneous$loss[j] / units))
  }
  saveRDS(list(run = run_name,
               age = age,
               q = run$q,
               param = run$param,
               fits = fits),
          run_file)
}

## S4: the networks of S3 with the balance correction
## c_j = sum C_{i,j}(x) / sum f(x) C_{i,j-1}(x) over the training rows, so
## that the average factor (3.9) there is the homogeneous CL factor
s3_file <- file.path(paths$processed, paste0(tag, "_fit_s3_cl_start.rds"))
s4_file <- file.path(paths$processed, paste0(tag, "_fit_s4_balance.rds"))
if (file.exists(s3_file) && !file.exists(s4_file)) {
  s4 <- readRDS(s3_file)
  s4$run <- "s4_balance"
  for (j in 1:(n_ay - 1)) {
    fit <- s4$fits[[j]]
    r <- learn_rows[[j]]
    c_prev <- cum[r, j]
    train <- seq_len(floor(length(r) * (1 - param$validation_split)))
    fit$balance <- sum(cum[r[train], j + 1]) /
      sum(fit$f_learn[train] * c_prev[train])
    fit$f_learn <- fit$balance * fit$f_learn
    fit$f_diag <- fit$balance * fit$f_diag
    res2 <- (cum[r, j + 1] - fit$f_learn * c_prev)^2 / c_prev
    fit$loss <- sum(res2)
    fit$loss_train <- sum(res2[train])
    fit$loss_vali <- sum(res2[-train])
    s4$fits[[j]] <- fit
  }
  saveRDS(s4, s4_file)
}

##########################################
#########  zero claims features (Section 4.2)
##########################################

## the rules of "NN chain ladder fit.R" for the one portfolio (a single
## LoB): per accident year i = 2..I the CL factors g^(i) of the zero claims
## features and their ultimate C_{i,I-i} prod g^(i); only the observed upper
## triangle enters (NA elsewhere)
cum_obs <- ifelse(observed, cum, NA)
vol <- rowsum(cum_obs, cells$i)                # the observed triangle
zero_factors <- NULL
ult_zero <- matrix(0, 1, n_ay)
for (i in 2:n_ay) {
  z <- nncl_zero_claims_factors(cum_obs, cells$i, vol, i)
  zero_factors <- rbind(zero_factors, data.frame(LoB = 1, z$factors))
  ult_zero[1, i] <- z$ultimate
}
## a positive numerator over a zero denominator: there is no second LoB to
## pool the ratio over, so these factors stay infinite; they are harmless
## while the first factor g_{I-i} of their accident year is 0 (ultimate 0),
## otherwise the reserves (5.1) stop in the analysis script
zero_factors[zero_factors$pooled, ]
stopifnot(all(is.finite(ult_zero)))
saveRDS(list(factors = zero_factors, ult_zero = ult_zero),
        file.path(paths$processed, "nncl_synthetic_zero_claims.rds"))
round(ult_zero / units, 1)
