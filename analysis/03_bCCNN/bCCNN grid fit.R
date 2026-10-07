##########################################
#########  bCCNN on the claims triangle: grid of hyper-parameters and
#########  architectures under four stopping rules, the fits (own design, not
#########  in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3;
#########  early stopping and test error: rolling origin (Al-Mudafer, Avanzi,
#########  Taylor & Wong 2021, Section 3.1 and eq. (4.4)); stopping rules:
#########  Paper C Section 3.3.2, Harkonen (2021) Section 3.2, Al-Mudafer et
#########  al. Section 4
##########################################

## every combination of config.yml bccnn$grid (hidden layers, activation,
## dropout, optimiser, batch size) with every seed: one validation run per
## rolling-origin partition, finished under each stopping rule of config.yml
## bccnn$stopping as the network of "bCCNN fit.R". Run "bCCNN fit.R" under
## the rolling origin with the refit first (VALIDATION=rolling_origin,
## FINAL_FIT=refit: the defaults): the rule "fixed" reads its steps off that
## fit. The tables, figures and nagging predictors are in "bCCNN grid
## analysis.R"
source(here::here("analysis", "00_setup.R"))
library(keras3)

scale <- cfg$data$scale            # unit of the fit (Paper C: 1'000 CHF)
train_cfg <- cfg$bccnn$training
stop_cfg <- cfg$bccnn$stopping
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

## the rule "fixed": one number of steps for every partition, combination
## and seed of the data set, as Paper C reads 300 iterations off its Figure
## 2 for all LoBs (Section 3.3.2); here the step with the lowest validation
## loss of "bCCNN fit.R" (the network of config.yml bccnn$model and
## training, first seed, final partition of the rolling origin), rounded
main_fit <- readRDS(file.path(paths$processed,
                              "bccnn_fit_rolling_origin_refit.rds"))
fixed <- fixed_steps(main_fit$best_epoch, stop_cfg$round)
c("lowest validation loss of bCCNN fit.R at step" = main_fit$best_epoch,
  "fixed steps" = fixed)

## every R session reads the fixed steps anew and the file names of the runs
## do not carry them: a session stops here if the saved runs are of another
## number (the main fit was refitted since), before it adds runs to them
saved <- list.files(paths$processed,
                    pattern = "^bccnn_grid_fit_.*[.]rds$",
                    full.names = TRUE)
stopifnot("saved runs with another fixed number of steps" =
            length(saved) == 0 || identical(readRDS(saved[1])$fixed, fixed))

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

##########################################
#########  fits
##########################################

## per run: the validation runs of the rolling origin (stop_cfg$max_epochs
## steps per partition) and, per stopping rule, the steps it reads off each
## partition, the test error and the final network of config.yml final_fit
## (kept with the run: the file names do not carry it); the rule "minimum"
## looks at the first train_cfg$max_epochs steps, as "bCCNN fit.R". A saved
## run is not refitted and several R sessions share the runs (claim_run()
## and save_run() of R/runs.R)
for (run_name in names(runs)) {
  run_file <- file.path(paths$processed,
                        paste0("bccnn_grid_fit_", run_name, ".rds"))
  if (!claim_run(run_file)) next
  param <- runs[[run_name]]
  t0 <- Sys.time()
  ro_fit <- rolling_origin_rules(parts,
                                 truth,
                                 param,
                                 stop_cfg,
                                 train_cfg$max_epochs,
                                 fixed,
                                 train_cfg$final_fit)
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  ro <- ro_fit$summary
  final <- ro[ro$partition == "final", ]
  steps <- setNames(final$steps, final$rule)
  first_seed <- param$seed == cfg$seed
  # per rule: steps of the final network, rolling_origin with the steps,
  # test error and seconds of the fits of every partition, mu and mu_test
  # the predicted triangles in units of scale. Training times: run_time the
  # seconds of the run by the clock (the first run of an R session also
  # starts Python), time_fit those of its Keras fits, epoch_blocks the mean
  # milliseconds per 100 epochs of every fit. The first seed also keeps the
  # losses per step of the final partition (loss curves, all rules) and the
  # milliseconds of every epoch
  save_run(list(run = run_name,
                param = param,
                final_fit = train_cfg$final_fit,
                fixed = fixed,
                run_time = run_time,
                time_fit = ro_fit$time_fit,
                steps = steps,
                rolling_origin = ro,
                mu = ro_fit$mu,
                mu_test = ro_fit$mu_test,
                epoch_blocks = epoch_blocks(ro_fit$epoch_time, 100),
                history = if (first_seed) ro_fit$history,
                epoch_time = if (first_seed) epoch_ms(ro_fit$epoch_time),
                info = run_info()),
           run_file)
  cat(sprintf("%s %s: %.0f s, steps %s\n",
              format(Sys.time(), "%H:%M"),
              run_name,
              run_time,
              paste(names(steps), steps, collapse = ", ")))
}
