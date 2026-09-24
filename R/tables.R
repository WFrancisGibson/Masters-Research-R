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
#' the observed upper triangle, out-of-sample on the true lower triangle.
#'
#' @param res bccnn_calibrate() result.
#' @param sets the triangle_sets() result it was fitted on.
#' @return a list of data.frames:
#'   results     Paper C Tables 2 and 4 (one column: this triangle);
#'   validation  Paper C Table 3 and the chosen number of steps;
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

  results <- data.frame(
    quantity = c("true reserves", "CL reserves (ccODP)", "bCCNN reserves",
                 "bias CL", "bias bCCNN", "bias CL (%)", "bias bCCNN (%)",
                 "in-sample loss ccODP", "in-sample loss bCCNN",
                 "out-of-sample loss ccODP", "out-of-sample loss bCCNN",
                 "dispersion ccODP", "dispersion bCCNN",
                 "gradient descent steps", "amounts in units of"),
    value = c(true, odp$reserve, nn$reserve,
              odp$reserve - true, nn$reserve - true,
              100 * (odp$reserve / true - 1), 100 * (nn$reserve / true - 1),
              odp$deviance, nn$deviance,
              poisson_deviance(test, odp$mu), poisson_deviance(test, nn$mu),
              res$phi[["ccODP"]], res$phi[["bCCNN"]],
              res$epochs, s))

  h <- val$history
  at <- function(e, col) h[h$epoch == e, col]
  best <- val$best_epoch
  validation <- data.frame(
    quantity = c("validation run length (epochs)",
                 "step with lowest validation loss",
                 "steps used for the final fit",
                 "training loss at start (ccODP)", "training loss at that step",
                 "validation loss at start (ccODP)", "validation loss at that step",
                 "decrease in-sample training loss (%)",
                 "decrease out-of-sample validation loss (%)"),
    value = c(max(h$epoch), best, res$epochs,
              at(0, "train"), at(best, "train"),
              at(0, "vali"), at(best, "vali"),
              100 * val$decrease[["train"]], 100 * val$decrease[["vali"]]))

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
  list(results = results, validation = validation, by_origin = by_origin,
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
