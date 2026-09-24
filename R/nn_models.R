############################# NEURAL NETWORK MODELS ############################
# R/nn_models.R -- functions only, no top-level code.
#
# The blended cross-classified neural network (bCCNN) of Paper C:
#   Gabrielli, Richman & Wuthrich (2020), Neural network embedding of the
#   over-dispersed Poisson reserving model, Scand. Actuarial J. 2020(1), 1-29
#   (= Paper C and Chapter 4 of Gabrielli (2020), PhD thesis, ETH Zurich).
#
# One triangle (one line of business); accident period i and development
# period j are 1-based here (Paper C's development year j = 0 is j = 1):
#
#   mu(i, j) = exp{ w * (alpha_i + beta_j) + c + <B, z3(i, j)> }          (13)
#
#   alpha_i, beta_j  ccODP estimates (fit_odp_glm()), used as fixed
#                    (non-trainable) one-dimensional embeddings;
#   z3               last of three tanh hidden layers (20, 15, 10), each
#                    followed by 10% dropout, fed with z0 = (alpha_i, beta_j);
#   w * (alpha_i + beta_j)  the skip connection: the ccODP model;
#   w, c, B          trainable output weights, started at
#                    w = 1, c = c_ODP, B = 0,                              (14)
#
# so the untrained network is exactly the ccODP (chain-ladder) model and
# gradient descent looks for structure beyond cross-classification. Loss:
# Poisson deviance (Keras "poisson"); optimiser: RMSprop; full batch, so one
# epoch is one gradient-descent step. The number of steps is chosen on a
# 50/50 claims split (bccnn_validation(), Section 3.3.2), then the network is
# refitted on the full triangle for exactly that many steps (Section 3.3.3).
#
# Keras functions (keras3) are called unqualified: analysis scripts attach
# keras3 through analysis/00_setup.R. Hyperparameters live in config.yml
# (bccnn:).


# Keras inputs for triangle cells: 0-based accident and development indices,
# as an embedding with input_dim = n looks up rows 0, ..., n - 1.
bccnn_inputs <- function(origin, dev) {
  list(matrix(as.integer(origin) - 1L, ncol = 1),
       matrix(as.integer(dev) - 1L, ncol = 1))
}


#' Build and compile a bCCNN model started in the ccODP model
#'
#' Paper C, eq. (13) with initialisation (14) and Listing 4.
#'
#' @param odp a fit_odp_glm() result: $c, $alpha, $beta (length n).
#' @param q neurons of the hidden layers; Paper C: c(20, 15, 10).
#' @param dropout dropout rate after every hidden layer; Paper C: 0.1.
#' @param activation hidden-layer activation; Paper C: "tanh".
#' @param trainable_embeddings FALSE (Paper C) keeps alpha and beta fixed at
#'   the ccODP estimates.
#' @param learning_rate,rho,epsilon RMSprop settings; Paper C used Keras's
#'   defaults (0.001, 0.9, 1e-7).
#' @param seed random seed of the hidden-layer initialisation and dropout.
#' @return a compiled Keras model with inputs (AccYear, DevYear), 0-based.
bccnn_model <- function(odp, q = c(20, 15, 10), dropout = 0.1,
                        activation = "tanh", trainable_embeddings = FALSE,
                        learning_rate = 0.001, rho = 0.9, epsilon = 1e-7,
                        seed = 2026) {
  n <- length(odp$alpha)
  stopifnot(length(odp$beta) == n, length(odp$c) == 1, length(q) >= 1)
  clear_session()
  set_random_seed(seed)

  embed <- function(input, name) {
    input |>
      layer_embedding(input_dim = n, output_dim = 1,
                      trainable = trainable_embeddings, name = name) |>
      layer_flatten(name = paste0(name, "_flat"))
  }
  accyear <- layer_input(shape = c(1), dtype = "int32", name = "AccYear")
  devyear <- layer_input(shape = c(1), dtype = "int32", name = "DevYear")
  ay <- embed(accyear, "AY_embed")
  dy <- embed(devyear, "DY_embed")

  cc0 <- layer_add(list(ay, dy), name = "CC0")            # alpha_i + beta_j
  nn0 <- layer_concatenate(list(ay, dy), name = "concate0")  # z0
  for (k in seq_along(q)) {
    nn0 <- nn0 |>
      layer_dense(units = q[k], activation = activation,
                  name = paste0("hidden", k)) |>
      layer_dropout(rate = dropout, name = paste0("dropout", k))
  }
  response <- layer_concatenate(list(cc0, nn0), name = "concate1") |>
    layer_dense(units = 1, activation = "exponential", name = "Response")
  model <- keras_model(inputs = list(accyear, devyear), outputs = response)

  # starting point (14): embeddings = ccODP effects; output kernel
  # (w, B) = (1, 0, ..., 0) and bias c = c_ODP
  set_weights(get_layer(model, "AY_embed"), list(matrix(odp$alpha, ncol = 1)))
  set_weights(get_layer(model, "DY_embed"), list(matrix(odp$beta, ncol = 1)))
  set_weights(get_layer(model, "Response"),
              list(matrix(c(1, rep(0, q[length(q)])), ncol = 1),
                   array(odp$c, dim = 1)))

  model |> compile(loss = "poisson",
                   optimizer = optimizer_rmsprop(learning_rate = learning_rate,
                                                 rho = rho, epsilon = epsilon))
  model
}


#' Train a bCCNN model on an observed triangle
#'
#' Starts in the ccODP model `odp` (checked: the untrained network must
#' reproduce odp$mu) and runs `epochs` gradient-descent steps on the observed
#' upper triangle.
#'
#' @param odp fit_odp_glm() of the same triangle.
#' @param y observed incremental triangle, n x n, in the units of odp (already
#'   divided by odp$scale); its lower triangle is ignored. Default odp$y.
#' @param epochs number of epochs; with the default full batch, the number of
#'   gradient-descent steps. 0 returns the untrained network, i.e. the ccODP
#'   model.
#' @param batch_size NULL = full batch (all observed cells), as Paper C.
#' @param track optional named list of n x n matrices in the units of y, NA
#'   outside the cells to score (e.g. a validation upper triangle, or the true
#'   lower triangle for back-testing). Their deviance is only recorded; it
#'   plays no part in the fit.
#' @param monitor TRUE records, after every epoch, the Poisson deviance of the
#'   network in inference mode (no dropout) on y and on each `track` matrix,
#'   and Keras's training loss (computed with dropout) as a deviance. This
#'   needs one prediction per epoch; FALSE skips it.
#' @param verbose Keras verbosity.
#' @param ... passed to bccnn_model() (q, dropout, activation, ..., seed).
#' @return a list: model; mu (n x n fitted and predicted means); by_origin,
#'   total, reserve_o, reserve (reserves, units of y); deviance (in-sample,
#'   phi = 1); epochs; history (data.frame: epoch, train_dropout, train, one
#'   column per track; epoch 0 is the ccODP start) or NULL; scale.
fit_bccnn <- function(odp, y = odp$y, epochs, batch_size = NULL, track = NULL,
                      monitor = TRUE, verbose = 0, ...) {
  n <- length(odp$alpha)
  y <- unname(as.matrix(y))
  if (!identical(dim(y), c(n, n))) {
    stop("fit_bccnn(): y must be ", n, " x ", n, call. = FALSE)
  }
  y[fut_mask(n)] <- NA
  cells <- triangle_long(y)
  obs <- cells[cells$upper, ]
  if (anyNA(obs$value)) {
    stop("fit_bccnn(): the upper triangle of y has NA cells", call. = FALSE)
  }
  x_obs <- bccnn_inputs(obs$origin, obs$dev)
  y_obs <- matrix(obs$value, ncol = 1)
  x_all <- bccnn_inputs(cells$origin, cells$dev)

  if (!is.null(track)) {
    if (is.null(names(track)) || any(names(track) %in% c("", "epoch", "train",
                                                         "train_dropout"))) {
      stop("fit_bccnn(): track must be a list with (new) names", call. = FALSE)
    }
    track <- lapply(track, function(t) unname(as.matrix(t)))
    if (!all(vapply(track, function(t) identical(dim(t), c(n, n)), logical(1)))) {
      stop("fit_bccnn(): every track matrix must be ", n, " x ", n, call. = FALSE)
    }
  }
  scored <- c(list(train = y), track)

  model <- bccnn_model(odp, ...)
  mu_of <- function() {
    matrix(as.numeric(predict_on_batch(model, x_all)), n, n)
  }

  # the untrained network is the ccODP model (up to float32 rounding)
  mu <- mu_of()
  gap <- max(abs(mu / odp$mu - 1))
  if (gap > 1e-4) {
    stop(sprintf(paste("fit_bccnn(): the untrained network does not reproduce",
                       "the ccODP model (max relative difference %.3g)"), gap),
         call. = FALSE)
  }

  rows <- list()
  record <- function(epoch, loss, mu) {
    rows[[length(rows) + 1L]] <<-
      c(epoch = epoch,
        train_dropout = keras_poisson_to_deviance(loss, obs$value),
        vapply(scored, poisson_deviance, numeric(1), mu = mu))
  }
  callbacks <- NULL
  if (monitor) {
    record(0L, NA_real_, mu)
    step <- 0L
    callbacks <- list(callback_lambda(on_epoch_end = function(epoch, logs) {
      step <<- step + 1L
      record(step, as.numeric(logs[["loss"]]), mu_of())
    }))
  }

  if (epochs > 0) {
    model |> fit(x = x_obs, y = y_obs, epochs = as.integer(epochs),
                 batch_size = as.integer(if (is.null(batch_size)) nrow(obs) else batch_size),
                 callbacks = callbacks, verbose = verbose, view_metrics = FALSE)
    mu <- mu_of()
  }
  dimnames(mu) <- list(origin = seq_len(n), dev = seq_len(n))

  by_origin <- reserve_by_origin(y, mu)
  list(model = model, mu = mu,
       by_origin = by_origin, total = reserve_totals(by_origin),
       reserve_o = by_origin$ibnr, reserve = sum(by_origin$ibnr),
       deviance = poisson_deviance(y, mu), epochs = as.integer(epochs),
       history = if (monitor) as.data.frame(do.call(rbind, rows)) else NULL,
       scale = odp$scale)
}


#' Early-stopping analysis on the 50/50 claims split (Paper C, Section 3.3.2)
#'
#' Fits the ccODP model to the training triangle, starts a bCCNN there and
#' trains it on the training triangle for max_epochs, recording after every
#' step the deviance on the training triangle (in-sample) and on the
#' validation triangle (out-of-sample; Paper C Figure 2). The step with the
#' lowest validation deviance is the number of gradient-descent steps for the
#' final fit (Paper C found 300 for its 12 x 12 triangles); 0 means the
#' network never beat the ccODP model.
#'
#' @param train,vali observed upper triangles of the two halves
#'   (triangle_sets()$train, $vali), in currency units.
#' @param max_epochs length of the run; Paper C: 1000.
#' @param scale,phi passed to fit_odp_glm().
#' @param ... passed to fit_bccnn() and bccnn_model().
#' @return a list: history (epoch, train_dropout, train, vali), best_epoch,
#'   decrease (relative decrease of the train and vali deviance from the
#'   ccODP start to best_epoch; Paper C Table 3), odp (the training fit).
bccnn_validation <- function(train, vali, max_epochs = 1000, scale = 1,
                             phi = "deviance", ...) {
  odp <- fit_odp_glm(train, scale = scale, phi = phi)
  n <- length(odp$alpha)
  vali <- unname(as.matrix(vali)) / scale
  vali[fut_mask(n)] <- NA
  nn <- fit_bccnn(odp, epochs = max_epochs, track = list(vali = vali), ...)
  h <- nn$history
  best <- as.integer(h$epoch[which.min(h$vali)])
  at <- function(e) h[h$epoch == e, ]
  list(history = h, best_epoch = best,
       decrease = c(train = 1 - at(best)$train / at(0)$train,
                    vali  = 1 - at(best)$vali  / at(0)$vali),
       odp = odp)
}


#' bCCNN dispersion estimate (Paper C, Section 3.3.2)
#'
#' The ccODP estimate (5) assumes MLE with a known number of parameters, which
#' does not hold for an early-stopped network with dropout. Paper C instead
#' reduces the ccODP dispersion by the relative decrease of the validation
#' loss, when that decrease is positive.
#'
#' @param phi_odp ccODP dispersion of the full triangle.
#' @param decrease_vali bccnn_validation()$decrease[["vali"]].
bccnn_phi <- function(phi_odp, decrease_vali) {
  phi_odp * (1 - max(0, decrease_vali))
}


#' Calibrate the bCCNN model on one triangle as in Paper C
#'
#' 1. early-stopping analysis on the 50/50 claims split (bccnn_validation());
#' 2. ccODP model on the full observed triangle (fit_odp_glm());
#' 3. bCCNN started in that ccODP model and trained on the full triangle for
#'    the number of steps from 1 (Section 3.3.3). The deviance on the true
#'    lower triangle is recorded after every step for back-testing only.
#'
#' @param sets triangle_sets() result.
#' @param scale,phi passed to fit_odp_glm().
#' @param max_epochs length of the validation run.
#' @param epochs NULL (default) uses the validation run's best step; a number
#'   overrides it (the validation run is still done, for Figure 2, Table 3 and
#'   the dispersion).
#' @param ... passed to fit_bccnn() and bccnn_model() (batch_size, q, dropout,
#'   activation, trainable_embeddings, learning_rate, rho, epsilon, seed).
#' @return a list: validation, odp, nn, epochs, phi (c(ccODP, bCCNN)), scale.
bccnn_calibrate <- function(sets, scale = 1, phi = "deviance",
                            max_epochs = 1000, epochs = NULL, ...) {
  validation <- bccnn_validation(sets$train, sets$vali, max_epochs = max_epochs,
                                 scale = scale, phi = phi, ...)
  steps <- if (is.null(epochs)) validation$best_epoch else as.integer(epochs)
  odp <- fit_odp_glm(sets$upper, scale = scale, phi = phi)
  test <- unname(as.matrix(sets$test)) / scale
  nn <- fit_bccnn(odp, epochs = steps, track = list(test = test), ...)
  list(validation = validation, odp = odp, nn = nn, epochs = steps,
       phi = c(ccODP = odp$phi,
               bCCNN = bccnn_phi(odp$phi, validation$decrease[["vali"]])),
       scale = scale)
}
