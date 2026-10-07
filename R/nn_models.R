##########################################
#########  bCCNN: neural network embedding of the ccODP model
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3, Listing 4;
#########  parametric bootstrap: Section 3.3.4
##########################################

## mu(i,j) = exp{w * (alpha_i + beta_j) + c + <B, z(i,j)>} (13):
## skip connection cc0 plus the network nn0,
## started in the ccODP model w = 1, c = c_ODP, B = 0 (14)
bccnn_model <- function(odp, param) {
  n <- length(odp$alpha)
  q0 <- param$hidden
  clear_session()
  set_random_seed(param$seed)
  #
  # declare AY and DY features to be categorical
  accyear <- layer_input(shape = c(1), dtype = "int32", name = "AccYear")
  devyear <- layer_input(shape = c(1), dtype = "int32", name = "DevYear")
  #
  # embedding layers for alpha_i and beta_j (fixed unless param$trainable)
  ay_embed <- accyear %>%
    layer_embedding(input_dim = n, output_dim = 1,
                    trainable = param$trainable,
                    name = "AY_embed") %>%
    layer_flatten(name = "AY_flat")
  dy_embed <- devyear %>%
    layer_embedding(input_dim = n, output_dim = 1,
                    trainable = param$trainable,
                    name = "DY_embed") %>%
    layer_flatten(name = "DY_flat")
  #
  # the ccODP part alpha_i + beta_j and the hidden layers of the NN part
  # (Paper C: 3), one per element of param$hidden, each followed by dropout
  cc0 <- list(ay_embed, dy_embed) %>% layer_add(name = "CC0")
  nn0 <- list(ay_embed, dy_embed) %>% layer_concatenate(name = "concate0")
  for (k in seq_along(q0)) {
    nn0 <- nn0 %>%
      layer_dense(units = q0[k],
                  activation = param$activation,
                  name = paste0("hidden", k)) %>%
      layer_dropout(rate = param$dropout,
                    name = paste0("dropout", k))
  }
  #
  # the bCCNN with the skip connection for the CC part
  response <- list(cc0, nn0) %>%
    layer_concatenate(name = "concate1") %>%
    layer_dense(units = 1,
                activation = "exponential",
                name = "Response")
  model <- keras_model(inputs = list(accyear, devyear), outputs = response)
  #
  # start exactly in the ccODP model (14): alpha_i, beta_j in the embeddings;
  # Response weights 1 on CC0 (w = 1) and 0 on the neurons of the last hidden
  # layer (B = 0), bias c = c_ODP
  get_layer(model, "AY_embed") %>% set_weights(list(as.matrix(odp$alpha)))
  get_layer(model, "DY_embed") %>% set_weights(list(as.matrix(odp$beta)))
  get_layer(model, "Response") %>%
    set_weights(list(as.matrix(c(1, rep(0, q0[length(q0)]))),
                     array(odp$intercept)))
  #
  # Keras optimiser param$optimizer (Paper C: rmsprop), as the NN chain ladder
  model %>% compile(loss = "poisson", optimizer = nncl_optimizer(param))
  model
}

## trains the bCCNN started in odp for 'epochs' gradient descent steps on the
## cells odp was fitted on, and keeps the predicted triangle after every step
## (epoch 0 = ccODP start); training times in seconds (own addition): per
## epoch in history, of the whole fit in time
bccnn_fit <- function(odp, epochs, param, track) {
  y <- odp$y
  cells <- odp$cells
  n <- nrow(y)
  # accident and development period of each cell, from 0 for the embedding
  # layers; x_all runs over all n x n cells column by column, as matrix()
  # fills them back
  x_all <- list(as.matrix(as.vector(row(y)) - 1L),
                as.matrix(as.vector(col(y)) - 1L))
  x_fit <- list(as.matrix(row(y)[cells] - 1L),
                as.matrix(col(y)[cells] - 1L))
  y_fit <- as.matrix(y[cells])
  #
  t0 <- Sys.time()
  model <- bccnn_model(odp, param)
  time_build <- as.numeric(Sys.time() - t0, units = "secs")
  mu_hat <- function() {
    matrix(model$predict_on_batch(x_all),
           n,
           n,
           dimnames = list(origin = 1:n, dev = 1:n))
  }
  # after every gradient descent step keep the predicted triangle and
  # Keras's loss, the seconds of the step (time) and of the prediction of
  # the triangle (time_predict); epoch 0: no step, the first prediction
  step_start <- Sys.time()
  mu_path <- list(mu_hat())
  loss <- NA
  time <- NA_real_
  time_predict <- as.numeric(Sys.time() - step_start, units = "secs")
  after_step <- callback_lambda(
    on_epoch_begin = function(epoch, logs) {
      step_start <<- Sys.time()
    },
    on_epoch_end = function(epoch, logs) {
      step_end <- Sys.time()
      mu_path[[length(mu_path) + 1]] <<- mu_hat()
      predict_end <- Sys.time()
      loss[length(loss) + 1] <<- logs$loss
      time[length(time) + 1] <<-
        as.numeric(step_end - step_start, units = "secs")
      time_predict[length(time_predict) + 1] <<-
        as.numeric(predict_end - step_end, units = "secs")
    }
  )
  batch_size <- if (is.null(param$batch_size)) nrow(y_fit) else
    param$batch_size
  fit_start <- Sys.time()
  if (epochs > 0) {
    model %>% fit(x_fit, y_fit,
                  epochs = as.integer(epochs),
                  batch_size = batch_size,
                  callbacks = list(after_step),
                  verbose = 0,
                  view_metrics = FALSE)
  }
  time_fit <- as.numeric(Sys.time() - fit_start, units = "secs")
  # Keras's callback holds the two R functions above and with them this call
  # (the network, the triangle after every step), and the call would hold
  # the callback: neither could be freed, the memory of the R session would
  # grow with every fit
  after_step <- NULL
  # deviance losses by step: Keras's training loss (with dropout), the
  # deviance without dropout on the training cells and on each matrix of
  # 'track' (NA = cell not scored), and the predicted sum over each matrix
  # of 'track'
  history <- data.frame(epoch = seq_along(mu_path) - 1,
                        train_dropout = keras_to_deviance(loss, y_fit))
  scored <- c(list(train = ifelse(cells, y, NA)), track)
  for (k in names(scored)) {
    history[[k]] <- sapply(mu_path, poisson_deviance, y = scored[[k]])
  }
  for (k in names(track)) {
    obs <- !is.na(track[[k]])
    history[[paste0(k, "_pred")]] <- sapply(mu_path, function(mu) sum(mu[obs]))
  }
  history$time <- time
  history$time_predict <- time_predict
  mu <- mu_hat()
  # build: bccnn_model(), which also starts Python for the first network of
  # an R session; fit: the Keras fit, the steps and their predictions;
  # total: this function
  list(model = model,
       mu = mu,
       history = history,
       mu_path = mu_path,
       time = c(build = time_build,
                fit = time_fit,
                total = as.numeric(Sys.time() - t0, units = "secs")))
}

## seconds per epoch of a fit (history of bccnn_fit()) with its partition
## and fit ("early_stop" or "refit"): rows of the per-epoch times of a run
epoch_time <- function(partition, fit, history) {
  data.frame(partition = partition,
             fit = fit,
             history[c("epoch", "time", "time_predict")])
}

## the per-epoch times in whole milliseconds: the files of the runs of a
## grid stay small
epoch_ms <- function(x) {
  x$time <- as.integer(round(1000 * x$time))
  x$time_predict <- as.integer(round(1000 * x$time_predict))
  x
}

## the per-epoch times of the fits of a run in a compact form (the grid):
## mean milliseconds of a step (time) and of the prediction of the triangle
## (time_predict) per block of 'size' epochs of each fit, x as epoch_time()
## with the steps of the fit; block 0 is the prediction of the start
epoch_blocks <- function(x, size) {
  x$block <- ceiling(x$epoch / size)
  blocks <- aggregate(1000 * x[c("time", "time_predict")],
                      x[c("block", "steps", "fit", "partition")],
                      mean)
  blocks$time <- round(blocks$time, 2)
  blocks$time_predict <- round(blocks$time_predict, 2)
  blocks[c("partition", "fit", "steps", "block", "time", "time_predict")]
}

## Paper C Section 3.3.2 reads "roughly 300 iterations" off its Figure 2 and
## uses them for every LoB; here the step with the lowest validation loss of
## the network of "bCCNN fit.R" to the nearest multiple of 'to' (a half goes
## up): one number of steps for all runs of a data set
fixed_steps <- function(best_epoch, to) {
  to * floor(best_epoch / to + 0.5)
}

## the steps each stopping rule reads off the validation losses of a run
## (config.yml bccnn$stopping; own design: the rules of the three papers on
## the same run); vali[1] is the loss at step 0, the ccODP start, vali[e + 1]
## the loss after e steps; a diverged network (losses not finite) breaks no
## rule, its losses are never the lowest
stopping_steps <- function(vali, stop_cfg, minimum_epochs, fixed) {
  n <- length(vali)
  # minimum: the lowest loss within the first minimum_epochs steps, the rule
  # of "bCCNN fit.R"
  minimum <- which.min(vali[1:(minimum_epochs + 1)]) - 1
  # moving_average (Harkonen 2021 Section 3.2): the lowest central moving
  # average of the losses over stop_cfg$window steps, found as the lowest
  # sum of a window (of equal sums the first; their averages could differ
  # in the last bit). An even window takes one step more after its centre
  # than before (as R's filter()), and the steps at both ends, with no full
  # window around them, cannot be chosen: a window of 100 chooses among the
  # steps from 49 to the last but 50, never the ccODP start. No finite sum
  # at all: the start
  w <- stop_cfg$window
  window_sum <- as.numeric(filter(vali, rep(1, w), sides = 2))
  window_sum[!is.finite(window_sum)] <- NA
  moving_average <- if (all(is.na(window_sum))) 0 else
    which.min(window_sum) - 1
  # patience (Al-Mudafer et al. 2021 Section 4): training stops when the
  # loss has set no new low for stop_cfg$patience steps, and the step of the
  # last low is used, as Keras's early stopping with restored best weights
  # run from the start; never stopped: the lowest loss of the whole run
  finite <- ifelse(is.finite(vali), vali, Inf)
  low <- which(c(TRUE, finite[-1] < cummin(finite)[-n]))
  stopped <- which(diff(low) > stop_cfg$patience)
  patience <- low[c(stopped, length(low))[1]] - 1
  c(minimum = minimum,
    fixed = fixed,
    moving_average = moving_average,
    patience = patience)[unlist(stop_cfg$rules)]
}

## Paper C Section 3.3.4: the bCCNN refitted on the simulated triangles
## y_boot[b] as the final network, ccODP start (14) on 'cells' and 'epochs'
## gradient descent steps; refit k with the seed param$seed + k; bCCNN
## reserves by accident period (length(b) x n) and the seconds of each
## refit: time by the clock (the first refit of an R session also starts
## Python), time_fit of its Keras fit
bccnn_bootstrap <- function(y_boot, b, cells, epochs, param) {
  refits <- lapply(b, function(k) {
    param$seed <- param$seed + k               # local copy per refit
    t0 <- Sys.time()
    nn <- bccnn_fit(ccodp_fit(y_boot[[k]], cells), epochs, param,
                    track = list())
    list(reserve = rowSums(lower_triangle(nn$mu), na.rm = TRUE),
         time = as.numeric(Sys.time() - t0, units = "secs"),
         time_fit = nn$time[["fit"]])
  })
  list(reserves = t(sapply(refits, `[[`, "reserve")),
       time = sapply(refits, `[[`, "time"),
       time_fit = sapply(refits, `[[`, "time_fit"))
}

## rolling origin: per partition, ccODP and bCCNN on the training cells,
## early-stopped on the validation cells; a test partition also scores the
## network chosen by final_fit on its test cells (test error: their eq. (4.4))
## and keeps its predicted triangle in mu_test (nagging predictors); the
## seconds of the Keras fit of the early-stopping run and of the test refit
## are in summary, with those of building the early-stopping network
## (time_build: the first network of an R session also starts Python); their
## seconds per epoch in epoch_time, the seconds of all Keras fits in time_fit
rolling_origin_fit <- function(parts, truth, param, max_epochs, final_fit) {
  summary <- NULL
  final <- NULL                     # no final partition: the test ones only
  mu_test <- list()
  times <- NULL
  for (k in seq_along(parts)) {
    part <- parts[[k]]
    lab <- if (part$final) "final" else as.character(k)
    odp <- ccodp_fit(part$y, cells = part$train)
    track <- list(vali = ifelse(part$vali, part$y, NA))
    if (part$final) track$truth <- truth else track$test <- part$test
    nn <- bccnn_fit(odp, max_epochs, param, track = track)
    h <- nn$history
    times <- rbind(times, epoch_time(lab, "early_stop", h))
    best <- h$epoch[which.min(h$vali)]
    res <- data.frame(partition = lab,
                      origin = part$origin,
                      n_train = sum(part$train),
                      n_vali = sum(part$vali),
                      n_test = sum(!is.na(part$test)),
                      best_epoch = best,
                      test_actual = NA,
                      test_ccODP = NA,
                      test_ccODP_train = NA,
                      test_bCCNN = NA,
                      test_loss_ccODP = NA,
                      test_loss_ccODP_train = NA,
                      test_loss_bCCNN = NA,
                      time_build = nn$time[["build"]],
                      time_early_stop = nn$time[["fit"]],
                      time_refit = NA)
    if (part$final) {
      final <- list(history = h, best_epoch = best, mu_path = nn$mu_path)
    } else {
      cl <- ccodp_fit(part$y)                      # chain ladder at c0
      if (final_fit == "refit") {
        # refit: bCCNN started in the chain ladder at c0, all cells,
        # 'best' steps
        nn_test <- bccnn_fit(cl,
                             best,
                             param,
                             track = list(test = part$test))
        h_test <- tail(nn_test$history, 1)
        mu_test[[k]] <- nn_test$mu
        times <- rbind(times, epoch_time(lab, "refit", nn_test$history))
        res$time_refit <- nn_test$time[["fit"]]
      } else {
        h_test <- h[h$epoch == best, ]
        mu_test[[k]] <- nn$mu_path[[best + 1]]
      }
      res$test_actual <- sum(part$test, na.rm = TRUE)
      res$test_ccODP <- sum(cl$mu[!is.na(part$test)])
      res$test_ccODP_train <- h$test_pred[h$epoch == 0]
      res$test_bCCNN <- h_test$test_pred
      res$test_loss_ccODP <- poisson_deviance(part$test, cl$mu)
      res$test_loss_ccODP_train <- h$test[h$epoch == 0]
      res$test_loss_bCCNN <- h_test$test
    }
    summary <- rbind(summary, res)
  }
  list(summary = summary,
       final = final,
       mu_test = mu_test,
       epoch_time = times,
       time_fit = sum(summary$time_early_stop, summary$time_refit,
                      na.rm = TRUE))
}

## the rolling origin of a run of the grid, finished under every stopping
## rule of stop_cfg (config.yml bccnn$stopping; own design): per partition
## one validation run of stop_cfg$max_epochs steps as in rolling_origin_fit(),
## and per rule the network of final_fit at the steps stopping_steps() reads
## off its validation losses: at a test partition its test error (4.4) and
## predicted triangle (mu_test), at the final partition the final network
## (mu; refit: on the observed triangle). Rules with the same steps share
## the network; refit with 0 steps is the chain ladder at c0 itself and no
## network is fitted. summary: one row per partition and rule, as that of
## rolling_origin_fit() (steps: its best_epoch; time_refit: the seconds of
## the refit the rule uses); history: the validation run of the final
## partition; epoch_time: the seconds per epoch of every fit with its steps;
## time_fit: the seconds of all Keras fits
rolling_origin_rules <- function(parts,
                                 truth,
                                 param,
                                 stop_cfg,
                                 minimum_epochs,
                                 fixed,
                                 final_fit) {
  summary <- NULL
  mu <- list()
  mu_test <- list()
  history <- NULL
  times <- NULL
  time_fit <- 0
  for (k in seq_along(parts)) {
    part <- parts[[k]]
    lab <- if (part$final) "final" else as.character(k)
    odp <- ccodp_fit(part$y, cells = part$train)
    track <- list(vali = ifelse(part$vali, part$y, NA))
    if (part$final) track$truth <- truth else track$test <- part$test
    nn <- bccnn_fit(odp, stop_cfg$max_epochs, param, track = track)
    h <- nn$history
    if (part$final) history <- h
    times <- rbind(times,
                   data.frame(steps = stop_cfg$max_epochs,
                              epoch_time(lab, "early_stop", h)))
    time_fit <- time_fit + nn$time[["fit"]]
    steps <- stopping_steps(h$vali, stop_cfg, minimum_epochs, fixed)
    # chain ladder at c0, its test loss and its sum over the test cells
    cl <- ccodp_fit(part$y)
    h_cl <- if (!part$final) {
      data.frame(test = poisson_deviance(part$test, cl$mu),
                 test_pred = sum(cl$mu[!is.na(part$test)]))
    }
    #
    # the network of each number of steps: its predicted triangle, the row
    # of its history with the test loss and the seconds of its Keras fit
    nets <- list()
    for (s in unique(steps)) {
      if (final_fit == "partition") {
        # the network of the validation run after s steps
        net <- list(mu = nn$mu_path[[s + 1]], h = h[h$epoch == s, ], time = NA)
      } else if (s == 0) {
        # no step: the chain ladder at c0 itself (Keras's prediction of this
        # start would be its means in single precision)
        net <- list(mu = cl$mu, h = h_cl, time = NA)
      } else {
        # refit: bCCNN started in the chain ladder at c0, all cells, s steps
        nn_s <- bccnn_fit(cl,
                          s,
                          param,
                          track = if (part$final) list() else
                            list(test = part$test))
        net <- list(mu = nn_s$mu,
                    h = tail(nn_s$history, 1),
                    time = nn_s$time[["fit"]])
        times <- rbind(times,
                       data.frame(steps = s,
                                  epoch_time(lab, "refit", nn_s$history)))
        time_fit <- time_fit + net$time
      }
      nets[[as.character(s)]] <- net
    }
    #
    for (r in names(steps)) {
      net <- nets[[as.character(steps[[r]])]]
      res <- data.frame(rule = r,
                        partition = lab,
                        origin = part$origin,
                        n_train = sum(part$train),
                        n_vali = sum(part$vali),
                        n_test = sum(!is.na(part$test)),
                        steps = steps[[r]],
                        test_actual = NA,
                        test_ccODP = NA,
                        test_ccODP_train = NA,
                        test_bCCNN = NA,
                        test_loss_ccODP = NA,
                        test_loss_ccODP_train = NA,
                        test_loss_bCCNN = NA,
                        time_build = nn$time[["build"]],
                        time_early_stop = nn$time[["fit"]],
                        time_refit = net$time)
      if (part$final) {
        mu[[r]] <- net$mu
      } else {
        mu_test[[r]] <- c(mu_test[[r]], list(net$mu))
        res$test_actual <- sum(part$test, na.rm = TRUE)
        res$test_ccODP <- h_cl$test_pred
        res$test_ccODP_train <- h$test_pred[h$epoch == 0]
        res$test_bCCNN <- net$h$test_pred
        res$test_loss_ccODP <- h_cl$test
        res$test_loss_ccODP_train <- h$test[h$epoch == 0]
        res$test_loss_bCCNN <- net$h$test
      }
      summary <- rbind(summary, res)
    }
  }
  list(summary = summary,
       mu = mu,
       mu_test = mu_test,
       history = history,
       epoch_time = times,
       time_fit = time_fit)
}

## the runs of the grid (config.yml bccnn$grid; own design, not in Paper C):
## one param list per combination of hidden layers, activation, dropout,
## optimiser and batch size (0 = full batch) and per seed (seed, seed + 1,
## ...), named grid_<hidden>_<activation>_d<dropout>_<optimizer>_b<batch>_
## s<seed>; the embeddings of alpha_i and beta_j stay fixed
bccnn_grid_runs <- function(grid_cfg, seed) {
  seeds <- seed + seq_len(grid_cfg$seeds) - 1
  runs <- list()
  for (h in grid_cfg$hidden) {
    for (a in grid_cfg$activation) {
      for (dr in grid_cfg$dropout) {
        for (o in grid_cfg$optimizers) {
          for (b in grid_cfg$batch_size) {
            for (s in seeds) {
              run_name <- paste0("grid_", paste(h, collapse = "-"), "_", a,
                                 "_d", dr, "_", o,
                                 "_b", if (b > 0) b else "full", "_s", s)
              runs[[run_name]] <- list(
                hidden = h,
                activation = a,
                dropout = dr,
                trainable = FALSE,
                optimizer = o,
                learning_rate = grid_cfg$learning_rate[[o]],
                momentum = grid_cfg$momentum,
                batch_size = if (b > 0) b,         # NULL = full batch
                seed = s
              )
            }
          }
        }
      }
    }
  }
  runs
}

## scores of a predicted triangle mu (a single network or a nagging
## predictor): reserve, Poisson deviance losses on the observed triangle y
## and on the true lower triangle, and the rolling-origin test error per
## test cell (Al-Mudafer et al. eq. (4.4)) of the triangles mu_test predicted
## at the test partitions; a diverged network (a mean that is NaN or
## infinite) has no score (NA) where that mean enters
bccnn_scores <- function(mu, mu_test, y, truth, parts) {
  test_loss <- sapply(seq_along(mu_test), function(k) {
    poisson_deviance(parts[[k]]$test, mu_test[[k]])
  })
  n_test <- sapply(seq_along(mu_test), function(k) {
    sum(!is.na(parts[[k]]$test))
  })
  scores <- c(reserve = sum(mu[row(mu) + col(mu) > nrow(mu) + 1]),
              loss_in = poisson_deviance(y, mu),
              loss_out = poisson_deviance(truth, mu),
              test_loss_per_cell = sum(test_loss) / sum(n_test))
  # an infinite mean gives an infinite reserve, which na.rm = TRUE of the
  # tables would not leave out
  scores[!is.finite(scores)] <- NA
  data.frame(as.list(scores))
}
