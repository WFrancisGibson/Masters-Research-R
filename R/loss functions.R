############################# LOSS FUNCTIONS ###################################
# R/losses.R -- functions only, no top-level code.
# Poisson deviance loss

poisson_deviance <- function(y, mu) {
  y  <- as.vector(as.matrix(y))
  mu <- as.vector(as.matrix(mu))
  stopifnot(length(y) == length(mu))
  ok <- !is.na(y)
  y  <- y[ok]
  mu <- mu[ok]
  if (any(!is.finite(mu) | mu <= 0)) {
    stop("poisson_deviance():
          mu must be positive and finite on the scored cells",
         call. = FALSE)
  }
  2 * sum(mu - y + ifelse(y > 0, y * log(y / mu), 0))
}


# Keras "poisson" loss -> Poisson deviance
keras_poisson_to_deviance <- function(loss, y) {
  y <- y[!is.na(y)]
  2 * length(y) * loss + 2 * sum(ifelse(y > 0, y * log(y), 0) - y)
}
