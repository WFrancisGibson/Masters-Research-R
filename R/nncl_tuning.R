##########################################
#########  NN chain ladder hyperparameters chosen on rolling-origin folds
#########  Wuthrich (2018), EAJ 8:407-436, Section 3 and Listing 2; folds
#########  and search after Al-Mudafer, Avanzi, Taylor & Wong (2021)
##########################################

## Own design, not in the paper. The CL factor networks of the fit script
## ("NN chain ladder SynthETIC fit.R") are replayed at the earlier valuation
## dates tau = I - test_periods: networks j = 1..tau - 1 on the learning
## cells known at tau (i <= tau - j, C_{i,j-1}(x) > 0, the fit script with I
## replaced by tau, Keras's validation split and early stopping included),
## the cumulative payments of the part-1 cells (C_{i,tau-i}(x) > 0) projected
## with them, C_{i,j}(x) = C_{i,tau-i}(x) prod_{l=tau-i+1}^{j} f_{l-1}(x), and
## scored on the cells observed after tau: tau < i + j <= I, j <= tau - 1
## (the networks known at tau). Loss of a test cell, in the units of the
## fit: (C_{i,j}(x) - projection)^2 / C_{i,tau-i}(x), the loss (6.1) of the
## paper carried to several steps ahead (variance proportional to the
## volume, as in Mack's chain ladder). Baseline: the homogeneous chain ladder
## at tau (Mack's CL factors of the learning cells known at tau). The zero
## claims features (part 2 of (5.1), Section 4.2) do not depend on the
## networks and are not scored. j: development year 0..J; column j + 1 of
## cum is C_{.,j}.

## arguments that can be tuned: hidden (the neurons of the hidden layers,
## the q of nncl_model()) and the elements of param
nncl_tunable <- c("hidden", "activation", "dropout", "optimizer",
                  "learning_rate", "momentum", "epochs", "patience",
                  "batch_size", "validation_split")

## the cells of the NN chain ladder at the valuation date tau: learning rows
## of networks j = 1..tau - 1, the part-1 rows (accident years 2..tau with
## C_{i,tau-i}(x) > 0), their latest development year m = tau - i and
## C_{i,tau-i}(x), and the test cells (k: row of diag_rows, j: development
## year) observed after tau up to the end of year I = ncol(cum)
nncl_origin <- function(cum, ay, tau) {
  n_ay <- ncol(cum)
  stopifnot(tau >= 2, tau < n_ay)
  learn_rows <- lapply(seq_len(tau - 1), function(j) {
    which(ay <= tau - j & cum[, j] > 0)
  })
  known <- which(ay > 1 & ay <= tau)
  m_all <- tau - ay[known]
  c_all <- cum[cbind(known, m_all + 1)]
  diag_rows <- known[c_all > 0]
  m <- m_all[c_all > 0]
  c_tau <- c_all[c_all > 0]
  test <- do.call(rbind, lapply(seq_len(tau - 1), function(j) {
    k <- which(m < j & j <= n_ay - ay[diag_rows])
    if (length(k) == 0) return(NULL)
    data.frame(k = k, j = j)
  }))
  list(tau = tau,
       learn_rows = learn_rows,
       diag_rows = diag_rows,
       m = m,
       c_tau = c_tau,
       test = test)
}

## projected C_{i,j}(x) of the test cells of org: f is the matrix of the CL
## factors, row k of diag_rows, column l the factor of network l
## (C_{l-1} -> C_l), l = 1..tau - 1
nncl_project <- function(org, f) {
  cs <- log(f)
  if (ncol(cs) > 1) {
    for (l in 2:ncol(cs)) cs[, l] <- cs[, l - 1] + cs[, l]
  }
  cs <- cbind(0, cs)                 # column l + 1: sum of log f over 1..l
  k <- org$test$k
  org$c_tau[k] * exp(cs[cbind(k, org$test$j + 1)] - cs[cbind(k, org$m[k] + 1)])
}

## loss of the projections at org: the sum over the test cells and the
## payments between tau and I (per part-1 row, at its last test cell),
## actual and projected
nncl_test_loss <- function(org, cum, proj) {
  k <- org$test$k
  actual <- cum[cbind(org$diag_rows[k], org$test$j + 1)]
  last <- !duplicated(k, fromLast = TRUE)
  c(loss = sum((actual - proj)^2 / org$c_tau[k]),
    n_test = length(k),
    actual = sum(actual[last] - org$c_tau[k[last]]),
    projected = sum(proj[last] - org$c_tau[k[last]]))
}

## time-series cross-validation score of the set hp for the training mode
## 'run' (list(q, param, cl_start), a run of nncl_runs()): per seed and
## valuation date tau in origins, the networks j = 1..tau - 1 fitted as in
## the fit script (nncl_run_fit() with fit() = nncl_fit()), the part-1 cells
## projected and scored; cum, ay, x: the cells' cumulative payments, accident
## years and network inputs; units: the unit of the payments in the fit, as
## the fit script; the runs keep the seconds of the epochs of their networks
## (time); see tscv_summary()
nncl_tscv_score <- function(cum,
                            ay,
                            x,
                            origins,
                            hp,
                            run,
                            seeds,
                            units,
                            fit = nncl_fit) {
  hp_check(hp, nncl_tunable)
  cum <- cum / units
  if (!is.null(hp$hidden)) run$q <- hp$hidden
  run$param <- modifyList(run$param, hp[setdiff(names(hp), "hidden")])
  orgs <- lapply(origins, function(tau) nncl_origin(cum, ay, tau))
  # baseline: the homogeneous chain ladder at tau (no seed)
  base <- lapply(orgs, function(org) {
    f_hom <- sapply(seq_along(org$learn_rows), function(j) {
      r <- org$learn_rows[[j]]
      sum(cum[r, j + 1]) / sum(cum[r, j])
    })
    f <- matrix(f_hom, length(org$diag_rows), length(f_hom), byrow = TRUE)
    nncl_test_loss(org, cum, nncl_project(org, f))
  })
  runs <- do.call(rbind, lapply(seeds, function(s) {
    run$param$seed <- s
    do.call(rbind, lapply(seq_along(orgs), function(o) {
      org <- orgs[[o]]
      # the networks at tau predict the factors of its part-1 rows (cum is
      # in the unit of the fit already)
      fits <- nncl_run_fit(cum,
                           x,
                           org$learn_rows,
                           x[org$diag_rows, , drop = FALSE],
                           run,
                           units = 1,
                           fit = fit)
      f <- do.call(cbind, lapply(fits, `[[`, "f_new"))
      tl <- nncl_test_loss(org, cum, nncl_project(org, f))
      data.frame(seed = s,
                 origin = org$tau,
                 n_test = tl[["n_test"]],
                 steps = mean(sapply(fits, `[[`, "epochs_used")),
                 loss = tl[["loss"]],
                 loss_baseline = base[[o]][["loss"]],
                 test_actual = tl[["actual"]],
                 test_NN = tl[["projected"]],
                 test_CL = base[[o]][["projected"]],
                 time = sum(sapply(fits, `[[`, "run_time")))
    }))
  }))
  tscv_summary(runs, hp)
}
