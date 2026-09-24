############################# RESERVING METRICS ################################
# R/metrics.R -- functions only, no top-level code.
#
# Summaries of a fitted mean square mu (n x n, rows = accident periods,
# columns = development periods; upper triangle fitted, lower triangle
# predicted), as used for the tables and figures of Paper C (Gabrielli,
# Richman & Wuthrich 2020).


#' Reserves by origin from a fitted mean square
#'
#' Same shape as $by_origin of the classical wrappers in
#' R/classical_models.R, so reserve_totals() and save_reserve_tables() work on
#' it. The reserve (ibnr) of origin i is the sum of mu over its future cells
#' i + j > n + 1. No standard errors (se, cv are NA).
#'
#' @param y observed incremental upper triangle (lower triangle NA or ignored).
#' @param mu n x n fitted / predicted means, in the units of y.
reserve_by_origin <- function(y, mu) {
  y  <- unname(as.matrix(y)) 
  mu <- unname(as.matrix(mu))
  n  <- nrow(mu)
  fut <- fut_mask(n)
  latest <- rowSums(ifelse(fut, 0, y), na.rm = TRUE)   # cumulative paid to date
  ibnr <- rowSums(ifelse(fut, mu, 0))
  ultimate <- latest + ibnr
  data.frame(origin = seq_len(n), latest = latest,
             dev_to_date = ifelse(ultimate > 0, latest / ultimate, NA_real_),
             ultimate = ultimate, ibnr = ibnr, se = NA_real_, cv = NA_real_)
}


#' Cumulative development factors by accident period (Paper C, Figure 8)
#'
#' From the means mu(i, l): individual CL factors
#'   f(i, j) = sum_{l <= j} mu(i, l) / sum_{l <= j - 1} mu(i, l),
#' and their cumulative version g(i, j) = prod_{l = 2..j} f(i, l)
#'   = sum_{l <= j} mu(i, l) / mu(i, 1)   (development periods 1-based).
#' Under the ccODP model every row is the same (the CL factors); the bCCNN
#' model lets them vary by accident period.
#'
#' @param mu n x n means.
#' @return n x (n - 1) matrix of g(i, j), j = 2..n.
cum_dev_factors <- function(mu) {
  mu <- unname(as.matrix(mu))
  n  <- ncol(mu)
  cs <- t(apply(mu, 1, cumsum))
  g  <- cs[, -1, drop = FALSE] / cs[, 1]
  dimnames(g) <- list(origin = seq_len(nrow(mu)), dev = 2:n)
  g
}


#' Pearson residuals (Paper C, Figure 7)
#'
#' (y - mu) / sqrt(phi * mu), NA where y is NA.
#'
#' @param y observed values (matrix, NA = not shown).
#' @param mu means of the same shape.
#' @param phi dispersion of the model that produced mu.
pearson_residuals <- function(y, mu, phi) {
  y  <- unname(as.matrix(y))
  mu <- unname(as.matrix(mu))
  (y - mu) / sqrt(phi * mu)
}
