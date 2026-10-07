##########################################
#########  bCCNN hyperparameters chosen on the rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2 and 4.1
##########################################

## arguments of param (bccnn_model(), bccnn_fit()) that can be tuned; hidden:
## the neurons of the hidden layers, one layer per element
bccnn_tunable <- c("hidden", "activation", "dropout", "trainable",
                   "learning_rate", "rho", "epsilon", "batch_size")

## time-series cross-validation score of the set hp (named list overriding
## param): per seed, rolling_origin_fit() on the test partitions of parts
## (early stopping on each partition's validation cells, then the network
## chosen by final_fit scored on its test cells: their eq. (4.4)); baseline
## the chain ladder at each valuation date (refit) or the ccODP on the
## training cells (partition); see tscv_summary()
bccnn_tscv_score <- function(parts,
                             hp,
                             param,
                             seeds,
                             max_epochs,
                             final_fit = "refit",
                             fit = rolling_origin_fit) {
  hp_check(hp, bccnn_tunable)
  tests <- Filter(function(p) !p$final, parts)
  if (length(tests) == 0) stop("no test partitions: set test_periods")
  base_col <- if (final_fit == "refit") "test_loss_ccODP" else
    "test_loss_ccODP_train"
  runs <- do.call(rbind, lapply(seeds, function(s) {
    p <- modifyList(param, hp)
    p$seed <- s
    ro <- fit(tests, NULL, p, max_epochs, final_fit)$summary
    data.frame(seed = s,
               origin = ro$origin,
               n_test = ro$n_test,
               steps = ro$best_epoch,
               loss = ro$test_loss_bCCNN,
               loss_baseline = ro[[base_col]],
               test_actual = ro$test_actual,
               test_bCCNN = ro$test_bCCNN,
               test_ccODP = ro$test_ccODP)
  }))
  tscv_summary(runs, hp)
}
