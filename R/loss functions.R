##########################################
#########  Loss functions
##########################################

## Poisson deviance loss D(y, mu), Paper C eq. (4): data y first (the course's
## version has the prediction first); summed over the cells where y is observed
poisson_deviance <- function(y, mu) {
  keep <- which(!is.na(y))
  y <- y[keep]
  mu <- mu[keep]
  2 * sum(mu - y + ifelse(y > 0, y * log(y / mu), 0))
}

## Keras 'poisson' loss = mean(mu - y * log(mu)) over the N cells,
## so the Poisson deviance expressed as
## 2 * sum(mu - y + y * log(y / mu)) #nolint
## = 2 * N * loss + 2 * sum(y * log(y) - y)
keras_to_deviance <- function(loss, y) {
  2 * length(y) * loss + 2 * sum(ifelse(y > 0, y * log(y), 0) - y)
}
