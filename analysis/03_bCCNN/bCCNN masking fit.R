##########################################
#########  bCCNN on the claims triangle: periods without payments masked
#########  or scored in the early stopping, the fits (own design, not in
#########  Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3.3
##########################################

## the network of Paper C (config.yml bccnn$model: 3 hidden layers, tanh)
## under Paper C's 50/50 claims split, early-stopped on all validation cells
## and on those left when the cells of the periods without payments in the
## training half are taken out (mask_zero_periods() in R/triangles.R, as in
## "bCCNN fit.R"), for every seed of config.yml bccnn$masking; the tables
## and figures are in "bCCNN masking analysis.R"
source(here::here("analysis", "00_setup.R"))
library(keras3)

scale <- cfg$data$scale            # unit of the fit (Paper C: 1'000 CHF)
train_cfg <- cfg$bccnn$training
max_epochs <- train_cfg$max_epochs
seeds <- cfg$seed + seq_len(cfg$bccnn$masking$seeds) - 1

## bCCNN hyper-parameters (Paper C Section 3.3), as param of "bCCNN fit.R";
## the seed is set per fit
param <- list(hidden = cfg$bccnn$model$hidden,   # neurons of the hidden layers
              activation = cfg$bccnn$model$activation,
              dropout = cfg$bccnn$model$dropout,  # after every hidden layer
              trainable = cfg$bccnn$model$trainable_embeddings,
              optimizer = train_cfg$optimizer,             # rmsprop
              learning_rate = train_cfg$learning_rate,
              momentum = train_cfg$momentum,     # sgd_momentum, sgd_nesterov
              batch_size = train_cfg$batch_size)           # NULL = full batch

##########################################
#########  triangles
##########################################

## observed triangle and true lower triangle, as in "bCCNN fit.R"; in units
## of scale
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
odp <- ccodp_fit(dat_upper)

## claims split (Paper C Section 3.3.2): the validation half scored against
## the ccODP and bCCNN of the training half, all its cells or without the
## periods with no payments in the training half
train <- sets$train / scale
vali <- sets$vali / scale
vali_mask <- mask_zero_periods(vali, train)
odp_train <- ccodp_fit(train)

##########################################
#########  fits
##########################################

## per seed: the early-stopping run on the training half with the
## validation loss on all cells and on the cells left after the masking, and
## the final network of each; a saved seed is not refitted and several R
## sessions share the seeds (claim_run() and save_run() of R/runs.R)
for (s in seeds) {
  seed_file <- file.path(paths$processed,
                         paste0("bccnn_masking_fit_s", s, ".rds"))
  if (!claim_run(seed_file)) next
  param$seed <- s
  t0 <- Sys.time()
  #
  # masking changes the cells scored, not the training, so one run on the
  # training half gives both validation losses; time_fit: the seconds of
  # the Keras fits of the seed
  track <- list(vali = vali, vali_mask = vali_mask)
  nn_claims <- bccnn_fit(odp_train,
                         max_epochs,
                         param,
                         track)[c("history", "time")]
  h_claims <- nn_claims$history
  time_fit <- nn_claims$time[["fit"]]
  #
  # per cells scored: the early-stopping run with the validation loss on
  # these cells in 'vali' and its lowest step in best_epoch
  fits <- list()
  for (m in c("all", "masked")) {
    h <- h_claims
    if (m == "masked") h$vali <- h$vali_mask
    fits[[m]] <- list(history = h, best_epoch = h$epoch[which.min(h$vali)])
  }
  #
  # final networks: refitted on the observed triangle for the chosen steps
  # (Paper C Section 3.3.3), one refit per number of steps
  refit <- list()
  refit_time <- list()
  for (m in names(fits)) {
    steps <- fits[[m]]$best_epoch
    if (is.null(refit[[as.character(steps)]])) {
      nn <- bccnn_fit(odp, steps, param, track = list())
      refit[[as.character(steps)]] <- nn$mu
      refit_time[[as.character(steps)]] <-
        epoch_ms(epoch_time("final", "refit", nn$history))
      time_fit <- time_fit + nn$time[["fit"]]
    }
    fits[[m]]$mu <- refit[[as.character(steps)]]
  }
  #
  # one row per cells scored: steps, validation losses of the
  # early-stopping run, reserve and losses of the final network on the
  # observed triangle and on the true lower triangle; mu in units of scale
  runs <- NULL
  for (m in names(fits)) {
    fit <- fits[[m]]
    h <- fit$history
    steps <- fit$best_epoch
    runs <- rbind(runs, data.frame(
      seed = s,
      cells = m,
      steps = steps,
      vali_start = h$vali[h$epoch == 0],
      vali_steps = h$vali[h$epoch == steps],
      reserve = sum(lower_triangle(fit$mu), na.rm = TRUE),
      loss_in = poisson_deviance(dat_upper, fit$mu),
      loss_out = poisson_deviance(truth, fit$mu)
    ))
  }
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  # training times: run_time the seconds of the seed by the clock (the first
  # seed of an R session also starts Python), time_fit those of its Keras
  # fits, epoch_time the milliseconds per epoch of every fit (refit: the
  # final networks by number of steps); the losses per step (loss curves)
  # are kept for the first seed
  times <- list(claims_split = epoch_ms(epoch_time("halves",
                                                   "early_stop",
                                                   h_claims)),
                refit = refit_time)
  save_run(list(seed = s,
                param = param,
                run_time = run_time,
                time_fit = time_fit,
                runs = runs,
                mu = lapply(fits, `[[`, "mu"),
                history = if (s == cfg$seed) h_claims,
                epoch_time = times,
                info = run_info()),
           seed_file)
  cat(sprintf("%s seed %d: %.0f s, steps %s\n",
              format(Sys.time(), "%H:%M"),
              s,
              run_time,
              paste(runs$cells, runs$steps, collapse = ", ")))
}
