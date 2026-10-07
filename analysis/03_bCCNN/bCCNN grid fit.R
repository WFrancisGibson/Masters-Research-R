##########################################
#########  bCCNN on the claims triangle: grid of hyper-parameters and
#########  architectures, the fits (own design, not in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3;
#########  early stopping and test error: rolling origin (Al-Mudafer, Avanzi,
#########  Taylor & Wong 2021, Section 3.1 and eq. (4.4))
##########################################

## every combination of config.yml bccnn$grid (hidden layers, activation,
## dropout, optimiser, batch size) with every seed, each early-stopped and
## fitted as the network of "bCCNN fit.R"; the tables, figures and nagging
## predictors are in "bCCNN grid analysis.R"
source(here::here("analysis", "00_setup.R"))
library(keras3)

scale <- cfg$data$scale            # unit of the fit (Paper C: 1'000 CHF)
train_cfg <- cfg$bccnn$training
ro_cfg <- cfg$data$rolling_origin

##########################################
#########  hyper-parameters of the runs
##########################################

## one param list per run, as param of "bCCNN fit.R"; every combination is
## fitted with every seed (the spread over the seeds, nagging predictors)
runs <- bccnn_grid_runs(cfg$bccnn$grid, cfg$seed)
c("combinations" = length(runs) / cfg$bccnn$grid$seeds,
  "seeds" = cfg$bccnn$grid$seeds,
  "runs" = length(runs))

##########################################
#########  triangles
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
odp <- ccodp_fit(dat_upper, phi_method = cfg$odp$phi)

##########################################
#########  fits
##########################################

## per run: rolling-origin early stopping (the step with the lowest
## validation loss of the final partition) and test error, then the final
## network of config.yml final_fit (kept with the run: the file names do not
## carry it); a saved run is not refitted and the runs are shared by several
## R sessions (R/runs.R)
for (run_name in names(runs)) {
  run_file <- file.path(paths$processed,
                        paste0("bccnn_grid_fit_", run_name, ".rds"))
  if (!claim_run(run_file)) next
  param <- runs[[run_name]]
  t0 <- Sys.time()
  ro_fit <- rolling_origin_fit(parts,
                               truth,
                               param,
                               train_cfg$max_epochs,
                               train_cfg$final_fit)
  val <- ro_fit$final
  epochs <- val$best_epoch
  times <- ro_fit$epoch_time
  time_fit <- ro_fit$time_fit
  if (train_cfg$final_fit == "refit") {
    nn <- bccnn_fit(odp, epochs, param, track = list())
    mu_nn <- nn$mu
    times <- rbind(times, epoch_time("final", "refit", nn$history))
    time_fit <- time_fit + nn$time[["fit"]]
  } else {
    mu_nn <- val$mu_path[[epochs + 1]]   # mu_path[[1]] is the ccODP start
  }
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  # mu and mu_test in units of scale; the losses per step of the final
  # partition (loss curves) are kept for the first seed; training times:
  # run_time the seconds of the run by the clock (the first run of an R
  # session also starts Python), time_fit those of its Keras fits,
  # rolling_origin those of every early-stopping run and test refit,
  # epoch_time the milliseconds per epoch of every fit
  save_run(list(run = run_name,
                param = param,
                final_fit = train_cfg$final_fit,
                run_time = run_time,
                time_fit = time_fit,
                best_epoch = epochs,
                rolling_origin = ro_fit$summary,
                mu = mu_nn,
                mu_test = ro_fit$mu_test,
                history = if (param$seed == cfg$seed) val$history,
                epoch_time = epoch_ms(times),
                info = run_info()),
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
