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
## returns the losses (6.1), f(x) on the learning rows (f_learn) and on the
## feature rows x_new (f_new), and the wall-clock seconds: of every epoch,
## its validation included (history$time), and of the three steps of the
## function, time_build (the network built and its start scored), run_time
## (the epochs) and time_predict
nncl_fit <- function(x,
                     y,
                     w,
                     x_new,
                     q,
                     param,
                     f_start = NULL) {
  t_build <- Sys.time()
  model <- nncl_model(ncol(x), q, param, f_start)
  n <- length(y)
  train <- seq_len(floor(n * (1 - param$validation_split)))  # Keras's split
  vali <- setdiff(seq_len(n), train)
  start <- get_weights(model)
  mu_start <- predict(model,
                      list(x[vali, ], w[vali, , drop = FALSE]),
                      batch_size = 1e5,
                      verbose = 0)
  # the time at the end of every epoch (NULL: nothing goes back to Keras)
  t_epoch <- Sys.time()
  callbacks <- list(callback_lambda(on_epoch_end = function(epoch, logs) {
    t_epoch <<- c(t_epoch, Sys.time())
    NULL
  }))
  if (param$early_stop) {
    callbacks <- c(callbacks,
                   list(callback_early_stopping(monitor = "val_loss",
                                                patience = param$patience,
                                                restore_best_weights = TRUE)))
  }
  t0 <- t_epoch
  history <- model %>% fit(list(x, w),
                           as.matrix(y),
                           epochs = param$epochs,
                           batch_size = param$batch_size,
                           validation_split = param$validation_split,
                           callbacks = callbacks,
                           verbose = 0,
                           view_metrics = FALSE)
  t1 <- Sys.time()
  # Keras's callback holds the R function above and with it this call (x, y,
  # the network), and the call would hold the callback: neither could be
  # freed, the memory of the R session would grow with every network
  callbacks <- NULL
  val_loss <- history$metrics$val_loss
  # early stopping keeps the epoch with the lowest validation loss, Keras
  # the first one if no loss is finite (a diverging optimiser)
  epochs_used <- if (param$early_stop) max(which.min(val_loss), 1L) else
    length(val_loss)
  # early stopping from the CL start: keep the start if no epoch beats it
  # (na.rm: the losses of a diverging optimiser are NaN)
  if (param$early_stop && !is.null(f_start) &&
        min(val_loss, na.rm = TRUE) >= mean((y[vali] - mu_start)^2)) {
    set_weights(model, start)
    epochs_used <- 0
  }
  mu <- predict(model, list(x, w), batch_size = 1e5, verbose = 0)[, 1]
  f_new <- predict(model,
                   list(x_new, matrix(1, nrow(x_new), 1)),
                   batch_size = 1e5,
                   verbose = 0)[, 1]
  res2 <- (y - mu)^2
  list(model = model,
       history = data.frame(epoch = seq_along(val_loss),
                            loss = history$metrics$loss,
                            val_loss = val_loss,
                            time = as.numeric(diff(t_epoch), units = "secs")),
       run_time = as.numeric(t1 - t0, units = "secs"),
       time_build = as.numeric(t0 - t_build, units = "secs"),
       time_predict = as.numeric(Sys.time() - t1, units = "secs"),
       epochs_run = length(val_loss),
       epochs_used = epochs_used,
       n_par = count_params(model) - count_params(get_layer(model, "Offset")),
       loss = sum(res2),            # L'_j (6.1) on all learning cells
       loss_train = sum(res2[train]),
       loss_vali = sum(res2[vali]),
       f_learn = mu / w[, 1],
       f_new = f_new)
}

## the two grids of nncl_runs() (own design, not in the paper), named by
## their part of the fit script: grid, the random start of Listing 2
## (nncl_cfg$grid), and cl_grid, the chain-ladder start of S3, the settings
## of grid with those of nncl_cfg$cl_grid in their place; prefix: the start
## of the names of their runs. The run files of a grid are those of the
## anchored pattern ^<tag>_fit_<prefix>: "grid_" alone is also in "clgrid_",
## and the tag of the dummy coding starts that of the numeric coding
nncl_grids <- function(nncl_cfg) {
  list(grid = c(nncl_cfg$grid, prefix = "grid_"),
       cl_grid = c(modifyList(nncl_cfg$grid, nncl_cfg$cl_grid),
                   prefix = "clgrid_"))
}

## the runs of the fit scripts, a named list of list(q, param, cl_start,
## part). Part main: the networks of the paper (Listing 2) with q hidden
## neurons, paper_q<q>, and the sensitivity runs at q_main, each adding one
## change: S1 Adam, S2 early stopping, S3 the output started in the
## homogeneous CL factor (nncl_cfg$runs: those to fit; S4, the balance
## correction, is derived from S3). Own design, not in the paper: the grids
## of nncl_grids(), <prefix><hidden>_<optimizer>_<training>_s<seed>, every
## combination of hidden layers, optimiser and training with every seed
## (seed, seed + 1, ...). Part grid: training "paper" is Listing 2's and
## "early_stop" that of S2. Part cl_grid: "cl_paper" is Listing 2's (its
## epochs, no early stopping) and "cl_start" the early stopping of S3, both
## started in the homogeneous CL factor as S3. A grid is in the order of the
## seeds, all combinations of a seed before the next seed: a grid under way
## holds whole seeds, and whole blocks of seeds for the nagging predictors,
## of every combination
nncl_runs <- function(nncl_cfg, seed) {
  param <- list(activation = nncl_cfg$model$activation,
                optimizer = "rmsprop",
                learning_rate = nncl_cfg$sensitivity$learning_rate,
                epochs = nncl_cfg$training$epochs,
                batch_size = nncl_cfg$training$batch_size,
                validation_split = nncl_cfg$training$validation_split,
                early_stop = FALSE,
                patience = nncl_cfg$sensitivity$patience,
                seed = seed)
  param_s1 <- modifyList(param, list(optimizer = "adam"))
  param_s2 <- modifyList(param_s1,
                         list(early_stop = TRUE,
                              epochs = nncl_cfg$sensitivity$max_epochs))
  q_main <- nncl_cfg$model$q_main
  runs <- list()
  for (q in nncl_cfg$model$q) {
    runs[[paste0("paper_q", q)]] <- list(q = q, param = param, cl_start = FALSE)
  }
  runs$s1_adam <- list(q = q_main, param = param_s1, cl_start = FALSE)
  runs$s2_early_stop <- list(q = q_main, param = param_s2, cl_start = FALSE)
  runs$s3_cl_start <- list(q = q_main, param = param_s2, cl_start = TRUE)
  runs <- lapply(runs[nncl_cfg$runs], c, part = "main")
  # the trainings of the grids: the epochs of Listing 2 or the early stopping
  # of S2, from the random start or from the homogeneous CL factor (S3)
  training <- list(paper = list(param = param, cl_start = FALSE),
                   early_stop = list(param = param_s2, cl_start = FALSE),
                   cl_paper = list(param = param, cl_start = TRUE),
                   cl_start = list(param = param_s2, cl_start = TRUE))
  grids <- nncl_grids(nncl_cfg)
  for (g in names(grids)) {
    grid_cfg <- grids[[g]]
    for (s in seed + seq_len(grid_cfg$seeds) - 1) {
      for (h in grid_cfg$hidden) {
        for (o in grid_cfg$optimizers) {
          for (tr in grid_cfg$training) {
            p <- modifyList(training[[tr]]$param,
                            list(optimizer = o,
                                 learning_rate = grid_cfg$learning_rate[[o]],
                                 momentum = grid_cfg$momentum,
                                 seed = s))
            run_name <- paste0(grid_cfg$prefix, paste(h, collapse = "-"), "_",
                               o, "_", tr, "_s", s)
            runs[[run_name]] <- list(q = h,
                                     param = p,
                                     cl_start = training[[tr]]$cl_start,
                                     part = g)
          }
        }
      }
    }
  }
  runs
}

## the runs of the two grids of nncl_runs() as a table for the analysis
## scripts, a row per run: part (grid or cl_grid), hidden layers, optimiser,
## training, seed, learning rate, block and run, its name; block: the block
## of grid_cfg$nagging seeds of the run, the networks of a combination and
## block make a nagging predictor (Richman & Wuthrich 2020)
nncl_grid_runs <- function(nncl_cfg, seed) {
  grids <- nncl_grids(nncl_cfg)
  rbindlist(lapply(names(grids), function(g) {
    grid_cfg <- grids[[g]]
    runs <- CJ(part = g,
               hidden = sapply(grid_cfg$hidden, paste, collapse = "-"),
               optimizer = grid_cfg$optimizers,
               training = grid_cfg$training,
               seed = seed + seq_len(grid_cfg$seeds) - 1,
               sorted = FALSE)
    runs$learning_rate <- unname(unlist(grid_cfg$learning_rate)[runs$optimizer])
    runs$block <- ceiling((runs$seed - seed + 1) / grid_cfg$nagging)
    runs$run <- paste0(grid_cfg$prefix, runs$hidden, "_", runs$optimizer, "_",
                       runs$training, "_s", runs$seed)
    runs
  }))
}

## the networks of one run (an element of nncl_runs()), one per development
## period j: cum = cumulative payments of the cells (column j + 1: C_{.,j}),
## x = their network inputs, learn_rows[[j]] = the learning cells of network
## j, x_new = the feature rows to predict f(x) for. The payments are fitted
## in 'units': the mse loss and its gradients stay moderate, which sgd needs
## (the adaptive optimisers are unaffected by the unit). model_prefix: the
## networks are saved to <model_prefix>_j<j>.keras. Returns the fits of
## nncl_fit() per j without the networks, the losses L'_j (6.1) back in the
## payments' unit
nncl_run_fit <- function(cum,
                         x,
                         learn_rows,
                         x_new,
                         run,
                         units,
                         model_prefix = NULL,
                         fit = nncl_fit) {
  fits <- list()
  for (j in seq_along(learn_rows)) {
    r <- learn_rows[[j]]
    c_prev <- cum[r, j] / units
    # Listing 2: responses C_j / sqrt(C_{j-1}), volumes sqrt(C_{j-1})
    y <- cum[r, j + 1] / units / sqrt(c_prev)
    w <- matrix(sqrt(c_prev), ncol = 1)
    # S3 and the chain-ladder-start grid: output started in the homogeneous
    # CL factor of the training rows
    f_start <- NULL
    if (run$cl_start) {
      train <- seq_len(floor(length(r) * (1 - run$param$validation_split)))
      f_start <- sum(cum[r[train], j + 1]) / sum(cum[r[train], j])
    }
    fit_j <- fit(x[r, , drop = FALSE], y, w, x_new, run$q, run$param, f_start)
    if (!is.null(model_prefix)) {
      save_model(fit_j$model,
                 paste0(model_prefix, "_j", j, ".keras"),
                 overwrite = TRUE)
    }
    fit_j$model <- NULL
    for (k in c("loss", "loss_train", "loss_vali")) {
      fit_j[[k]] <- units * fit_j[[k]]
    }
    fits[[j]] <- fit_j
  }
  fits
}

## S4: the networks of S3 with the balance correction
## c_j = sum C_{i,j}(x) / sum f(x) C_{i,j-1}(x) over the training rows, so
## that the average factor (3.9) there is the homogeneous CL factor; run =
## the saved run S3 (f_x: the CL factors, feature values x networks j, and
## the fits), cum = cumulative payments of the cells, x_id = the feature
## value of every cell (row of f_x), learn_rows[[j]] = the learning cells of
## network j. Returns the run with the corrected factors, their losses L'_j
## (6.1) and the corrections (balance)
nncl_balance <- function(run, cum, x_id, learn_rows) {
  run$run <- "s4_balance"
  for (j in seq_along(learn_rows)) {
    fit <- run$fits[[j]]
    r <- learn_rows[[j]]
    c_prev <- cum[r, j]
    train <- seq_len(floor(length(r) * (1 - run$param$validation_split)))
    fit$balance <- sum(cum[r[train], j + 1]) /
      sum(run$f_x[x_id[r[train]], j] * c_prev[train])
    run$f_x[, j] <- fit$balance * run$f_x[, j]
    res2 <- (cum[r, j + 1] - run$f_x[x_id[r], j] * c_prev)^2 / c_prev
    fit$loss <- sum(res2)
    fit$loss_train <- sum(res2[train])
    fit$loss_vali <- sum(res2[-train])
    run$fits[[j]] <- fit
  }
  run
}

## zero claims features (Section 4.2) of one LoB for accident year i:
## cum = cumulative payments of the cells (columns development years 0..J),
## ay = their accident years, vol = the LoB's cumulative triangle;
## zero set X_k^(i) = {x: C_{k,I-i}(x) <= 0} of the accident years k < i
## (<= 0: recoveries can turn a cumulative negative, against the standing
## assumption of Section 2); 0/0 gives g = 1 and g_{I-i} = 0 an ultimate 0;
## a positive numerator over a zero denominator (the paper assumes 'all
## denominators are positive') takes g_pooled, the ratio that
## nncl_zero_claims() pools over the LoBs or the accident years
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

## zero claims factors and ultimates (Section 4.2) of every LoB and accident
## year i = 2..I: cum = cumulative payments of the cells (NA below the
## diagonal), ay = their accident years, lob = their LoBs 1, 2, ... Own
## rule, not in the paper, for a factor with a positive numerator over a
## zero denominator: it takes the ratio pooled over the LoBs and, in a
## portfolio of one LoB, the ratio of development year j pooled over the
## zero sets of the accident years i > I - j (column pooled_over; the first
## factor g_{I-i} of an accident year has the total volume as denominator).
## Returns the factors and ult_zero, the matrix LoB x accident year of the
## ultimates
nncl_zero_claims <- function(cum, ay, lob) {
  n_ay <- ncol(cum)
  n_lob <- max(lob)
  lob_rows <- lapply(seq_len(n_lob), function(l) which(lob == l))
  # the LoBs' observed triangles
  vol <- lapply(lob_rows, function(r) rowsum(cum[r, ], ay[r]))
  factors <- NULL
  for (l in seq_len(n_lob)) {
    r <- lob_rows[[l]]
    for (i in 2:n_ay) {
      z <- nncl_zero_claims_factors(cum[r, ], ay[r], vol[[l]], i)
      factors <- rbind(factors, data.frame(LoB = l, z$factors))
    }
  }
  # numerators and denominators pooled over the LoBs (by i and j) or over
  # the accident years (by j)
  if (n_lob > 1) {
    pool <- aggregate(cbind(num, den) ~ j + i, factors, sum)
  } else {
    pool <- aggregate(cbind(num, den) ~ j,
                      factors[factors$j > n_ay - factors$i, ],
                      sum)
  }
  ult_zero <- matrix(0, n_lob, n_ay)
  factors <- NULL
  for (l in seq_len(n_lob)) {
    r <- lob_rows[[l]]
    for (i in 2:n_ay) {
      p <- if (n_lob > 1) pool[pool$i == i, ] else
        pool[match((n_ay - i):(n_ay - 2), pool$j), ]
      z <- nncl_zero_claims_factors(cum[r, ],
                                    ay[r],
                                    vol[[l]],
                                    i,
                                    p$num / p$den)
      factors <- rbind(factors, data.frame(LoB = l, z$factors))
      ult_zero[l, i] <- z$ultimate
    }
  }
  factors$pooled_over <- ifelse(factors$pooled,
                                if (n_lob > 1) "LoB" else "accident years",
                                NA)
  list(factors = factors, ult_zero = ult_zero)
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
