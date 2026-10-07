##########################################
#########  NN chain ladder: CL factor networks and zero claims features
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Sections 3-4, Appendix 2 (Listing 2)
##########################################

## Keras runs on Python through reticulate, as for analysis/03_bCCNN. The
## data are the paper's own four LoBs, the data set machine4 of config.yml
## (set below): the cells go to data/interim/machine4 and the fits to
## data/processed/machine4. The fits made before the data sets had folders
## of their own are in data/interim (nncl_cells.rds) and data/processed
## (nncl_fit_<run>.rds, nncl_homogeneous.rds, nncl_zero_claims.rds): copied
## to these two folders they are read as before, a saved run is not refitted
Sys.setenv(DATASET = "machine4", UNIT = "")
source(here::here("analysis", "00_setup.R"))
library(keras3)

n_ay <- cfg$data$n_dev                         # I = 12, J = I - 1 = 11
first_ay <- cfg$data$first_ay                  # 1994
pay_cols <- sprintf("Pay%02d", 0:(n_ay - 1))
features <- c("LoB", "cc", "AQ", "age", "inj_part")

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

##########################################
#########  cells (i, x) and cumulative payments C_{i,j}(x)
##########################################

## claims of analysis/00_claim-simulation/individual_claims_simulation_machine.R
claims <- fread(file.path(paths$raw, cfg$data$dir, "claims.csv"),
                select = c(features, "AY", "RepDel", pay_cols),
                colClasses = list(numeric = pay_cols))
claims$i <- claims$AY - first_ay + 1           # accident year i = 1..I
claims$reported <- claims$i + claims$RepDel <= n_ay   # known at the end of 2005

## C_{i,j}(x): all claims of accident year i with feature x (Section 2),
## ordered by i and the features (the row order of the Keras split); the
## upper triangle i + j <= I is the data, the lower triangle the truth
cells <- claims[, c(list(n_claims = .N, n_reported = sum(reported)),
                    lapply(.SD, sum)),
                keyby = c("i", features),
                .SDcols = pay_cols]
rm(claims)
cum <- as.matrix(cells[, pay_cols, with = FALSE])
for (j in 2:n_ay) cum[, j] <- cum[, j - 1] + cum[, j]
colnames(cum) <- paste0("cum_", 0:(n_ay - 1))
cells[, (pay_cols) := NULL]
cells <- cbind(cells, cum)
cells$c_diag <- cum[cbind(seq_len(nrow(cum)), n_ay - cells$i + 1)]  # C_{i,I-i}
observed <- outer(cells$i, 0:(n_ay - 1), "+") <= n_ay
saveRDS(cells, file.path(paths$interim, "nncl_cells.rds"))

## recoveries can make a cumulative negative (against the standing assumption
## of Section 2): such cells join the zero claims features (<= 0)
c("cells" = nrow(cells),
  "observed cells with C < 0" = sum(cum < 0 & observed),
  "diagonal cells with C < 0" = sum(cells$c_diag < 0),
  "their diagonal amount" = sum(pmin(cells$c_diag, 0)))

##########################################
#########  feature pre-processing (Section 3.3)
##########################################

## (i) dummy coding of LoB, cc and inj_part, reference label the one with the
## most reported claims; (ii) MinMaxScaler (3.8) of AQ and age to [-1, 1]
x <- NULL
for (v in c("LoB", "cc", "inj_part")) {
  n_lab <- cells[, .(n = sum(n_reported)), by = v]
  ref <- n_lab[[v]][which.max(n_lab$n)]
  cat(v, ": ", nrow(n_lab), " labels, reference label ", ref, "\n", sep = "")
  lab <- relevel(factor(cells[[v]]), ref = as.character(ref))
  x <- cbind(x, model.matrix(~lab)[, -1])
}
for (v in c("AQ", "age")) {
  x_v <- cells[[v]]
  x <- cbind(x, 2 * (x_v - min(x_v)) / (max(x_v) - min(x_v)) - 1)
}
d <- ncol(x)            # 3 + 50 + 45 + 2 = 100 (Table 5: q (d + 1) + q + 1)
d

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
## f_{j-1} = sum C_{i,j}(x) / sum C_{i,j-1}(x) over the learning cells
homogeneous <- data.frame(j = 1:(n_ay - 1),
                          n_cells = lengths(learn_rows),
                          paper_loss = c(2255.9, 252.9, 51.4, 24.6, 16.9,
                                         8.7, 5.9, 2.0, 1.3, 1.2, 0.4))
homogeneous$f_hom <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  sum(cum[r, j + 1]) / sum(cum[r, j])
})
homogeneous$loss <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  sum((cum[r, j + 1] - homogeneous$f_hom[j] * cum[r, j])^2 / cum[r, j])
})
saveRDS(homogeneous, file.path(paths$processed, "nncl_homogeneous.rds"))
cbind(homogeneous[, 1:2],
      f_hom = round(homogeneous$f_hom, 4),
      loss_millions = round(homogeneous$loss / 1e6, 1),
      paper = homogeneous$paper_loss)

## Section 4: feature values x with a positive C_{i,0}(x), i <= 11
## (paper 830,380), and the accident years of Keras's validation rows (j = 1)
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
## refitted; the networks go to models/
for (run_name in names(runs)) {
  run_file <- file.path(paths$processed, paste0("nncl_fit_", run_name, ".rds"))
  if (file.exists(run_file)) next
  run <- runs[[run_name]]
  fits <- list()
  for (j in 1:(n_ay - 1)) {
    r <- learn_rows[[j]]
    c_prev <- cum[r, j]
    # Listing 2: responses C_j / sqrt(C_{j-1}), volumes sqrt(C_{j-1})
    y <- cum[r, j + 1] / sqrt(c_prev)
    w <- matrix(sqrt(c_prev), ncol = 1)
    # S3: output started in the homogeneous CL factor of the training rows
    f_start <- NULL
    if (run$cl_start) {
      train <- seq_len(floor(length(r) * (1 - param$validation_split)))
      f_start <- sum(cum[r[train], j + 1]) / sum(c_prev[train])
    }
    fit <- nncl_fit(x[r, ], y, w, x_diag, run$q, run$param, f_start)
    save_model(fit$model,
               file.path(paths$models,
                         paste0("nncl_", run_name, "_j", j, ".keras")),
               overwrite = TRUE)
    fit$model <- NULL
    # f(x) of the part-1 diagonal cells, under its name in the saved runs
    fit$f_diag <- fit$f_new
    fit$f_new <- NULL
    fits[[j]] <- fit
    cat(sprintf(paste("%s j = %d: %.0f s, epochs %d/%d, loss %.1f",
                      "(homogeneous %.1f)\n"),
                run_name,
                j,
                fit$run_time,
                fit$epochs_used,
                fit$epochs_run,
                fit$loss / 1e6,
                homogeneous$loss[j] / 1e6))
  }
  saveRDS(list(run = run_name, q = run$q, param = run$param, fits = fits),
          run_file)
}

## S4: the networks of S3 with the balance correction
## c_j = sum C_{i,j}(x) / sum f(x) C_{i,j-1}(x) over the training rows, so
## that the average factor (3.9) there is the homogeneous CL factor
s3_file <- file.path(paths$processed, "nncl_fit_s3_cl_start.rds")
s4_file <- file.path(paths$processed, "nncl_fit_s4_balance.rds")
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

## per LoB and accident year i = 2..I the CL factors g^(i) of the zero claims
## features and their ultimate C_{i,I-i} prod g^(i); only the observed upper
## triangle enters (NA elsewhere)
cum_obs <- ifelse(observed, cum, NA)
lobs <- sort(unique(cells$LoB))
lob_rows <- lapply(lobs, function(l) which(cells$LoB == l))
## the LoBs' observed triangles
vol <- lapply(lob_rows, function(r) rowsum(cum_obs[r, ], cells$i[r]))
zero_factors <- NULL
for (l in lobs) {
  r <- lob_rows[[l]]
  for (i in 2:n_ay) {
    z <- nncl_zero_claims_factors(cum_obs[r, ], cells$i[r], vol[[l]], i)
    zero_factors <- rbind(zero_factors, data.frame(LoB = l, z$factors))
  }
}
## the paper assumes 'all denominators are positive': a factor with a
## positive numerator over a zero denominator takes the ratio pooled over the
## LoBs (LoB 3, accident year 1997: g_9)
pooled <- aggregate(cbind(num, den) ~ j + i, zero_factors, sum)
ult_zero <- matrix(0, length(lobs), n_ay)
zero_factors <- NULL
for (l in lobs) {
  r <- lob_rows[[l]]
  for (i in 2:n_ay) {
    p <- pooled[pooled$i == i, ]
    z <- nncl_zero_claims_factors(cum_obs[r, ],
                                  cells$i[r],
                                  vol[[l]],
                                  i,
                                  p$num / p$den)
    zero_factors <- rbind(zero_factors, data.frame(LoB = l, z$factors))
    ult_zero[l, i] <- z$ultimate
  }
}
zero_factors[zero_factors$pooled, ]
saveRDS(list(factors = zero_factors, ult_zero = ult_zero),
        file.path(paths$processed, "nncl_zero_claims.rds"))
round(ult_zero / cfg$nncl$units)
