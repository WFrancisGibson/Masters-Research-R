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
# epoch is one gradient-descent step.
#
# The number of gradient-descent steps (early stopping) is chosen on held-out
# data, in one of two ways (bccnn_calibrate()):
#   * "rolling_origin" (default): Al-Mudafer, Avanzi, Taylor & Wong (2021),
#     Section 3.1: validation on the latest calendar periods of the triangle
#     (rolling_origin_sets()), plus test partitions at earlier valuation dates
#     that measure the model's forecast error (bccnn_rolling_origin());
#   * "claims_split": Paper C, Section 3.3.2, a 50/50 split of the individual
#     claims into training and validation triangles (bccnn_validation()).
# Then the network is refitted on the full triangle for exactly that many
# steps (Paper C, Section 3.3.3), or -- rolling origin only -- the network
# trained on the final partition's training cells is kept (Al-Mudafer et al.,
# Section 4.3).
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


#' Train a bCCNN model on (part of) an observed triangle
#'
#' Starts in the ccODP model `odp` (checked: the untrained network must
#' reproduce odp$mu) and runs `epochs` gradient-descent steps on the training
#' cells.
#'
#' @param odp fit_odp_glm() of the same triangle (and the same cells).
#' @param y observed incremental triangle, n x n, in the units of odp (already
#'   divided by odp$scale); its lower triangle is ignored. Default odp$y.
#' @param epochs number of epochs; with the default full batch, the number of
#'   gradient-descent steps. 0 returns the untrained network, i.e. the ccODP
#'   model.
#' @param cells n x n logical mask of the observed cells to train on; default
#'   odp$cells, i.e. the cells the ccODP start was fitted on.
#' @param batch_size NULL = full batch (all training cells), as Paper C.
#' @param track optional named list of n x n matrices in the units of y, NA
#'   outside the cells to score (e.g. validation cells, or the true lower
#'   triangle for back-testing). They are only recorded; they play no part in
#'   the fit.
#' @param monitor TRUE records, after every epoch, the Poisson deviance of the
#'   network in inference mode (no dropout) on the training cells and on each
#'   `track` matrix (plus <track>_pred, the sum of the means over its cells),
#'   and Keras's training loss (computed with dropout, before that epoch's
#'   update) as a deviance. This needs one prediction per epoch.
#' @param keep_mu TRUE also keeps the n x n means after every epoch (needs
#'   monitor), so a model early-stopped at any epoch can be read off.
#' @param verbose Keras verbosity.
#' @param ... passed to bccnn_model() (q, dropout, activation, ..., seed).
#' @return a list: model (weights after the last epoch); mu (n x n fitted and
#'   predicted means); by_origin, total, reserve_o, reserve (reserves, units of
#'   y); deviance (on the training cells, phi = 1); epochs; cells; history
#'   (data.frame: epoch, train_dropout, train, one column per track and per
#'   <track>_pred; epoch 0 is the ccODP start) or NULL; mu_path (n x n x
#'   (epochs + 1) array, epoch k in slice k + 1) or NULL; scale.
fit_bccnn <- function(odp, y = odp$y, epochs, cells = odp$cells,
                      batch_size = NULL, track = NULL, monitor = TRUE,
                      keep_mu = FALSE, verbose = 0, ...) {
  n <- length(odp$alpha)
  y <- unname(as.matrix(y))
  if (!identical(dim(y), c(n, n))) {
    stop("fit_bccnn(): y must be ", n, " x ", n, call. = FALSE)
  }
  y[fut_mask(n)] <- NA
  if (is.null(cells)) cells <- !fut_mask(n)
  cells <- unname(as.matrix(cells))
  if (!identical(dim(cells), c(n, n)) || !is.logical(cells) || anyNA(cells) ||
        any(cells & fut_mask(n)) || anyNA(y[cells])) {
    stop("fit_bccnn(): cells must be an n x n logical mask of observed cells",
         call. = FALSE)
  }
  if (keep_mu && !monitor) {
    stop("fit_bccnn(): keep_mu needs monitor = TRUE", call. = FALSE)
  }
  all_cells <- triangle_long(y)
  fit_idx <- which(as.vector(cells))
  x_fit <- bccnn_inputs(all_cells$origin[fit_idx], all_cells$dev[fit_idx])
  y_fit <- matrix(all_cells$value[fit_idx], ncol = 1)
  x_all <- bccnn_inputs(all_cells$origin, all_cells$dev)

  if (!is.null(track)) {
    reserved <- c("", "epoch", "train", "train_dropout")
    if (is.null(names(track)) || any(names(track) %in% reserved) ||
          any(grepl("_pred$", names(track)))) {
      stop("fit_bccnn(): track must be a list with (new) names", call. = FALSE)
    }
    track <- lapply(track, function(t) unname(as.matrix(t)))
    if (!all(vapply(track, function(t) identical(dim(t), c(n, n)), logical(1)))) {
      stop("fit_bccnn(): every track matrix must be ", n, " x ", n, call. = FALSE)
    }
  }
  scored <- c(list(train = ifelse(cells, y, NA)), track)

  model <- bccnn_model(odp, ...)
  # the Python method takes the R list of inputs as a Python list; keras3's
  # predict_on_batch() wrapper would turn the list into an array first
  mu_of <- function() {
    matrix(as.numeric(model$predict_on_batch(x_all)), n, n)
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
  mu_path <- if (keep_mu) array(NA_real_, c(n, n, epochs + 1L)) else NULL
  record <- function(epoch, loss, mu) {
    rows[[length(rows) + 1L]] <<-
      c(epoch = epoch,
        train_dropout = keras_poisson_to_deviance(loss, y_fit),
        vapply(scored, poisson_deviance, numeric(1), mu = mu),
        stats::setNames(vapply(track, function(t) sum(mu[!is.na(t)]), numeric(1)),
                        paste0(names(track), "_pred")))
    if (keep_mu) mu_path[, , epoch + 1L] <<- mu
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
    model |> fit(x = x_fit, y = y_fit, epochs = as.integer(epochs),
                 batch_size = as.integer(if (is.null(batch_size)) nrow(y_fit) else batch_size),
                 callbacks = callbacks, verbose = verbose, view_metrics = FALSE)
    mu <- mu_of()
  }
  dimnames(mu) <- list(origin = seq_len(n), dev = seq_len(n))

  by_origin <- reserve_by_origin(y, mu)
  list(model = model, mu = mu,
       by_origin = by_origin, total = reserve_totals(by_origin),
       reserve_o = by_origin$ibnr, reserve = sum(by_origin$ibnr),
       deviance = poisson_deviance(scored$train, mu),
       epochs = as.integer(epochs), cells = cells,
       history = if (monitor) as.data.frame(do.call(rbind, rows)) else NULL,
       mu_path = mu_path, scale = odp$scale)
}


#' Relative decrease of the losses from the ccODP start to a given step
#'
#' Paper C, Table 3, from a fit_bccnn() history with a "vali" column:
#' train (no dropout) and vali compare step with step 0 (the ccODP start);
#' train_dropout compares Keras's training loss (Paper C Figure 2, rough
#' because of dropout), averaged over steps within `window` of `step`, with
#' its value at step 1 (computed at the start weights, so the ccODP loss).
#'
#' @param history fit_bccnn()$history with columns epoch, train, vali,
#'   train_dropout.
#' @param step the step (epoch) to evaluate; must be in history.
#' @param window half-width of the train_dropout average.
loss_decrease <- function(history, step, window = 10) {
  if (!step %in% history$epoch) {
    stop("loss_decrease(): step ", step, " is not in the history", call. = FALSE)
  }
  at <- function(col, e) history[[col]][history$epoch == e]
  near <- history$epoch >= max(1, step - window) &
    history$epoch <= max(1, step + window)
  c(train = 1 - at("train", step) / at("train", 0),
    vali = 1 - at("vali", step) / at("vali", 0),
    train_dropout = if (max(history$epoch) >= 1) {
      1 - mean(history$train_dropout[near]) / at("train_dropout", 1)
    } else NA_real_)
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
#' The split assumes the training ccODP parameters carry over to the
#' validation half. Where the training half has no payments at all in an
#' accident or development period (on the annual data: the sparse
#' development periods 19 and 20), its ccODP effect is -Inf and nothing
#' carries over, so those validation cells are left out of the validation
#' loss (an adaptation of Paper C, which did not meet this case).
#'
#' @param train,vali observed upper triangles of the two halves
#'   (triangle_sets()$train, $vali), in currency units.
#' @param max_epochs length of the run; Paper C: 1000.
#' @param scale,phi passed to fit_odp_glm().
#' @param ... passed to fit_bccnn() and bccnn_model().
#' @return a list: method, history (epoch, train_dropout, train, vali,
#'   vali_pred), best_epoch, decrease (loss_decrease() at best_epoch; Paper C
#'   Table 3), odp (the training fit), excluded (periods left out of vali).
bccnn_validation <- function(train, vali, max_epochs = 1000, scale = 1,
                             phi = "deviance", ...) {
  odp <- withCallingHandlers(
    fit_odp_glm(train, scale = scale, phi = phi),
    warning = function(w) {
      if (grepl("no payments", conditionMessage(w))) invokeRestart("muffleWarning")
    })
  n <- length(odp$alpha)
  vali <- unname(as.matrix(vali)) / scale
  vali[fut_mask(n)] <- NA
  vali[odp$zero_origin, ] <- NA
  vali[, odp$zero_dev] <- NA
  excluded <- list(origin = which(odp$zero_origin), dev = which(odp$zero_dev))
  if (length(unlist(excluded)) > 0) {
    message("bccnn_validation(): the training half has no payments in ",
            "development period(s) ", paste(excluded$dev, collapse = ", "),
            if (length(excluded$origin)) paste0(" / accident period(s) ",
                                               paste(excluded$origin, collapse = ", ")),
            "; those validation cells are left out of the validation loss")
  }
  nn <- fit_bccnn(odp, epochs = max_epochs, track = list(vali = vali), ...)
  h <- nn$history
  best <- as.integer(h$epoch[which.min(h$vali)])
  list(method = "claims_split", history = h, best_epoch = best,
       decrease = loss_decrease(h, best), odp = odp, excluded = excluded)
}


#' Early stopping (and test error) on one rolling-origin partition
#'
#' Al-Mudafer et al. (2021), Sections 3.1 and 4. Fits the ccODP model on the
#' partition's training cells, starts a bCCNN there, trains it on the training
#' cells for max_epochs while recording the deviance on the validation cells
#' (and, for a test partition, on its test cells), and stops at the step with
#' the lowest validation deviance. The recorded test deviance at that step is
#' the test error of the early-stopped network (Keras's EarlyStopping with
#' the best weights restored; Al-Mudafer et al. use patience 1000). The
#' benchmark is the chain ladder (ccODP) fitted on all the partition's cells,
#' i.e. at the partition's valuation date.
#'
#' @param part one element of rolling_origin_sets().
#' @param truth optional n x n true lower triangle in units of scale, recorded
#'   for back-testing only (final partition).
#' @param max_epochs length of the run.
#' @param scale,phi passed to fit_odp_glm().
#' @param keep_mu keep the means after every step (see fit_bccnn()).
#' @param ... passed to fit_bccnn() and bccnn_model().
#' @return a list: origin, final, n_train, n_vali, n_test, history,
#'   best_epoch, decrease (loss_decrease() at best_epoch), odp (the training
#'   cells' fit), test (test-set summary, test partitions only), mu_path.
bccnn_ro_partition <- function(part, truth = NULL, max_epochs = 1000,
                               scale = 1, phi = "deviance", keep_mu = FALSE,
                               ...) {
  odp <- fit_odp_glm(part$y, scale = scale, phi = phi, cells = part$train)
  track <- list(vali = ifelse(part$vali, odp$y, NA))
  if (!is.null(part$test)) track$test <- unname(part$test) / scale
  if (!is.null(truth)) track$truth <- unname(as.matrix(truth))
  nn <- fit_bccnn(odp, epochs = max_epochs, track = track, keep_mu = keep_mu, ...)
  h <- nn$history
  best <- as.integer(h$epoch[which.min(h$vali)])
  out <- list(origin = part$origin, final = part$final,
              n_train = sum(part$train), n_vali = sum(part$vali),
              n_test = if (is.null(part$test)) 0L else sum(!is.na(part$test)),
              history = h, best_epoch = best,
              decrease = loss_decrease(h, best), odp = odp, test = NULL,
              mu_path = nn$mu_path)
  if (!is.null(part$test)) {
    cl <- fit_odp_glm(part$y, scale = scale, phi = phi)   # chain ladder at c
    at <- function(col) h[[col]][h$epoch == best]
    out$test <- c(actual = sum(track$test, na.rm = TRUE),
                  ccODP_pred = sum(cl$mu[!is.na(track$test)]),
                  bCCNN_pred = at("test_pred"),
                  ccODP_dev = poisson_deviance(track$test, cl$mu),
                  bCCNN_dev = at("test"))
  }
  out
}


#' Rolling-origin calibration and test error of the bCCNN model
#'
#' Al-Mudafer et al. (2021), Sections 3.1 and 4.1: runs bccnn_ro_partition()
#' on every partition of rolling_origin_sets(). The test error of the model
#' design is the cell-weighted average over the test partitions of the
#' per-cell test loss (their eq. (4.4)); here the loss is the Poisson
#' deviance, the bCCNN's training loss, and the same is reported for the
#' chain ladder. Al-Mudafer et al. average (4.2)-(4.3) over several
#' initialisations; the bCCNN starts deterministically in the ccODP model, so
#' one run per partition is used.
#'
#' @param parts rolling_origin_sets() result.
#' @param truth optional true lower triangle (units of scale), recorded in the
#'   final partition for back-testing only.
#' @param max_epochs,scale,phi passed to bccnn_ro_partition().
#' @param keep_mu_final keep the final partition's means after every step.
#' @param ... passed to fit_bccnn() and bccnn_model().
#' @return a list: fits (one bccnn_ro_partition() result per partition),
#'   summary (data.frame, one row per partition), test_error (per test cell,
#'   c(ccODP, bCCNN)), final (the final partition's fit).
bccnn_rolling_origin <- function(parts, truth = NULL, max_epochs = 1000,
                                 scale = 1, phi = "deviance",
                                 keep_mu_final = FALSE, ...) {
  fits <- lapply(parts, function(p) {
    bccnn_ro_partition(p, truth = if (p$final) truth, max_epochs = max_epochs,
                       scale = scale, phi = phi,
                       keep_mu = p$final && keep_mu_final, ...)
  })
  summary <- do.call(rbind, lapply(seq_along(fits), function(k) {
    f <- fits[[k]]
    t <- if (is.null(f$test)) {
      c(actual = NA, ccODP_pred = NA, bCCNN_pred = NA, ccODP_dev = NA,
        bCCNN_dev = NA)
    } else f$test
    data.frame(partition = if (f$final) "final" else as.character(k),
               origin = f$origin, n_train = f$n_train, n_vali = f$n_vali,
               n_test = f$n_test, best_epoch = f$best_epoch,
               test_actual = t[["actual"]], test_ccODP = t[["ccODP_pred"]],
               test_bCCNN = t[["bCCNN_pred"]],
               test_loss_ccODP = t[["ccODP_dev"]],
               test_loss_bCCNN = t[["bCCNN_dev"]])
  }))
  tst <- summary[summary$partition != "final", ]
  test_error <- c(ccODP = sum(tst$test_loss_ccODP) / sum(tst$n_test),
                  bCCNN = sum(tst$test_loss_bCCNN) / sum(tst$n_test))
  list(fits = fits, summary = summary, test_error = test_error,
       final = fits[[length(fits)]])
}


#' bCCNN dispersion estimate (Paper C, Section 3.3.2)
#'
#' The ccODP estimate (5) assumes MLE with a known number of parameters, which
#' does not hold for an early-stopped network with dropout. Paper C instead
#' reduces the ccODP dispersion by the relative decrease of the validation
#' loss, when that decrease is positive.
#'
#' @param phi_odp ccODP dispersion of the full triangle.
#' @param decrease_vali relative decrease of the validation loss at the steps
#'   used (loss_decrease()[["vali"]]).
bccnn_phi <- function(phi_odp, decrease_vali) {
  phi_odp * (1 - max(0, decrease_vali))
}


#' Calibrate the bCCNN model on one triangle
#'
#' 1. early stopping on held-out data:
#'    * validation = "rolling_origin" (default): Al-Mudafer et al. (2021)
#'      rolling-origin partitions of the observed triangle
#'      (rolling_origin_sets(), bccnn_rolling_origin()); the number of steps
#'      comes from the final partition (validation on the latest calendar
#'      periods), and the test partitions give the forecast test error;
#'    * validation = "claims_split": Paper C's 50/50 claims split
#'      (bccnn_validation());
#' 2. ccODP model on the full observed triangle (fit_odp_glm());
#' 3. the reported bCCNN:
#'    * final_fit = "refit" (default, Paper C Section 3.3.3): started in that
#'      ccODP model and trained on the full triangle for the chosen number of
#'      steps; the deviance on the true lower triangle is recorded after every
#'      step for back-testing only;
#'    * final_fit = "partition" (Al-Mudafer et al. Section 4.3, rolling origin
#'      only): the network trained on the final partition's training cells,
#'      early-stopped at the chosen step (its $model is NULL: the Keras model
#'      holds the weights of the last step, not of the chosen one).
#'
#' @param sets triangle_sets() result.
#' @param scale,phi passed to fit_odp_glm().
#' @param max_epochs length of the early-stopping runs.
#' @param epochs NULL (default) uses the step with the lowest validation loss;
#'   a number (<= max_epochs) overrides it. The dispersion and Table 3 use the
#'   loss decrease at the steps actually used.
#' @param validation "rolling_origin" or "claims_split".
#' @param test_periods,vali_periods,exclude passed to rolling_origin_sets().
#' @param final_fit "refit" or "partition".
#' @param ... passed to fit_bccnn() and bccnn_model() (batch_size, q, dropout,
#'   activation, trainable_embeddings, learning_rate, rho, epsilon, seed).
#' @return a list: validation_method, final_fit, validation (the run that set
#'   the steps: history, best_epoch, ...), rolling_origin (partitions,
#'   summary, test_error; NULL for the claims split), decrease (at the steps
#'   used), odp, nn, epochs, phi (c(ccODP, bCCNN)), scale.
bccnn_calibrate <- function(sets, scale = 1, phi = "deviance",
                            max_epochs = 1000, epochs = NULL,
                            validation = c("rolling_origin", "claims_split"),
                            test_periods = c(5, 2), vali_periods = 2,
                            exclude = 2, final_fit = c("refit", "partition"),
                            ...) {
  validation <- match.arg(validation)
  final_fit <- match.arg(final_fit)
  truth <- unname(as.matrix(sets$test)) / scale
  ro <- NULL
  if (validation == "rolling_origin") {
    parts <- rolling_origin_sets(sets$upper, test_periods = test_periods,
                                 vali_periods = vali_periods, exclude = exclude)
    ro <- bccnn_rolling_origin(parts, truth = truth, max_epochs = max_epochs,
                               scale = scale, phi = phi,
                               keep_mu_final = final_fit == "partition", ...)
    ro$parts <- parts
    val <- ro$final
  } else {
    if (final_fit == "partition") {
      stop("bccnn_calibrate(): final_fit = \"partition\" needs ",
           "validation = \"rolling_origin\"", call. = FALSE)
    }
    val <- bccnn_validation(sets$train, sets$vali, max_epochs = max_epochs,
                            scale = scale, phi = phi, ...)
  }

  steps <- if (is.null(epochs)) val$best_epoch else as.integer(epochs)
  if (steps > max(val$history$epoch)) {
    stop("bccnn_calibrate(): epochs = ", steps, " is longer than the ",
         "validation run (max_epochs = ", max(val$history$epoch), ")",
         call. = FALSE)
  }
  decrease <- loss_decrease(val$history, steps)
  odp <- fit_odp_glm(sets$upper, scale = scale, phi = phi)

  if (final_fit == "refit") {
    nn <- fit_bccnn(odp, epochs = steps, track = list(truth = truth), ...)
  } else {
    mu <- val$mu_path[, , steps + 1L]
    dimnames(mu) <- dimnames(odp$mu)
    by_origin <- reserve_by_origin(odp$y, mu)
    nn <- list(model = NULL, mu = mu,
               by_origin = by_origin, total = reserve_totals(by_origin),
               reserve_o = by_origin$ibnr, reserve = sum(by_origin$ibnr),
               deviance = poisson_deviance(odp$y, mu), epochs = steps,
               cells = val$odp$cells, history = val$history, mu_path = NULL,
               scale = scale)
    ro$fits[[length(ro$fits)]]$mu_path <- NULL
    ro$final$mu_path <- NULL
    val$mu_path <- NULL
  }
  list(validation_method = validation, final_fit = final_fit,
       validation = val, rolling_origin = ro, decrease = decrease,
       odp = odp, nn = nn, epochs = steps,
       phi = c(ccODP = odp$phi, bCCNN = bccnn_phi(odp$phi, decrease[["vali"]])),
       scale = scale)
}
