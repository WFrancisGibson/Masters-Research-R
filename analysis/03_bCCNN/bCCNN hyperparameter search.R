##########################################
#########  bCCNN hyperparameters chosen on the rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2 and 4.1
#########  (own design for the bCCNN, not in Paper C)
##########################################

## Al-Mudafer et al.: the hyperparameters are those with the lowest test
## error over the test partitions, averaged over several seeds; the chosen
## model is then fitted as usual (R/tuning.R, R/bccnn_tuning.R, config.yml
## bccnn$tuning). The test error is the selection criterion here, so its
## value for the chosen set is optimistic; the loss on the true lower
## triangle is the independent check.
## One R session (the steps of the search build on each other): a scored set
## is saved in <processed>/bccnn_tuning and not refitted when the script is
## run again, so a stopped search resumes.
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
library(keras3)

scale <- cfg$data$scale            # unit of the fit (Paper C: 1'000 CHF)
train_cfg <- cfg$bccnn$training
tune_cfg <- cfg$bccnn$tuning
ro_cfg <- cfg$data$rolling_origin
final_fit <- train_cfg$final_fit   # kept with every set and with the search

## bCCNN hyper-parameters of config.yml (as "bCCNN fit.R"): the start of the
## successive search and the settings not tuned
param <- list(hidden = cfg$bccnn$model$hidden,   # neurons of the hidden layers
              activation = cfg$bccnn$model$activation,
              dropout = cfg$bccnn$model$dropout,  # after every hidden layer
              trainable = cfg$bccnn$model$trainable_embeddings,
              optimizer = train_cfg$optimizer,             # rmsprop
              learning_rate = train_cfg$learning_rate,
              momentum = train_cfg$momentum,     # sgd_momentum, sgd_nesterov
              batch_size = train_cfg$batch_size,           # NULL = full batch
              seed = cfg$seed)

##########################################
#########  triangles and partitions
##########################################

## observed triangle, true lower triangle and rolling-origin partitions, as
## in "bCCNN fit.R"; in units of scale
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
parts <- rolling_origin(dat_upper,
                        ro_cfg$test_periods,
                        ro_cfg$vali_periods,
                        ro_cfg$exclude)

##########################################
#########  search and the bCCNN with the chosen settings
##########################################

## every set is scored on the test partitions: per seed and partition the
## ccODP start on the training cells, early stopping on the partition's
## validation cells and the network of final_fit scored on the later
## calendar periods; pooled per test cell and averaged over the seeds
score_set <- function(hp) {
  c(bccnn_tscv_score(parts,
                     hp,
                     param,
                     seeds = unlist(tune_cfg$seeds),
                     max_epochs = train_cfg$max_epochs,
                     final_fit = final_fit),
    list(final_fit = final_fit, info = run_info()))
}

## as "bCCNN fit.R": the final rolling-origin partition chooses the steps,
## then refit on the observed triangle (or the network of the partition);
## seconds: of the Keras fits; epoch_time: milliseconds per epoch of each
bccnn_final <- function(p) {
  ro <- rolling_origin_fit(parts, truth, p, train_cfg$max_epochs, final_fit)
  epochs <- ro$final$best_epoch
  times <- ro$epoch_time
  seconds <- ro$time_fit
  if (final_fit == "refit") {
    nn <- bccnn_fit(ccodp_fit(dat_upper), epochs, p, track = list())
    mu <- nn$mu
    times <- rbind(times, epoch_time("final", "refit", nn$history))
    seconds <- seconds + nn$time[["fit"]]
  } else {
    mu <- ro$final$mu_path[[epochs + 1]]
  }
  list(scores = c(steps = epochs,
                  test_error = sum(ro$summary$test_loss_bCCNN, na.rm = TRUE) /
                    sum(ro$summary$n_test),  # n_test of the final one is 0
                  reserves = sum(lower_triangle(mu), na.rm = TRUE),
                  out_of_sample_loss = poisson_deviance(truth, mu),
                  seconds = seconds),
       epoch_time = epoch_ms(times))
}

## the finished search is saved and not repeated (delete the file to search
## again); in the final run one R session takes it (R/runs.R) and writes the
## tables, any other session ends here
search_file <- file.path(paths$processed, "bccnn_tuning_search.rds")
cache_dir <- file.path(paths$processed, "bccnn_tuning")
search_here <- claim_run(search_file)
if (!search_here && !file.exists(search_file)) quit(save = "no")
if (search_here) {
  t0 <- Sys.time()
  ## the sets of a stopped search are read back, their file names do not
  ## carry final_fit: all are of this one
  cached <- list.files(cache_dir, pattern = "\\.rds$", full.names = TRUE)
  stopifnot("saved sets of another final_fit" =
              sapply(cached, function(f) readRDS(f)$final_fit) == final_fit)
  #
  ## the search starts from config.yml: its score is the baseline
  tune_order <- unlist(tune_cfg$order)
  search <- tune_search(score_set,
                        candidates = tune_cfg$candidates,
                        method = tune_cfg$method,
                        start = param[tune_order],
                        order = tune_order,
                        cache_dir = cache_dir)
  #
  ## bCCNN with the config settings and with the chosen ones, next to the
  ## chain ladder
  final <- list("config.yml" = bccnn_final(param),
                "chosen" = bccnn_final(modifyList(param, search$best)))
  odp <- ccodp_fit(dat_upper)
  compare <- t(sapply(final, `[[`, "scores"))
  compare <- data.frame(model = rownames(compare), compare,
                        true_reserves = sum(truth, na.rm = TRUE),
                        CL_reserves = sum(odp$reserve_o),
                        CL_out_of_sample_loss = poisson_deviance(truth, odp$mu),
                        units = scale)
  #
  ## the search with its training times: per set the seconds by the clock
  ## (run_time; the first set of an R session also starts Python) and of
  ## its Keras fits (time_fit), per run those of its fits (runs); the
  ## milliseconds per epoch of a set are in its file in <processed>/
  ## bccnn_tuning, those of the two final networks in final_epoch_time
  time_fit <- sapply(search$scored, function(x) {
    sum(x$runs$time_early_stop, x$runs$time_refit, na.rm = TRUE)
  })
  save_run(list(best = search$best,
                table = search$table,
                path = search$path,
                runs = tuning_runs(search),
                final_fit = final_fit,
                run_time = sapply(search$scored, `[[`, "run_time"),
                time_fit = time_fit,
                final = compare,
                final_epoch_time = lapply(final, `[[`, "epoch_time"),
                time = as.numeric(Sys.time() - t0, units = "secs"),
                info = run_info()),
           search_file)
}
search <- readRDS(search_file)
search$table
search$path
tuning_best(search)
search$final

##########################################
#########  tables
##########################################

fwrite(search$table, file.path(tab_dir, "bccnn_tuning_table.csv"))
if (!is.null(search$path)) {
  fwrite(search$path, file.path(tab_dir, "bccnn_tuning_path.csv"))
}
fwrite(search$runs, file.path(tab_dir, "bccnn_tuning_runs.csv"))
fwrite(tuning_best(search), file.path(tab_dir, "bccnn_tuning_best.csv"))
fwrite(search$final, file.path(tab_dir, "bccnn_tuning_final.csv"))
