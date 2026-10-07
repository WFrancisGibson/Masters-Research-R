##########################################
#########  bCCNN hyperparameters chosen on the rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2 and 4.1
##########################################

## Al-Mudafer et al.: the hyperparameters are those with the lowest test
## error over the test partitions, averaged over several seeds; the chosen
## model is then fitted as usual. Here (R/tuning.R, R/bccnn_tuning.R):
## 1. triangles, as in "bCCNN fit.R"
## 2. rolling-origin partitions (valuation years 15, 18, 20 of 20)
## 3. search (config bccnn$tuning): every set is scored on the two test
##    partitions -- per seed and partition: ccODP start on the training
##    cells, early stopping on the partition's validation cells, the network
##    of final_fit scored on the later calendar years -- pooled per test cell
##    and averaged over the seeds; scored sets are saved in
##    data/processed/bccnn_tuning and not refitted when the script is run
##    again (a stopped search resumes)
## 4. the bCCNN with the chosen set: the final partition chooses the steps,
##    then the network of final_fit on the observed triangle (as in
##    "bCCNN fit.R"); next to the bCCNN with the settings of config.yml
## 5. tables to output/tables/03_bCCNN: bccnn_tuning_*.csv
##
## The test error is the selection criterion here, so its value for the
## chosen set is optimistic; the loss on the true lower triangle is the
## independent check.
## Run time: a set costs (seeds) x 2 test partitions x (max_epochs steps + a
## refit); the default successive search scores at most 1 + 2 + 4 + 2 + 2 =
## 11 sets, 66 early-stopping runs. Keras setup as in "bCCNN fit.R".
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
library(keras3)

n <- cfg$data$n_dev
scale <- cfg$data$scale
train_cfg <- cfg$bccnn$training
tune_cfg <- cfg$bccnn$tuning

## bCCNN hyper-parameters of config.yml (as "bCCNN fit.R"): the start of the
## successive search and the settings not tuned
param <- list(hidden = cfg$bccnn$model$hidden,
              activation = cfg$bccnn$model$activation,
              dropout = cfg$bccnn$model$dropout,
              trainable = cfg$bccnn$model$trainable_embeddings,
              learning_rate = train_cfg$learning_rate,
              rho = train_cfg$rho,
              epsilon = train_cfg$epsilon,
              batch_size = train_cfg$batch_size,
              seed = cfg$seed)

##########################################
#########  triangles and partitions
##########################################

trans <- fread(file.path(paths$raw, cfg$data$annual_dir, "transactions.csv"),
               select = c("claim_no", "occurrence_period", "payment_period",
                          "payment_inflated"), data.table = FALSE)
sets <- triangle_sets(trans, n)
dat_upper <- sets$upper / scale
truth <- sets$test / scale
parts <- rolling_origin(dat_upper,
                        cfg$bccnn$rolling_origin$test_periods,
                        cfg$bccnn$rolling_origin$vali_periods,
                        cfg$bccnn$rolling_origin$exclude)

##########################################
#########  search
##########################################

order <- unlist(tune_cfg$order)
search <- tune_search(
  function(hp) {
    bccnn_tscv_score(parts, hp, param,
                     seeds = unlist(tune_cfg$seeds),
                     max_epochs = train_cfg$max_epochs,
                     final_fit = train_cfg$final_fit)
  },
  candidates = tune_cfg$candidates,
  method = tune_cfg$method,
  start = param[order],             # config.yml: its score is the baseline
  order = order,
  cache_dir = file.path(paths$processed, "bccnn_tuning"))

search$table
search$path
message("chosen: ", hp_label(search$best))

##########################################
#########  bCCNN with the chosen and with the config settings
##########################################

## as "bCCNN fit.R": the final rolling-origin partition chooses the steps,
## then refit on the observed triangle (or the network of the partition)
bccnn_final <- function(p) {
  ro <- rolling_origin_fit(parts, truth, p, train_cfg$max_epochs,
                           train_cfg$final_fit)
  epochs <- ro$final$best_epoch
  mu <- if (train_cfg$final_fit == "refit") {
    bccnn_fit(ccodp_fit(dat_upper), epochs, p, track = list())$mu
  } else {
    ro$final$mu_path[[epochs + 1]]
  }
  c(steps = epochs,
    test_error = sum(ro$summary$test_loss_bCCNN, na.rm = TRUE) /
      sum(ro$summary$n_test),        # n_test of the final partition is 0
    reserves = sum(lower_triangle(mu), na.rm = TRUE),
    out_of_sample_loss = poisson_deviance(truth, mu))
}
odp <- ccodp_fit(dat_upper)
compare <- rbind("config.yml" = bccnn_final(param),
                 "chosen" = bccnn_final(modifyList(param, search$best)))
compare <- data.frame(model = rownames(compare), compare,
                      true_reserves = sum(truth, na.rm = TRUE),
                      CL_reserves = sum(odp$reserve_o),
                      CL_out_of_sample_loss = poisson_deviance(truth, odp$mu),
                      units = scale)
compare

##########################################
#########  tables
##########################################

fwrite(search$table, file.path(tab_dir, "bccnn_tuning_table.csv"))
if (!is.null(search$path)) {
  fwrite(search$path, file.path(tab_dir, "bccnn_tuning_path.csv"))
}
fwrite(tuning_runs(search), file.path(tab_dir, "bccnn_tuning_runs.csv"))
fwrite(tuning_best(search), file.path(tab_dir, "bccnn_tuning_best.csv"))
fwrite(compare, file.path(tab_dir, "bccnn_tuning_final.csv"))
