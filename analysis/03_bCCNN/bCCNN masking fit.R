##########################################
#########  bCCNN on the claims triangle: periods without payments masked
#########  or scored in the early stopping and the test error, the fits
#########  (own design, not in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3.3;
#########  rolling origin and test error: Al-Mudafer, Avanzi, Taylor & Wong
#########  (2021), Section 3.1 and eq. (4.4)
##########################################

## the network of Paper C (config.yml bccnn$model: 3 hidden layers, tanh)
## under the three splits of "bCCNN fit.R": Paper C's 50/50 claims split, and
## the rolling origin with the final network refitted on the observed
## triangle (refit) or kept from the final partition (partition); each with
## all validation and test cells scored and with the cells of the periods
## without payments left out (mask_zero_periods() in R/triangles.R), for
## every seed of config.yml bccnn$masking; the tables and figures are in
## "bCCNN masking analysis.R"
source(here::here("analysis", "00_setup.R"))
library(keras3)

scale <- cfg$data$scale            # unit of the fit (Paper C: 1'000 CHF)
train_cfg <- cfg$bccnn$training
ro_cfg <- cfg$data$rolling_origin
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

## rolling origin: validation cells without the periods with no payments in
## the training cells, test cells without the periods with no payments in
## any cell observed at the valuation date
parts <- rolling_origin(dat_upper,
                        ro_cfg$test_periods,
                        ro_cfg$vali_periods,
                        ro_cfg$exclude)
parts_mask <- mask_partitions(parts)

##########################################
#########  fits
##########################################

## per seed: the early-stopping runs of the three splits with all cells
## scored and with the masked cells left out, and their final networks; a
## saved seed is not refitted and several R sessions share the seeds
## (claim_run() and save_run() of R/runs.R)
for (s in seeds) {
  seed_file <- file.path(paths$processed,
                         paste0("bccnn_masking_fit_s", s, ".rds"))
  if (!claim_run(seed_file)) next
  param$seed <- s
  t0 <- Sys.time()
  #
  # claims split: masking changes the cells scored, not the training, so
  # one run on the training half gives both validation losses; time_fit:
  # the seconds of the Keras fits of the seed
  track <- list(vali = vali, vali_mask = vali_mask)
  nn_claims <- bccnn_fit(odp_train,
                         max_epochs,
                         param,
                         track)[c("history", "time")]
  h_claims <- nn_claims$history
  time_fit <- nn_claims$time[["fit"]]
  #
  # rolling origin, per final fit; no cell masked: the same fits
  ro <- list()
  for (f in c("refit", "partition")) {
    ro[[f]] <- list(all = rolling_origin_fit(parts,
                                             truth,
                                             param,
                                             max_epochs,
                                             f))
    time_fit <- time_fit + ro[[f]]$all$time_fit
    if (identical(parts_mask, parts)) {
      ro[[f]]$masked <- ro[[f]]$all
    } else {
      ro[[f]]$masked <- rolling_origin_fit(parts_mask,
                                           truth,
                                           param,
                                           max_epochs,
                                           f)
      time_fit <- time_fit + ro[[f]]$masked$time_fit
    }
  }
  #
  # per split and cells scored: the early-stopping run of the final network
  # (validation loss on the cells scored in 'vali', its lowest step in
  # best_epoch) and the test partitions of the rolling origin
  fits <- list()
  for (m in c("all", "masked")) {
    h <- h_claims
    if (m == "masked") h$vali <- h$vali_mask
    fits[[paste("claims_split", m)]] <-
      list(history = h, best_epoch = h$epoch[which.min(h$vali)])
    for (f in names(ro)) {
      tst <- ro[[f]][[m]]$summary
      fits[[paste0("rolling_origin_", f, " ", m)]] <-
        c(ro[[f]][[m]]$final, list(test = tst[tst$partition != "final", ]))
    }
  }
  #
  # final networks: refitted on the observed triangle for the chosen steps
  # (Paper C Section 3.3.3), one refit per number of steps; partition: the
  # early-stopped network of the final partition (mu_path[[1]] is the
  # ccODP start)
  refit <- list()
  refit_time <- list()
  for (k in names(fits)) {
    steps <- fits[[k]]$best_epoch
    if (grepl("partition", k)) {
      fits[[k]]$mu <- fits[[k]]$mu_path[[steps + 1]]
    } else {
      if (is.null(refit[[as.character(steps)]])) {
        nn <- bccnn_fit(odp, steps, param, track = list())
        refit[[as.character(steps)]] <- nn$mu
        refit_time[[as.character(steps)]] <-
          epoch_ms(epoch_time("final", "refit", nn$history))
        time_fit <- time_fit + nn$time[["fit"]]
      }
      fits[[k]]$mu <- refit[[as.character(steps)]]
    }
  }
  #
  # one row per split and cells scored: steps, validation losses of the
  # early-stopping run, reserve and losses of the final network on the
  # observed triangle and on the true lower triangle, and the rolling-origin
  # test error per test cell (4.4) with its baseline: the chain ladder at
  # each valuation date (refit) or the ccODP on the training cells
  # (partition); mu in units of scale
  runs <- NULL
  for (k in names(fits)) {
    fit <- fits[[k]]
    h <- fit$history
    steps <- fit$best_epoch
    tst <- fit$test
    base <- if (grepl("refit", k)) tst$test_loss_ccODP else
      tst$test_loss_ccODP_train
    runs <- rbind(runs, data.frame(
      seed = s,
      split = sub(" .*", "", k),
      cells = sub(".* ", "", k),
      steps = steps,
      vali_start = h$vali[h$epoch == 0],
      vali_steps = h$vali[h$epoch == steps],
      reserve = sum(lower_triangle(fit$mu), na.rm = TRUE),
      loss_in = poisson_deviance(dat_upper, fit$mu),
      loss_out = poisson_deviance(truth, fit$mu),
      test_loss_per_cell = if (is.null(tst)) NA else
        sum(tst$test_loss_bCCNN) / sum(tst$n_test),
      test_loss_per_cell_ccODP = if (is.null(tst)) NA else
        sum(base) / sum(tst$n_test)
    ))
  }
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  # the losses per step (loss curves) of the claims split and of the final
  # partition of the rolling origin, kept for the first seed
  history <- list(claims_split = h_claims,
                  rolling_origin = lapply(ro$refit, function(r) {
                    r$final$history
                  }))
  # training times: run_time the seconds of the seed by the clock (the first
  # seed of an R session also starts Python), time_fit those of its Keras
  # fits, the summaries of the rolling origin those of every early-stopping
  # run and test refit, epoch_time the milliseconds per epoch of every fit
  # (refit: the final networks by number of steps)
  times <- list(claims_split = epoch_ms(epoch_time("halves",
                                                   "early_stop",
                                                   h_claims)),
                rolling_origin = lapply(ro, lapply, function(r) {
                  epoch_ms(r$epoch_time)
                }),
                refit = refit_time)
  save_run(list(seed = s,
                param = param,
                run_time = run_time,
                time_fit = time_fit,
                runs = runs,
                rolling_origin = lapply(ro, lapply, `[[`, "summary"),
                mu = lapply(fits, `[[`, "mu"),
                history = if (s == cfg$seed) history,
                epoch_time = times,
                info = run_info()),
           seed_file)
  cat(sprintf("%s seed %d: %.0f s, steps %s\n",
              format(Sys.time(), "%H:%M"),
              s,
              run_time,
              paste(runs$steps, collapse = " ")))
}
