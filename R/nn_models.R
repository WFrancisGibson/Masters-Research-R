##################################################################
#########  bCCNN: neural network embedding of the ccODP model
#########  Gabrielli, Richman & Wuthrich (2020), Paper C
#########  early stopping: rolling origin (Al-Mudafer et al. 2021)
#########                  or the 50/50 claims split (Paper C)
##################################################################
#
# mu(i, j) = exp{ w * (alpha_i + beta_j) + c + <B, z3(i, j)> }     (13)
#
# alpha_i, beta_j: ccODP estimates, fixed embeddings (skip connection)
# z3: three tanh hidden layers (20, 15, 10), 10% dropout after each
# start: w = 1, c = c_ODP, B = 0, i.e. exactly the ccODP model     (14)
# loss "poisson", optimiser rmsprop, full batch (1 epoch = 1 step)


###############################################
#########  network architecture
###############################################

# Keras inputs: 0-based accident and development years of the cells
bccnn_inputs <- function(origin, dev) {
  list(as.matrix(origin - 1L), as.matrix(dev - 1L))
}

bccnn_model <- function(odp,
                        q = c(20, 15, 10),
                        dropout = 0.1,
                        activation = "tanh",
                        trainable_embeddings = FALSE,
                        learning_rate = 0.001,
                        rho = 0.9,
                        epsilon = 1e-7,
                        seed = 2026) {
  n <- length(odp$alpha)
  clear_session()
  set_random_seed(seed)

  acc_year <- layer_input(shape = c(1), dtype = "int32", name = "AccYear")
  dev_year <- layer_input(shape = c(1), dtype = "int32", name = "DevYear")

  ay_embed <- acc_year |>
    layer_embedding(input_dim = n, output_dim = 1, name = "AY_embed",
                    trainable = trainable_embeddings) |>
    layer_flatten(name = "AY_flat")

  dy_embed <- dev_year |>
    layer_embedding(input_dim = n, output_dim = 1, name = "DY_embed",
                    trainable = trainable_embeddings) |>
    layer_flatten(name = "DY_flat")

  # the ccODP part: alpha_i + beta_j
  cc0 <- layer_add(list(ay_embed, dy_embed), name = "cc0")

  # one hidden layer per element of q (Paper C: three), dropout after each
  nn0 <- list(ay_embed, dy_embed) |>
    layer_concatenate(name = "concate0")
  for (l in seq_along(q)) {
    nn0 <- nn0 |>
      layer_dense(units = q[l], activation = activation,
                  name = paste0("hidden", l)) |>
      layer_dropout(rate = dropout, name = paste0("dropout", l))
  }

  response <- list(cc0, nn0) |>
    layer_concatenate(name = "concate1") |>
    layer_dense(units = 1, activation = "exponential", name = "Response")

  model <- keras_model(inputs = list(acc_year, dev_year), outputs = response)

  # start exactly in the ccODP model
  get_layer(model, "AY_embed") |> set_weights(list(as.matrix(odp$alpha)))
  get_layer(model, "DY_embed") |> set_weights(list(as.matrix(odp$beta)))
  get_layer(model, "Response") |>
    set_weights(list(as.matrix(c(1, rep(0, q[length(q)]))), array(odp$c)))

  model |> compile(loss = "poisson",
                   optimizer = optimizer_rmsprop(learning_rate = learning_rate,
                                                 rho = rho, epsilon = epsilon))
  model
}


###############################################
#########  fitting, recording the losses
###############################################

# Trains the bCCNN started in `odp` for `epochs` steps on `cells` of y
# (units of odp). After every step it records the Poisson deviance (without
# dropout) on the training cells and on each matrix of `track` (NA outside
# the cells to score), the predicted sum over each `track` matrix, and
# Keras's training loss (with dropout) as a deviance. Epoch 0 = ccODP start.
fit_bccnn <- function(odp,
                      y = odp$y,
                      epochs,
                      cells = odp$cells,
                      track = list(),
                      keep_mu = FALSE,
                      batch_size = NULL, ...) {
  n <- length(odp$alpha)
  cell <- triangle_long(y)
  x_all <- bccnn_inputs(cell$origin, cell$dev)
  x_fit <- bccnn_inputs(cell$origin[cells], cell$dev[cells])
  y_fit <- as.matrix(y[cells])
  scored <- c(list(train = ifelse(cells, y, NA)), track)

  model <- bccnn_model(odp, ...)
  predict_mu <- function() matrix(model$predict_on_batch(x_all), n, n)

  history <- NULL
  mu_path <- list()
  record <- function(epoch, loss) {
    mu <- predict_mu()
    if (keep_mu) mu_path[[epoch + 1]] <<- mu
    pred <- lapply(track, function(t) sum(mu[!is.na(t)]))
    names(pred) <- paste0(names(track), "_pred", recycle0 = TRUE)
    row <- data.frame(epoch = epoch,
                      train_dropout = keras_poisson_to_deviance(loss, y_fit),
                      c(lapply(scored, poisson_deviance, mu = mu), pred))
    history <<- rbind(history, row)
  }

  record(0, NA)
  step <- 0
  after_step <- callback_lambda(on_epoch_end = function(epoch, logs) {
    step <<- step + 1
    record(step, logs$loss)
  })
  if (epochs > 0) {
    model |> fit(x_fit, y_fit, epochs = as.integer(epochs),
                 batch_size = batch_size %||% nrow(y_fit),
                 callbacks = list(after_step),
                 verbose = 0, view_metrics = FALSE)
  }

  mu <- predict_mu()
  dimnames(mu) <- list(origin = 1:n, dev = 1:n)
  by_origin <- reserve_by_origin(y, mu)
  list(model = model, mu = mu, by_origin = by_origin,
       total = reserve_totals(by_origin),
       reserve_o = by_origin$ibnr, reserve = sum(by_origin$ibnr),
       deviance = poisson_deviance(scored$train, mu), epochs = epochs,
       cells = cells, history = history, mu_path = mu_path, scale = odp$scale)
}

# relative decrease of the losses from the ccODP start to `step` (Paper C
# Table 3). Keras's training loss of epoch e is computed before that epoch's
# update, i.e. after e - 1 steps: average it over epochs step + 1 +- window
# (fewer near the start, so step 0 gives 0)
loss_decrease <- function(h, step, window = 10) {
  at <- function(col, e) h[[col]][h$epoch == e]
  w <- min(window, step)
  near <- h$epoch >= step + 1 - w & h$epoch <= step + 1 + w
  c(train = 1 - at("train", step) / at("train", 0),
    vali = 1 - at("vali", step) / at("vali", 0),
    train_dropout = if (step == 0) 0 else
      1 - mean(h$train_dropout[near]) / at("train_dropout", 1))
}

# bCCNN dispersion: the ccODP one reduced by the decrease of the validation
# loss (Paper C, Section 3.3.2)
bccnn_phi <- function(phi_odp, decrease_vali) {
  phi_odp * (1 - max(0, decrease_vali))
}


###############################################
#########  periods without payments
###############################################

# Sets to NA the cells of `m` in the accident and development periods that
# have no payments in the cells `fit` was fitted on. Their ccODP effect is
# -Inf (glm() reports about -30, fitted means ~e^-30), so a positive payment
# scored against them adds roughly 30 x payment to the deviance, and the
# network's embedding input of that period is far outside the range of the
# others: nothing fitted on those cells carries over to them. Not in Paper C
# or Harkonen (2021), whose triangles have payments in every period.
mask_zero_periods <- function(m, fit) {
  if (is.null(m)) return(m)
  stopifnot(nrow(m) == length(fit$zero_origin),
            ncol(m) == length(fit$zero_dev))
  m[fit$zero_origin, ] <- NA
  m[, fit$zero_dev] <- NA
  m
}


###############################################
#########  early stopping 1: 50/50 claims split
###############################################

# Paper C, Section 3.3.2: ccODP and bCCNN fitted on the training half, the
# step with the lowest deviance on the validation half is kept
bccnn_validation <- function(train,
                             vali,
                             max_epochs = 1000,
                             scale = 1,
                             phi = "deviance", ...) {
  odp <- suppressWarnings(fit_odp_glm(train, scale = scale, phi = phi))
  # no payments in the training half (tail development years): leave these
  # validation cells out (mask_zero_periods())
  vali <- mask_zero_periods(upper(vali / scale), odp)

  h <- fit_bccnn(odp, epochs = max_epochs, track = list(vali = vali),
                 ...)$history
  best <- h$epoch[which.min(h$vali)]
  list(method = "claims_split", history = h, best_epoch = best,
       decrease = loss_decrease(h, best), odp = odp)
}


###############################################
#########  early stopping 2: rolling origin
###############################################

# One partition of rolling_origin_sets() (Al-Mudafer et al. 2021): ccODP and
# bCCNN fitted on the training cells, the step with the lowest validation
# deviance is kept. A test partition also scores the procedure that gives
# the reported model ("refit": bCCNN from the chain ladder at the valuation
# date, all cells, `best` steps; "partition": the early-stopped network),
# next to the chain ladder at that date and the ccODP on the training cells.
# Periods without payments (mask_zero_periods()): validation cells in a
# period with no payments in the training cells are left out of the stopping
# rule, as in the claims split; test cells in a period with no payments in
# any cell observed at the valuation date are left out of the test error (no
# model fitted at that date can forecast them). Test cells in a period that
# has payments only in the validation cells stay in: the chain ladder at
# that date does know that period, so a procedure that loses it is scored
# for it. n_vali and n_test count the cells scored.
bccnn_ro_partition <- function(part,
                               truth = NULL,
                               max_epochs = 1000,
                               scale = 1,
                               phi = "deviance",
                               final_fit = "refit",
                               keep_mu = FALSE, ...) {

  odp <- fit_odp_glm(part$y, scale = scale, phi = phi, cells = part$train)
  # chain ladder at the valuation date c (all cells observed at c)
  cl <- if (!part$final) fit_odp_glm(part$y, scale = scale, phi = phi)

  track <- list(vali = mask_zero_periods(ifelse(part$vali, odp$y, NA), odp))

  if (!part$final) track$test <- mask_zero_periods(part$test / scale, cl)
  track$truth <- truth

  nn <- fit_bccnn(odp, epochs = max_epochs, track = track, keep_mu = keep_mu,
                  ...)
  h <- nn$history
  best <- h$epoch[which.min(h$vali)]
  out <- list(origin = part$origin,
              final = part$final,
              n_train = sum(part$train),
              n_vali = sum(!is.na(track$vali)),
              n_test = sum(!is.na(track$test)),
              history = h,
              best_epoch = best,
              decrease = loss_decrease(h, best),
              odp = odp,
              mu_path = nn$mu_path,
              test = NULL)

  if (!part$final) {
    at <- function(col, e) h[[col]][h$epoch == e]
    if (final_fit == "refit") {
      rf <- fit_bccnn(cl, epochs = best, track = list(test = track$test),
                      ...)$history
      nn_dev <- tail(rf$test, 1)
      nn_pred <- tail(rf$test_pred, 1)
    } else {
      nn_dev <- at("test", best)
      nn_pred <- at("test_pred", best)
    }
    out$test <- c(test_actual = sum(track$test, na.rm = TRUE),
                  test_ccODP = sum(cl$mu[!is.na(track$test)]),
                  test_ccODP_train = at("test_pred", 0),
                  test_bCCNN = nn_pred,
                  test_loss_ccODP = poisson_deviance(track$test, cl$mu),
                  test_loss_ccODP_train = at("test", 0),
                  test_loss_bCCNN = nn_dev)
  }
  out
}

# All partitions; test error = test deviance per test cell over the test
# partitions (Al-Mudafer et al. eq. (4.4)). One run per partition: the
# results depend on the seed (random hidden layers and dropout).
bccnn_rolling_origin <- function(parts,
                                 truth = NULL,
                                 max_epochs = 1000,
                                 scale = 1,
                                 phi = "deviance",
                                 final_fit = "refit",
                                 keep_mu_final = FALSE,
                                 ...) {
  fits <- lapply(parts, function(p) {
    bccnn_ro_partition(p, truth = if (p$final) truth, max_epochs = max_epochs,
                       scale = scale, phi = phi, final_fit = final_fit,
                       keep_mu = p$final && keep_mu_final, ...)
  })

  no_test <- c(test_actual = NA, test_ccODP = NA, test_ccODP_train = NA,
               test_bCCNN = NA, test_loss_ccODP = NA,
               test_loss_ccODP_train = NA, test_loss_bCCNN = NA)
  summary <- do.call(rbind, lapply(seq_along(fits), function(k) {
    f <- fits[[k]]
    data.frame(partition = if (f$final) "final" else as.character(k),
               origin = f$origin, n_train = f$n_train, n_vali = f$n_vali,
               n_test = f$n_test, best_epoch = f$best_epoch,
               as.list(if (f$final) no_test else f$test))
  }))

  tst <- summary[summary$partition != "final", ]
  test_error <- c(ccODP = sum(tst$test_loss_ccODP),
                  ccODP_train = sum(tst$test_loss_ccODP_train),
                  bCCNN = sum(tst$test_loss_bCCNN)) / sum(tst$n_test)
  list(fits = fits, summary = summary, test_error = test_error,
       final_fit = final_fit, final = fits[[length(fits)]])
}


###############################################
#########  calibration of the bCCNN
###############################################

# 1. early stopping (rolling origin or claims split) gives the number of steps
# 2. ccODP on the full observed triangle
# 3. final_fit "refit" (Paper C): bCCNN from that ccODP, trained on the full
#    triangle for those steps; "partition" (Al-Mudafer et al.): the
#    early-stopped network of the final rolling-origin partition
bccnn_calibrate <- function(sets, scale = 1, phi = "deviance",
                            max_epochs = 1000, epochs = NULL,
                            validation = "rolling_origin",
                            test_periods = c(5, 2), vali_periods = 2,
                            exclude = 2, final_fit = "refit", ...) {
  truth <- sets$test / scale
  ro <- NULL
  if (validation == "rolling_origin") {
    parts <- rolling_origin_sets(sets$upper, test_periods = test_periods,
                                 vali_periods = vali_periods, exclude = exclude)
    ro <- bccnn_rolling_origin(parts, truth = truth, max_epochs = max_epochs,
                               scale = scale, phi = phi, final_fit = final_fit,
                               keep_mu_final = final_fit == "partition", ...)
    ro$parts <- parts
    val <- ro$final
  } else {
    val <- bccnn_validation(sets$train, sets$vali, max_epochs = max_epochs,
                            scale = scale, phi = phi, ...)
  }

  steps <- if (is.null(epochs)) val$best_epoch else epochs
  decrease <- loss_decrease(val$history, steps)
  odp <- fit_odp_glm(sets$upper, scale = scale, phi = phi)

  if (final_fit == "refit") {
    nn <- fit_bccnn(odp, epochs = steps, track = list(truth = truth), ...)
  } else {
    mu <- val$mu_path[[steps + 1]]
    by_origin <- reserve_by_origin(odp$y, mu)
    y_train <- ifelse(val$odp$cells, odp$y, NA)
    nn <- list(model = NULL, mu = mu, by_origin = by_origin,
               total = reserve_totals(by_origin),
               reserve_o = by_origin$ibnr, reserve = sum(by_origin$ibnr),
               deviance = poisson_deviance(y_train, mu),
               deviance_observed = poisson_deviance(odp$y, mu),
               epochs = steps, history = val$history)
  }

  list(validation_method = validation, final_fit = final_fit,
       validation = val, rolling_origin = ro, decrease = decrease,
       odp = odp, nn = nn, epochs = steps,
       phi = c(ccODP = odp$phi, bCCNN = bccnn_phi(odp$phi, decrease[["vali"]])),
       scale = scale)
}
