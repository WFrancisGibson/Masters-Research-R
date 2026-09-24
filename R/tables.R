############################# RESULT TABLES ####################################
# R/tables.R -- functions only, no top-level code.
#
# Tables of the ccODP and bCCNN fits after Paper C (Gabrielli, Richman &
# Wuthrich 2020): Tables 2 and 4 (reserves, biases, losses, dispersion) and
# Table 3 (early-stopping analysis), for one triangle.


#' Paper C tables for a bccnn_calibrate() result
#'
#' All amounts (reserves, biases, deviance losses, dispersions) are in units of
#' res$scale, like Paper C's 1'000 CHF; the results table states the unit on
#' its last row. Losses are un-scaled Poisson deviances (phi = 1): in-sample on
#' the observed upper triangle, out-of-sample on the true lower triangle. The
#' true reserves run to development period n; payments after it (tail_o of
#' triangle_sets()) are in no triangle and are reported on their own row.
#'
#' @param res bccnn_calibrate() result.
#' @param sets the triangle_sets() result it was fitted on.
#' @return a list of data.frames:
#'   settings    how the steps were chosen and the final network fitted;
#'   results     Paper C Tables 2 and 4 (one column: this triangle);
#'   validation  Paper C Table 3 at the steps used, and the chosen steps;
#'   rolling_origin  test partitions and final partition (Al-Mudafer et al.
#'               2021), with the test error (4.4); NULL for the claims split;
#'   by_origin   reserves and biases by accident period, with a total row;
#'   odp_parameters  ccODP c, alpha_i, beta_j;
#'   mu_ccODP, mu_bCCNN  fitted (upper) and predicted (lower) means;
#'   history_validation, history_fit  deviance by gradient-descent step.
bccnn_tables <- function(res, sets) {
  s <- res$scale
  odp <- res$odp
  nn <- res$nn
  val <- res$validation
  n <- length(odp$alpha)
  test <- unname(as.matrix(sets$test)) / s
  true_o <- rowSums(test, na.rm = TRUE)
  true <- sum(true_o)

  settings <- data.frame(
    setting = c("early stopping on", "final network", "steps chosen by",
                "units"),
    value = c(res$validation_method, res$final_fit,
              if (res$epochs == val$best_epoch) "lowest validation loss" else
                "override (config epochs)",
              format(s, scientific = FALSE)))

  # final_fit = "partition": the bCCNN never trained on the validation cells,
  # so its loss on the whole observed triangle is not purely in-sample
  partition_fit <- !is.null(nn$deviance_observed)
  results <- data.frame(
    quantity = c("true reserves", "CL reserves (ccODP)", "bCCNN reserves",
                 "bias CL", "bias bCCNN", "bias CL (%)", "bias bCCNN (%)",
                 "in-sample loss ccODP",
                 if (partition_fit) {
                   "loss bCCNN on the observed triangle (validation cells out-of-sample)"
                 } else "in-sample loss bCCNN",
                 "out-of-sample loss ccODP", "out-of-sample loss bCCNN",
                 "dispersion ccODP", "dispersion bCCNN",
                 "gradient descent steps",
                 "payments after the last development period (not modelled)",
                 "amounts in units of"),
    value = c(true, odp$reserve, nn$reserve,
              odp$reserve - true, nn$reserve - true,
              100 * (odp$reserve / true - 1), 100 * (nn$reserve / true - 1),
              odp$deviance,
              if (partition_fit) nn$deviance_observed else nn$deviance,
              poisson_deviance(test, odp$mu), poisson_deviance(test, nn$mu),
              res$phi[["ccODP"]], res$phi[["bCCNN"]],
              res$epochs, sum(sets$tail_o) / s, s))

  h <- val$history
  at <- function(e, col) h[h$epoch == e, col]
  steps <- res$epochs
  dec <- res$decrease
  validation <- data.frame(
    quantity = c("validation run length (epochs)",
                 "step with lowest validation loss",
                 "steps used for the final fit",
                 "in-sample deviance without dropout at start (ccODP)",
                 "in-sample deviance without dropout at the steps used",
                 "validation loss at start (ccODP)",
                 "validation loss at the steps used",
                 "decrease in-sample deviance without dropout (%)",
                 "decrease in-sample training loss with dropout (%, Figure 2)",
                 "decrease out-of-sample validation loss (%)"),
    value = c(max(h$epoch), val$best_epoch, steps,
              at(0, "train"), at(steps, "train"),
              at(0, "vali"), at(steps, "vali"),
              100 * dec[["train"]], 100 * dec[["train_dropout"]],
              100 * dec[["vali"]]))

  rolling <- NULL
  if (!is.null(res$rolling_origin)) {
    ro <- res$rolling_origin
    # test_*_ccODP: chain ladder at each valuation date (like-for-like
    # baseline of final_fit "refit"); test_*_ccODP_train: ccODP on the
    # training cells (like-for-like baseline of "partition")
    rolling <- ro$summary
    rolling$test_loss_per_cell_ccODP <- rolling$test_loss_ccODP / rolling$n_test
    rolling$test_loss_per_cell_ccODP_train <-
      rolling$test_loss_ccODP_train / rolling$n_test
    rolling$test_loss_per_cell_bCCNN <- rolling$test_loss_bCCNN / rolling$n_test
    tst <- rolling[rolling$partition != "final", ]
    rolling <- rbind(rolling, data.frame(
      partition = "test error (4.4)", origin = NA, n_train = NA, n_vali = NA,
      n_test = sum(tst$n_test), best_epoch = NA,
      test_actual = sum(tst$test_actual), test_ccODP = sum(tst$test_ccODP),
      test_ccODP_train = sum(tst$test_ccODP_train),
      test_bCCNN = sum(tst$test_bCCNN),
      test_loss_ccODP = sum(tst$test_loss_ccODP),
      test_loss_ccODP_train = sum(tst$test_loss_ccODP_train),
      test_loss_bCCNN = sum(tst$test_loss_bCCNN),
      test_loss_per_cell_ccODP = ro$test_error[["ccODP"]],
      test_loss_per_cell_ccODP_train = ro$test_error[["ccODP_train"]],
      test_loss_per_cell_bCCNN = ro$test_error[["bCCNN"]]))
  }

  by_origin <- data.frame(origin = as.character(seq_len(n)),
                          latest = odp$by_origin$latest, true = true_o,
                          CL = odp$reserve_o, bCCNN = nn$reserve_o)
  by_origin$bias_CL <- by_origin$CL - by_origin$true
  by_origin$bias_bCCNN <- by_origin$bCCNN - by_origin$true
  total <- colSums(by_origin[, -1])
  by_origin <- rbind(by_origin,
                     data.frame(origin = "total", as.list(total)))

  mu_table <- function(mu) {
    data.frame(origin = seq_len(n), unname(as.matrix(mu)),
               check.names = FALSE) |>
      stats::setNames(c("origin", seq_len(n)))
  }
  list(settings = settings, results = results, validation = validation,
       rolling_origin = rolling, by_origin = by_origin,
       odp_parameters = data.frame(period = seq_len(n), c = odp$c,
                                   alpha = odp$alpha, beta = odp$beta),
       mu_ccODP = mu_table(odp$mu), mu_bCCNN = mu_table(nn$mu),
       history_validation = h, history_fit = nn$history)
}


#' Write a list of tables as CSV files
#'
#' Writes <dir>/<prefix>_<name>.csv for every data.frame in `tables`.
#'
#' @param tables named list of data.frames (e.g. bccnn_tables()).
#' @param prefix file-name prefix, e.g. "bccnn_annual".
#' @param dir output folder; default paths$tables (from analysis/00_setup.R).
#' @return the file paths, invisibly.
write_tables <- function(tables, prefix, dir = paths$tables) {
  files <- file.path(dir, paste0(prefix, "_", names(tables), ".csv"))
  for (k in seq_along(tables)) {
    if (!is.null(tables[[k]])) data.table::fwrite(tables[[k]], files[k])
  }
  invisible(files)
}
