##########################################
#########  stand-ins for keras3 in the bCCNN fit scripts (no Keras, no
#########  Python); test-bccnn_scripts.R runs a copy of each fit script with
#########  this file in place of library(keras3)
##########################################

## the functions of keras3 the fit scripts call: fit() takes the gradient
## descent steps and calls the callback as Keras does (epochs from 0, the
## loss of the epoch in logs); attached like a package, a script may name a
## variable fit
attach(list(
  `%>%` = magrittr::`%>%`,
  callback_lambda = function(on_epoch_begin, on_epoch_end) {
    list(on_epoch_begin = on_epoch_begin, on_epoch_end = on_epoch_end)
  },
  fit = function(model, x, y, epochs, callbacks, ...) {
    for (e in seq_len(epochs)) {
      callbacks[[1]]$on_epoch_begin(e - 1, list())
      model$steps <- model$steps + 1
      callbacks[[1]]$on_epoch_end(e - 1, list(loss = 1 / e))
    }
  },
  save_model = function(model, filepath, overwrite) {
    saveRDS("stand-in for a Keras model", filepath)
  }
), name = "keras_stand_ins")

## stand-in for bccnn_model() (R/nn_models.R): the "network" starts in the
## ccODP odp and moves with the steps towards the payments of the triangle
## odp was fitted on, with a noise per cell; speed, noise and with them the
## validation losses depend on the seed only, not on the other
## hyper-parameters
bccnn_model <- function(odp, param) {
  n <- nrow(odp$mu)
  set.seed(param$seed)
  noise <- matrix(rnorm(n * n, sd = 0.3), n, n)
  learn <- ifelse(is.na(odp$y), 0, log(pmax(odp$y, 1e-6) / odp$mu))
  rate <- runif(1, 20, 60)
  phase <- runif(1, 0, 20)
  model <- new.env()
  model$steps <- 0
  model$predict_on_batch <- function(x) {
    e <- model$steps
    a <- (1 - exp(-e / rate)) * (1.6 + 0.3 * sin(e / 5 + phase))
    cell <- cbind(x[[1]] + 1, x[[2]] + 1)
    odp$mu[cell] * exp(a * (learn[cell] + 0.02 * noise[cell]))
  }
  model
}
