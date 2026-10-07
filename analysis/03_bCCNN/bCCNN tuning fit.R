##########################################
#########  bCCNN on the annual claims triangle: hyper-parameters and
#########  architecture (own design, not in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3;
#########  early stopping and test error: rolling origin (Al-Mudafer, Avanzi,
#########  Taylor & Wong 2021, Section 3.1 and eq. (4.4))
##########################################

## every combination of config.yml bccnn$tuning (hidden layers, activation,
## dropout, optimiser, batch size) with every seed, each early-stopped and
## fitted as the network of "bCCNN fit.R"; the tables, figures and nagging
## predictors are in "bCCNN tuning analysis.R"
source(here::here("analysis", "00_setup.R"))
library(keras3)

n <- cfg$data$n_dev
scale <- cfg$data$scale            # fit in millions (Paper C: in 1'000 CHF)
train_cfg <- cfg$bccnn$training

##########################################
#########  hyper-parameters of the runs
##########################################

## one param list per run, as param of "bCCNN fit.R"; the embeddings of
## alpha_i and beta_j stay fixed in every run; every run is fitted with every
## seed (the spread over the seeds, nagging predictors)
grid_cfg <- cfg$bccnn$tuning
seeds <- cfg$seed + seq_len(grid_cfg$seeds) - 1
runs <- list()
for (h in grid_cfg$hidden) {
  for (a in grid_cfg$activation) {
    for (dr in grid_cfg$dropout) {
      for (o in names(grid_cfg$optimizers)) {
        for (b in grid_cfg$batch_size) {
          for (s in seeds) {
            run_name <- paste0("tune_", paste(h, collapse = "-"), "_", a,
                               "_d", dr, "_", o,
                               "_b", if (b > 0) b else "full", "_s", s)
            runs[[run_name]] <- list(
              hidden = h,
              activation = a,
              dropout = dr,
              trainable = FALSE,
              optimizer = o,
              learning_rate = grid_cfg$optimizers[[o]],
              momentum = grid_cfg$momentum,
              batch_size = if (b > 0) b,           # NULL = full batch
              seed = s
            )
          }
        }
      }
    }
  }
}
c("combinations" = length(runs) / length(seeds),
  "seeds" = length(seeds),
  "runs" = length(runs))

##########################################
#########  triangles
##########################################

## observed triangle, true lower triangle and rolling-origin partitions, as
## in "bCCNN fit.R"; in units of scale
trans <- fread(file.path(paths$raw, cfg$data$annual_dir, "transactions.csv"),
               select = c("claim_no", "occurrence_period", "payment_period",
                          "payment_inflated"), data.table = FALSE)
sets <- triangle_sets(trans, n)
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
parts <- rolling_origin(dat_upper,
                        cfg$bccnn$rolling_origin$test_periods,
                        cfg$bccnn$rolling_origin$vali_periods,
                        cfg$bccnn$rolling_origin$exclude)
odp <- ccodp_fit(dat_upper, phi_method = cfg$odp$phi)

##########################################
#########  fits
##########################################

## per run: rolling-origin early stopping (the step with the lowest
## validation loss of the final partition) and test error, then the final
## network of config.yml final_fit; a finished run (its .rds) is not
## refitted, so several R sessions can share the runs
for (run_name in names(runs)) {
  run_file <- file.path(paths$processed,
                        paste0("bccnn_tuning_fit_", run_name, ".rds"))
  if (file.exists(run_file)) next
  param <- runs[[run_name]]
  t0 <- Sys.time()
  ro_fit <- rolling_origin_fit(parts,
                               truth,
                               param,
                               train_cfg$max_epochs,
                               train_cfg$final_fit)
  val <- ro_fit$final
  epochs <- val$best_epoch
  if (train_cfg$final_fit == "refit") {
    mu_nn <- bccnn_fit(odp, epochs, param, track = list())$mu
  } else {
    mu_nn <- val$mu_path[[epochs + 1]]   # mu_path[[1]] is the ccODP start
  }
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  # mu and mu_test in units of scale; the losses per step of the final
  # partition (loss curves) are kept for the first seed
  saveRDS(list(run = run_name,
               param = param,
               run_time = run_time,
               best_epoch = epochs,
               rolling_origin = ro_fit$summary,
               mu = mu_nn,
               mu_test = ro_fit$mu_test,
               history = if (param$seed == cfg$seed) val$history),
          run_file)
  tst <- ro_fit$summary[ro_fit$summary$partition != "final", ]
  cat(sprintf(paste("%s %s: %.0f s, %.0f steps, test loss per cell %.4f",
                    "(ccODP %.4f)\n"),
              format(Sys.time(), "%H:%M"),
              run_name,
              run_time,
              epochs,
              sum(tst$test_loss_bCCNN) / sum(tst$n_test),
              sum(tst$test_loss_ccODP) / sum(tst$n_test)))
}
