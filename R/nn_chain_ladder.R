##########################################
#########  NN chain ladder: feature CL factors and zero claims features
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Sections 3-5 and Listing 2
##########################################

## Keras optimiser param$optimizer at param$learning_rate (Listing 2:
## rmsprop); sgd_momentum and sgd_nesterov are sgd with param$momentum
nncl_optimizer <- function(param) {
  lr <- param$learning_rate
  switch(param$optimizer,
         sgd = optimizer_sgd(learning_rate = lr),
         sgd_momentum = optimizer_sgd(learning_rate = lr,
                                      momentum = param$momentum),
         sgd_nesterov = optimizer_sgd(learning_rate = lr,
                                      momentum = param$momentum,
                                      nesterov = TRUE),
         adagrad = optimizer_adagrad(learning_rate = lr),
         adadelta = optimizer_adadelta(learning_rate = lr),
         rmsprop = optimizer_rmsprop(learning_rate = lr),
         adam = optimizer_adam(learning_rate = lr),
         adamw = optimizer_adam_w(learning_rate = lr),
         adamax = optimizer_adamax(learning_rate = lr),
         nadam = optimizer_nadam(learning_rate = lr))
}

## network of the CL factor f_{j-1}(x) of development period j (Listing 2):
## response C_j / sqrt(C_{j-1}) = f(x) * sqrt(C_{j-1}) (6.2) with
## f(x) = exp(beta_0 + sum_k beta_k z_k(x)) and tanh neurons z_k (3.2)-(3.3);
## q: neurons of the hidden layers (the paper: one layer, a vector of several
## numbers gives a deeper network);
## f_start: output started in the homogeneous CL factor (weights 0);
## param$dropout (own design, not in the paper): dropout rate after every
## hidden layer, none if NULL or 0 (the network of the paper); the CL start
## is unaffected, the output weights being 0
nncl_model <- function(d, q, param, f_start = NULL) {
  clear_session()
  set_random_seed(param$seed)
  features <- layer_input(shape = c(d), name = "Features")
  volumes <- layer_input(shape = c(1), name = "Volumes")
  dropout <- if (is.null(param$dropout)) 0 else param$dropout
  net <- features
  for (k in seq_along(q)) {
    net <- net %>% layer_dense(units = q[k],
                               activation = param$activation,
                               name = paste0("hidden", k))
    if (dropout > 0) {
      net <- net %>% layer_dropout(rate = dropout,
                                   name = paste0("dropout", k))
    }
  }
  net <- net %>%
    layer_dense(units = 1, activation = "exponential", name = "CL_factor")
  # the offset sqrt(C_{j-1}): a frozen weight 1 (Listing 2 lines 11-14)
  offset <- volumes %>%
    layer_dense(units = 1,
                activation = "linear",
                use_bias = FALSE,
                trainable = FALSE,
                kernel_initializer = "ones",
                name = "Offset")
  response <- list(net, offset) %>% layer_multiply(name = "Response")
  model <- keras_model(inputs = list(features, volumes), outputs = response)
  if (!is.null(f_start)) {
    get_layer(model, "CL_factor") %>%
      set_weights(list(matrix(0, q[length(q)], 1), array(log(f_start))))
  }
  model %>% compile(loss = "mse", optimizer = nncl_optimizer(param))
  model
}

## fits the network of development period j on its learning cells (Listing 2
## lines 18-21); Keras validates on the last validation_split of the rows;
## returns the losses (6.1) and f(x) on the learning rows and on x_diag
nncl_fit <- function(x,
                     y,
                     w,
                     x_diag,
                     q,
                     param,
                     f_start = NULL) {
  model <- nncl_model(ncol(x), q, param, f_start)
  n <- length(y)
  train <- seq_len(floor(n * (1 - param$validation_split)))  # Keras's split
  vali <- setdiff(seq_len(n), train)
  start <- get_weights(model)
  mu_start <- predict(model,
                      list(x[vali, ], w[vali, , drop = FALSE]),
                      batch_size = 1e5,
                      verbose = 0)
  callbacks <- NULL
  if (param$early_stop) {
    callbacks <- list(callback_early_stopping(monitor = "val_loss",
                                              patience = param$patience,
                                              restore_best_weights = TRUE))
  }
  t0 <- Sys.time()
  history <- model %>% fit(list(x, w),
                           as.matrix(y),
                           epochs = param$epochs,
                           batch_size = param$batch_size,
                           validation_split = param$validation_split,
                           callbacks = callbacks,
                           verbose = 0,
                           view_metrics = FALSE)
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  val_loss <- history$metrics$val_loss
  epochs_used <- if (param$early_stop) which.min(val_loss) else
    length(val_loss)
  # early stopping from the CL start: keep the start if no epoch beats it
  # (na.rm: the losses of a diverging optimiser are NaN)
  if (param$early_stop && !is.null(f_start) &&
        min(val_loss, na.rm = TRUE) >= mean((y[vali] - mu_start)^2)) {
    set_weights(model, start)
    epochs_used <- 0
  }
  mu <- predict(model, list(x, w), batch_size = 1e5, verbose = 0)[, 1]
  f_diag <- predict(model,
                    list(x_diag, matrix(1, nrow(x_diag), 1)),
                    batch_size = 1e5,
                    verbose = 0)[, 1]
  res2 <- (y - mu)^2
  list(model = model,
       history = data.frame(epoch = seq_along(val_loss),
                            loss = history$metrics$loss,
                            val_loss = val_loss),
       run_time = run_time,
       epochs_run = length(val_loss),
       epochs_used = epochs_used,
       n_par = count_params(model) - count_params(get_layer(model, "Offset")),
       loss = sum(res2),            # L'_j (6.1) on all learning cells
       loss_train = sum(res2[train]),
       loss_vali = sum(res2[vali]),
       f_learn = mu / w[, 1],
       f_diag = f_diag)
}

## zero claims features (Section 4.2) of one LoB for accident year i:
## cum = cumulative payments of the cells (columns development years 0..J),
## ay = their accident years, vol = the LoB's cumulative triangle;
## zero set X_k^(i) = {x: C_{k,I-i}(x) <= 0} of the accident years k < i
## (<= 0: recoveries can turn a cumulative negative, against the standing
## assumption of Section 2); 0/0 gives g = 1 and g_{I-i} = 0 an ultimate 0;
## a positive numerator over a zero denominator (the paper assumes 'all
## denominators are positive') takes g_pooled, the ratio pooled over the LoBs
nncl_zero_claims_factors <- function(cum, ay, vol, i, g_pooled = NULL) {
  n_ay <- nrow(vol)
  m <- n_ay - i                                   # latest development year
  dev <- m:(n_ay - 2)                             # g_m, ..., g_{J-1}
  zero <- ay < i & cum[, m + 1] <= 0
  num <- den <- rep(0, length(dev))
  # g_{I-i}: denominator the total volume of the accident years k < i
  num[1] <- sum(cum[zero, m + 2])
  den[1] <- sum(vol[seq_len(i - 1), m + 1])
  # g_j, I-i < j < J: accident years k <= I - j - 1
  for (h in seq_along(dev)[-1]) {
    k <- zero & ay <= n_ay - dev[h] - 1
    num[h] <- sum(cum[k, dev[h] + 2])
    den[h] <- sum(cum[k, dev[h] + 1])
  }
  g <- ifelse(num == 0 & den == 0, 1, num / den)
  pooled <- num > 0 & den == 0
  if (!is.null(g_pooled)) g[pooled] <- g_pooled[pooled]
  list(factors = data.frame(i = i,
                            j = dev,
                            num = num,
                            den = den,
                            g = g,
                            pooled = pooled),
       ultimate = if (g[1] == 0) 0 else unname(vol[i, m + 1]) * prod(g))
}

## NN reserves (5.1) by LoB and accident year: part 1 sum over the cells with
## C_{i,I-i}(x) > 0 of C_{i,I-i}(x) (prod_j f_j(x) - 1), part 2 the zero
## claims ultimate less the diagonal of the zero set (0 without recoveries);
## ult_zero: matrix LoB x accident year of the part-2 ultimates
nncl_reserves <- function(lob, ay, c_diag, f_prod, ult_zero) {
  cells <- data.table(LoB = lob,
                      i = ay,
                      part1 = ifelse(c_diag > 0, c_diag * (f_prod - 1), 0),
                      zero_diag = ifelse(c_diag > 0, 0, c_diag))
  res <- cells[, .(part1 = sum(part1), zero_diag = sum(zero_diag)),
               keyby = .(LoB, i)]
  res$part2 <- ult_zero[cbind(res$LoB, res$i)] - res$zero_diag
  res$reserve <- res$part1 + res$part2
  stopifnot(all(is.finite(res$reserve)))
  res
}

## Mack (1993) chain ladder on the observed part (i + j <= I) of a full
## cumulative I x I triangle cum; true = its outstanding lower triangle
nncl_mack <- function(cum) {
  n <- nrow(cum)
  tri <- as.triangle(upper_triangle(unname(cum)))
  mack <- MackChainLadder(tri, est.sigma = "Mack")
  latest <- as.numeric(getLatestCumulative(tri))
  list(by_origin = reserves_table(latest,
                                  ibnr = as.numeric(mack$FullTriangle[, n]) -
                                    latest,
                                  se = as.numeric(mack$Mack.S.E[, n]),
                                  true = cum[, n] - latest),
       total_se = unname(mack$Total.Mack.S.E))
}
