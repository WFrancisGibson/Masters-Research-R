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
## (epoch 0 = ccODP start)
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
  model <- bccnn_model(odp, param)
  mu_hat <- function() {
    matrix(model$predict_on_batch(x_all),
           n,
           n,
           dimnames = list(origin = 1:n, dev = 1:n))
  }
  # after every gradient descent step keep the predicted triangle and
  # Keras's loss
  mu_path <- list(mu_hat())
  loss <- NA
  after_step <- callback_lambda(on_epoch_end = function(epoch, logs) {
    mu_path[[length(mu_path) + 1]] <<- mu_hat()
    loss[length(loss) + 1] <<- logs$loss
  })
  batch_size <- if (is.null(param$batch_size)) nrow(y_fit) else
    param$batch_size
  if (epochs > 0) {
    model %>% fit(x_fit, y_fit,
                  epochs = as.integer(epochs),
                  batch_size = batch_size,
                  callbacks = list(after_step),
                  verbose = 0,
                  view_metrics = FALSE)
  }
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
  list(model = model,
       mu = mu_hat(),
       history = history,
       mu_path = mu_path)
}

## Paper C Section 3.3.4: the bCCNN refitted on the simulated triangles
## y_boot[b] as the final network, ccODP start (14) on 'cells' and 'epochs'
## gradient descent steps; refit k with the seed param$seed + k; bCCNN
## reserves by accident period (length(b) x n)
bccnn_bootstrap <- function(y_boot, b, cells, epochs, param) {
  t(sapply(b, function(k) {
    param$seed <- param$seed + k               # local copy per refit
    nn <- bccnn_fit(ccodp_fit(y_boot[[k]], cells), epochs, param,
                    track = list())
    rowSums(lower_triangle(nn$mu), na.rm = TRUE)
  }))
}

## rolling origin: per partition, ccODP and bCCNN on the training cells,
## early-stopped on the validation cells; a test partition also scores the
## network chosen by final_fit on its test cells (test error: their eq. (4.4))
## and keeps its predicted triangle in mu_test (nagging predictors)
rolling_origin_fit <- function(parts, truth, param, max_epochs, final_fit) {
  summary <- NULL
  mu_test <- list()
  for (k in seq_along(parts)) {
    part <- parts[[k]]
    odp <- ccodp_fit(part$y, cells = part$train)
    track <- list(vali = ifelse(part$vali, part$y, NA))
    if (part$final) track$truth <- truth else track$test <- part$test
    nn <- bccnn_fit(odp, max_epochs, param, track = track)
    h <- nn$history
    best <- h$epoch[which.min(h$vali)]
    res <- data.frame(partition = if (part$final) "final" else as.character(k),
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
                      test_loss_bCCNN = NA)
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
       mu_test = mu_test)
}

## scores of a predicted triangle mu (a single network or a nagging
## predictor): reserve, Poisson deviance losses on the observed triangle y
## and on the true lower triangle, and the rolling-origin test error per
## test cell (Al-Mudafer et al. eq. (4.4)) of the triangles mu_test predicted
## at the test partitions; a diverged network (mu not finite) has no scores
bccnn_scores <- function(mu, mu_test, y, truth, parts) {
  test_loss <- sapply(seq_along(mu_test), function(k) {
    poisson_deviance(parts[[k]]$test, mu_test[[k]])
  })
  n_test <- sapply(seq_along(mu_test), function(k) {
    sum(!is.na(parts[[k]]$test))
  })
  data.frame(reserve = sum(mu[row(mu) + col(mu) > nrow(mu) + 1]),
             loss_in = poisson_deviance(y, mu),
             loss_out = poisson_deviance(truth, mu),
             test_loss_per_cell = sum(test_loss) / sum(n_test))
}
