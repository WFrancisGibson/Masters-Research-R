##########################################
#########  bCCNN hyperparameters chosen on the rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2 and 4.1
##########################################

## arguments of param (bccnn_model(), bccnn_fit()) that can be tuned; hidden:
## the neurons of the hidden layers, one layer per element
bccnn_tunable <- c("hidden", "activation", "dropout", "trainable",
                   "optimizer", "learning_rate", "momentum", "batch_size")

## time-series cross-validation score of the set hp (named list overriding
## param): per seed, rolling_origin_fit() on the test partitions of parts
## (early stopping on each partition's validation cells, then the network
## chosen by final_fit scored on its test cells: their eq. (4.4)); baseline
## the chain ladder at each valuation date (refit) or the ccODP on the
## training cells (partition); the runs keep the seconds of the Keras fit
## of the early-stopping run and of the test refit, epoch_time the
## milliseconds per epoch of every fit; see tscv_summary()
bccnn_tscv_score <- function(parts,
                             hp,
                             param,
                             seeds,
                             max_epochs,
                             final_fit = "refit",
                             fit = rolling_origin_fit) {
  hp_check(hp, bccnn_tunable)
  tests <- Filter(function(p) !p$final, parts)
  base_col <- if (final_fit == "refit") "test_loss_ccODP" else
    "test_loss_ccODP_train"
  runs <- NULL
  times <- NULL
  for (s in seeds) {
    p <- modifyList(param, hp)
    p$seed <- s
    ro_fit <- fit(tests, NULL, p, max_epochs, final_fit)
    ro <- ro_fit$summary
    runs <- rbind(runs,
                  data.frame(seed = s,
                             origin = ro$origin,
                             n_test = ro$n_test,
                             steps = ro$best_epoch,
                             loss = ro$test_loss_bCCNN,
                             loss_baseline = ro[[base_col]],
                             test_actual = ro$test_actual,
                             test_bCCNN = ro$test_bCCNN,
                             test_ccODP = ro$test_ccODP,
                             time_early_stop = ro$time_early_stop,
                             time_refit = ro$time_refit))
    times <- rbind(times, data.frame(seed = s, epoch_ms(ro_fit$epoch_time)))
  }
  c(tscv_summary(runs, hp), list(epoch_time = times))
}
