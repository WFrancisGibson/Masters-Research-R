# bCCNN hyperparameters chosen on the rolling-origin folds
#
# Al-Mudafer, Avanzi, Taylor & Wong (2021), Section 3.2: the hyperparameters
# are those with the lowest test error over the test partitions, averaged
# over several seeds; the chosen model is then trained on the final partition.
# Here (R/bccnn_tuning.R):
#
#   1. triangles from the simulated claims, as in "bCCNN fit.R"
#   2. rolling-origin partitions (valuation years 15, 18, 20 of 20)
#   3. search: every candidate set is scored by time-series cross-validation
#      on the two test partitions -- per seed and partition: ccODP start on
#      the training cells, early stopping on the partition's validation
#      cells, refit at the valuation date for those steps, deviance on the
#      later calendar years -- pooled per test cell and averaged over seeds
#      (config bccnn.tuning: method successive or grid, seeds, candidates)
#   4. bCCNN with the chosen hyperparameters: the final partition chooses the
#      number of steps, the reported network is fitted on the full triangle
#      (bccnn_calibrate(), as in "bCCNN fit.R")
#   5. tables to output/tables: the search (bccnn_tuning_*.csv) and the tuned
#      model (bccnn_annual_tuned_*.csv)
#
# The test error is the selection criterion here, so the test error reported
# for the tuned model is optimistic; its deviance on the true lower triangle
# (bccnn_annual_tuned_results.csv) is the independent check.
#
# Run time: one score = (number of seeds) x 2 test partitions x (an
# early-stopping run of max_epochs steps + a refit). With the default config
# the successive search scores at most 1 + 2 + 4 + 2 = 9 sets (the current
# value of each hyperparameter is not refitted), 54 runs.
# Keras setup as in "bCCNN fit.R" (RETICULATE_PYTHON).

source(here::here("analysis", "00_setup.R"))
# 'R/fit ODP GLM' has no .R extension, so 00_setup.R does not source it
source(here::here("R", "fit ODP GLM"))

dat_cfg <- cfg$data
nn_cfg  <- cfg$bccnn
tune_cfg <- nn_cfg$tuning
raw_dir <- file.path(paths$raw, dat_cfg$annual_dir)
n <- dat_cfg$n_dev


## 1. triangles ----------------------------------------------------------------
transactions <- fread(file.path(raw_dir, "transactions.csv"),
                      select = c("claim_no", "occurrence_period",
                                 "payment_period", "payment_inflated"))
claims <- fread(file.path(raw_dir, "claims.csv"),
                select = c("claim_no", "occurrence_period"))
sets <- triangle_sets(transactions, n_dev = n, claims = claims)


## 2. rolling-origin partitions ------------------------------------------------
parts <- rolling_origin_sets(sets$upper,
                             test_periods = nn_cfg$rolling_origin$test_periods,
                             vali_periods = nn_cfg$rolling_origin$vali_periods,
                             exclude = nn_cfg$rolling_origin$exclude)


## 3. search -------------------------------------------------------------------
# settings not tuned: model: and training: of config.yml
fixed <- list(q = nn_cfg$model$hidden,
              dropout = nn_cfg$model$dropout,
              activation = nn_cfg$model$activation,
              trainable_embeddings = nn_cfg$model$trainable_embeddings,
              learning_rate = nn_cfg$training$learning_rate,
              rho = nn_cfg$training$rho,
              epsilon = nn_cfg$training$epsilon,
              batch_size = nn_cfg$training$batch_size)
score_args <- list(fixed = fixed,
                   seeds = unlist(tune_cfg$seeds),
                   max_epochs = nn_cfg$training$max_epochs,
                   scale = dat_cfg$scale,
                   phi = cfg$odp$phi,
                   final_fit = nn_cfg$training$final_fit)
candidates <- tune_cfg$candidates

search <- if (tune_cfg$method == "grid") {
  do.call(bccnn_grid_search, c(list(parts, candidates), score_args))
} else {
  order <- unlist(tune_cfg$order)
  # start: the values in config.yml, so its score is the baseline
  do.call(bccnn_successive_search,
          c(list(parts, start = fixed[order], candidates = candidates,
                 order = order), score_args))
}

print(search$table)
if (!is.null(search$path)) print(search$path)
message("chosen: ", hp_label(search$best),
        sprintf("  (test error per cell %.4f; chain ladder %.4f)",
                search$best_score, search$table$score_ccODP[1]))

runs <- do.call(rbind, lapply(search$scored, function(x) {
  cbind(label = x$label, x$runs)
}))
write_tables(list(table = search$table, path = search$path, runs = runs,
                  best = data.frame(hyperparameter = names(search$best),
                                    value = vapply(search$best, paste, "",
                                                   collapse = ", "))),
             "bccnn_tuning")


## 4. bCCNN with the chosen hyperparameters ----------------------------------
res <- do.call(bccnn_calibrate,
               c(list(sets,
                      scale = dat_cfg$scale,
                      phi = cfg$odp$phi,
                      max_epochs = nn_cfg$training$max_epochs,
                      epochs = nn_cfg$training$epochs,
                      validation = "rolling_origin",
                      test_periods = nn_cfg$rolling_origin$test_periods,
                      vali_periods = nn_cfg$rolling_origin$vali_periods,
                      exclude = nn_cfg$rolling_origin$exclude,
                      final_fit = nn_cfg$training$final_fit,
                      seed = cfg$seed),
                 modifyList(fixed, search$best)))


## 5. tables -------------------------------------------------------------------
tabs <- bccnn_tables(res, sets)
write_tables(tabs, "bccnn_annual_tuned")
print(tabs$results)
if (!is.null(tabs$rolling_origin)) print(tabs$rolling_origin)
