##########################################
#########  stand-ins for keras3 in the NN chain ladder SynthETIC scripts (no
#########  Keras, no Python); test-nncl_scripts.R runs a copy of the fit and
#########  the search script with this file in place of library(keras3)
##########################################

## the functions of keras3 that nncl_fit() and the scripts call, attached
## like a package. The "network" of nncl_model() below has one CL factor for
## all feature values: an epoch of fit() takes it half of the way to the
## homogeneous CL factor of the rows it is given (the least squares factor of
## Listing 2's responses on the volumes) and calls the callback as Keras
## does; with early stopping the factor of the epoch with the lowest
## validation loss is restored (no patience: all epochs are run)
attach(list(
  `%>%` = magrittr::`%>%`,
  clear_session = function() NULL,
  get_weights = function(net) net$f,
  set_weights = function(net, f) net$f <- f,
  predict = function(net, xw, ...) net$f * xw[[2]],
  count_params = function(object) if (is.environment(object)) 322 else 1,
  get_layer = function(net, name) name,
  callback_lambda = function(on_epoch_end) list(on_epoch_end = on_epoch_end),
  callback_early_stopping = function(...) "early stopping",
  fit = function(net, xw, y, epochs, validation_split, callbacks, ...) {
    w <- xw[[2]]
    train <- seq_len(floor(nrow(y) * (1 - validation_split)))
    f_hom <- sum(y * w) / sum(w^2)
    f <- loss <- val_loss <- NULL
    for (e in seq_len(epochs)) {
      net$f <- f[e] <- (net$f + f_hom) / 2
      res2 <- (y - net$f * w)^2
      loss[e] <- mean(res2[train])
      val_loss[e] <- mean(res2[-train])
      callbacks[[1]]$on_epoch_end(e - 1, list())
    }
    if (length(callbacks) == 2) net$f <- f[which.min(val_loss)]
    list(metrics = list(loss = loss, val_loss = val_loss))
  },
  save_model = function(model, filepath, overwrite) {
    saveRDS("stand-in for a Keras model", filepath)
  }
), name = "nncl_stand_ins")

## stand-in for nncl_model() (R/nn_chain_ladder.R): the random start is a CL
## factor of 2 for every seed and every setting, the CL start f_start
nncl_model <- function(d, q, param, f_start = NULL) {
  net <- new.env()
  net$f <- if (is.null(f_start)) 2 else f_start
  net
}

## stand-in for nncl_mack() (R/nn_chain_ladder.R, the search script): no
## chain ladder is estimated, its "reserves" are the outstanding payments
nncl_mack <- function(cum) {
  n <- nrow(cum)
  list(by_origin = data.frame(ibnr = cum[, n] - cum[cbind(1:n, n:1)]),
       total_se = 0)
}
