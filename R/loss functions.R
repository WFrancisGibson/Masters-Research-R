############################# LOSS FUNCTIONS ###################################
# R/losses.R -- functions only, no top-level code.


#' Poisson deviance loss (Paper C, eq. (4))
#'
#' The un-scaled deviance (dispersion phi = 1) that the ccODP maximum
#' likelihood fit and the bCCNN gradient descent both minimise:
#'   2 * sum( mu - y + y * log(y / mu) ),   y * log(y / mu) = 0 for y = 0.
#' Cells where y is NA are skipped, so one call gives the in-sample loss of an
#' upper triangle (lower triangle NA) and another the out-of-sample loss of a
#' lower triangle (upper triangle NA). Divide by phi for the scaled deviance.
#'
#' @param y observed values (vector or matrix, NA = not scored).
#' @param mu means of the same shape, > 0.
poisson_deviance <- function(y, mu) {
  y  <- as.vector(as.matrix(y))
  mu <- as.vector(as.matrix(mu))
  stopifnot(length(y) == length(mu))
  ok <- !is.na(y)
  y  <- y[ok]
  mu <- mu[ok]
  if (any(!is.finite(mu) | mu <= 0)) {
    stop("poisson_deviance(): mu must be positive and finite on the scored cells",
         call. = FALSE)
  }
  2 * sum(mu - y + ifelse(y > 0, y * log(y / mu), 0))
}


#' Keras "poisson" loss -> Poisson deviance
#'
#' Keras minimises mean(mu - y * log(mu)) over a batch. Over n observations y
#' this is an affine function of the deviance above:
#'   deviance = 2 * n * loss + 2 * sum(y * log(y) - y),
#' so the two have the same minimiser and the same gradient-descent path.
#' (Keras adds 1e-7 inside the log, which is negligible here.)
#'
#' @param loss Keras loss value(s) computed on the observations y.
#' @param y the observations the loss was computed on.
keras_poisson_to_deviance <- function(loss, y) {
  y <- y[!is.na(y)]
  2 * length(y) * loss + 2 * sum(ifelse(y > 0, y * log(y), 0) - y)
}
