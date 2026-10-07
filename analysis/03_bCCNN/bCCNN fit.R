##########################################
#########  bCCNN on the claims triangle
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Neural network
#########  embedding of the over-dispersed Poisson reserving model
#########  (Gabrielli 2020, PhD thesis ETH Zurich)
#########  early stopping: rolling origin (Al-Mudafer, Avanzi, Taylor & Wong
#########  2021) or Paper C's 50/50 claims split
#########  (config.yml: bccnn$training$validation);
#########  prediction uncertainty: "bCCNN bootstrap fit.R"
##########################################

## Keras runs on Python through reticulate: point it to a Python with
## tensorflow and keras, e.g. with the line
## RETICULATE_PYTHON=<path to Python312>/python.exe in .Renviron
source(here::here("analysis", "00_setup.R"))
library(keras3)

n <- cfg$data$n_dev
scale <- cfg$data$scale            # unit of the fit (Paper C: 1'000 CHF)
phi_method <- cfg$odp$phi          # dispersion estimate: deviance or pearson
train_cfg <- cfg$bccnn$training
ro_cfg <- cfg$data$rolling_origin

## the variant <validation>_<final_fit> is in the names of the fit, its
## tables, figures and model; the claims split always refits (Paper C)
final_fit <- if (train_cfg$validation == "claims_split") "refit" else
  train_cfg$final_fit
variant <- paste(train_cfg$validation, final_fit, sep = "_")
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN", variant)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

## bCCNN hyper-parameters (Paper C Section 3.3)
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
#########  triangles
##########################################

## incremental triangle at the valuation date, its lower triangle and the
## 50/50 claims split, from "claims triangles.R"; in units of scale
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)

##########################################
#########  ccODP on the observed triangle (Paper C Section 2)
##########################################

odp <- ccodp_fit(dat_upper, phi_method = phi_method)

## the ccODP reserves are the chain-ladder reserves
tri <- incr2cum(as.triangle(sets$upper))
cl <- sum(predict(chainladder(tri))[, n] - getLatestCumulative(tri))
stopifnot(isTRUE(all.equal(sum(odp$reserve_o) * scale, cl, tolerance = 1e-6)))

##########################################
#########  early stopping and final network (Paper C Section 3.3)
##########################################

## the fit is saved with its training times and not repeated (delete the
## file to refit); in the final run one R session takes it (R/runs.R) and
## writes the tables and figures, any other session ends here
fit_file <- file.path(paths$processed, paste0("bccnn_fit_", variant, ".rds"))
fit_here <- claim_run(fit_file)
if (!fit_here && !file.exists(fit_file)) quit(save = "no")
if (fit_here) {
  t0 <- Sys.time()
  ## early stopping: number of gradient descent steps
  ro_fit <- NULL
  if (train_cfg$validation == "rolling_origin") {
    parts <- rolling_origin(dat_upper,
                            ro_cfg$test_periods,
                            ro_cfg$vali_periods,
                            ro_cfg$exclude)
    ro_fit <- rolling_origin_fit(parts,
                                 truth,
                                 param,
                                 train_cfg$max_epochs,
                                 final_fit)
    val <- ro_fit$final
    time_val <- ro_fit$time_fit
  } else {
    ## Paper C Section 3.3.2: ccODP and bCCNN on the training half of the
    ## claims; the step with the lowest deviance on the validation half is
    ## kept
    train <- sets$train / scale
    # no payments in the training half: the ccODP effect is -Inf,
    # leave these cells out
    vali <- mask_zero_periods(sets$vali / scale, train)
    val <- bccnn_fit(ccodp_fit(train), train_cfg$max_epochs, param,
                     track = list(vali = vali))[c("history", "time")]
    h <- val$history
    val$best_epoch <- h$epoch[which.min(h$vali)]
    time_val <- val$time[["fit"]]
  }
  epochs <- if (is.null(train_cfg$epochs)) val$best_epoch else train_cfg$epochs
  t1 <- Sys.time()
  #
  ## final network (Paper C Section 3.3.3): refit on the observed triangle
  ## (Paper C) or the early-stopped network of the final rolling-origin
  ## partition (Al-Mudafer et al.); nn_cells: the cells it was trained on
  if (final_fit == "refit") {
    nn <- bccnn_fit(odp, epochs, param, track = list(truth = truth))
    mu_nn <- nn$mu
    h_fit <- nn$history
    nn_cells <- odp$cells
    time_final <- nn$time[["fit"]]
    save_model(nn$model,
               file.path(paths$models, paste0("bccnn_", variant, ".keras")),
               overwrite = TRUE)
  } else {
    mu_nn <- val$mu_path[[epochs + 1]]   # mu_path[[1]] is the ccODP start
    h_fit <- val$history
    nn_cells <- parts[[length(parts)]]$train
    time_final <- 0                      # no further fit
  }
  t2 <- Sys.time()
  #
  ## Paper C Table 3: relative decrease of the losses of the early-stopping
  ## run from the ccODP start (epoch 0) to the steps used
  h <- val$history
  decrease_train <- 1 - h$train[h$epoch == epochs] / h$train[h$epoch == 0]
  decrease_vali <- 1 - h$vali[h$epoch == epochs] / h$vali[h$epoch == 0]
  # Keras's training loss of epoch e is computed before that epoch's update
  # (after e - 1 steps) and jumps with the dropout: average it over the
  # epochs within 10 of epochs + 1
  w <- min(10, epochs)
  near <- h$epoch >= epochs + 1 - w & h$epoch <= epochs + 1 + w
  decrease_dropout <- if (epochs == 0) 0 else
    1 - mean(h$train_dropout[near]) / h$train_dropout[h$epoch == 1]
  #
  ## bCCNN dispersion (Paper C Section 3.3.2): estimate (5) does not apply
  ## after early stopping with dropout; reduce the ccODP one by the
  ## validation decrease (Table 3), an increase counts as 0 (Paper C, LoB 3);
  ## for Pearson's phi by analogy
  phi_odp <- c(pearson = odp$phi_pearson, deviance = odp$phi_deviance)
  phi_bccnn <- phi_odp * (1 - max(0, decrease_vali))
  #
  ## reserves by accident period, in units of scale
  by_origin <- data.frame(origin = 1:n,
                          latest = rowSums(dat_upper, na.rm = TRUE),
                          true = rowSums(truth, na.rm = TRUE),
                          CL = odp$reserve_o,
                          bCCNN = rowSums(lower_triangle(mu_nn), na.rm = TRUE))
  by_origin$bias_CL <- by_origin$CL - by_origin$true
  by_origin$bias_bCCNN <- by_origin$bCCNN - by_origin$true
  #
  ## all that the tables and figures below, the bootstrap and the timings
  ## need; history_validation and history_fit hold the seconds per epoch,
  ## epoch_time those of all rolling-origin fits; time: seconds by the clock
  ## of the early stopping (the first network of an R session also starts
  ## Python), the final network and both; time_fit: of their Keras fits
  save_run(list(variant = variant,
                param = param,
                best_epoch = val$best_epoch,
                epochs = epochs,                 # steps of the final network
                cells = nn_cells,
                mu_ccodp = odp$mu,
                mu_bccnn = mu_nn,
                phi_ccodp = phi_odp,
                phi_bccnn = phi_bccnn,
                decrease = c(train = decrease_train,
                             dropout = decrease_dropout,
                             vali = decrease_vali),
                by_origin = by_origin,
                history_validation = val$history,
                history_fit = h_fit,
                rolling_origin = ro_fit$summary,
                epoch_time = ro_fit$epoch_time,
                time = c(early_stopping = as.numeric(t1 - t0, units = "secs"),
                         final_fit = as.numeric(t2 - t1, units = "secs"),
                         total = as.numeric(Sys.time() - t0, units = "secs")),
                time_fit = c(early_stopping = time_val,
                             final_fit = time_final,
                             total = time_val + time_final),
                info = run_info()),
           fit_file)
}
fit <- readRDS(fit_file)
epochs <- fit$epochs
mu_nn <- fit$mu_bccnn
phi_nn <- fit$phi_bccnn[[phi_method]]
by_origin <- fit$by_origin
round(rbind(clock = fit$time, keras = fit$time_fit), 1)

##########################################
#########  tables (Paper C Tables 2, 3 and 4)
##########################################

tot <- colSums(by_origin[, -1])

## reserves, biases, Poisson deviance losses and dispersions (Tables 2 and 4),
## in units of scale; in-sample on the observed triangle, out-of-sample on the
## true lower triangle
results <- c(
  "true reserves" = tot[["true"]],
  "CL reserves (ccODP)" = tot[["CL"]],
  "bCCNN reserves" = tot[["bCCNN"]],
  "bias CL" = tot[["CL"]] - tot[["true"]],
  "bias bCCNN" = tot[["bCCNN"]] - tot[["true"]],
  "bias CL (%)" = 100 * (tot[["CL"]] / tot[["true"]] - 1),
  "bias bCCNN (%)" = 100 * (tot[["bCCNN"]] / tot[["true"]] - 1),
  "in-sample loss ccODP" = odp$deviance,
  "in-sample loss bCCNN" = poisson_deviance(dat_upper, mu_nn),
  "out-of-sample loss ccODP" = poisson_deviance(truth, odp$mu),
  "out-of-sample loss bCCNN" = poisson_deviance(truth, mu_nn),
  "dispersion ccODP" = odp$phi,
  "dispersion bCCNN" = phi_nn,
  "gradient descent steps" = epochs,
  "payments after the last development period (not modelled)" =
    sum(sets$tail) / scale,
  "amounts in units of" = scale
)
results <- data.frame(quantity = names(results), value = unname(results))
# "partition": the network never saw the validation cells of the observed
# triangle
if (final_fit != "refit") {
  results$quantity[results$quantity == "in-sample loss bCCNN"] <-
    "loss bCCNN on the observed triangle (validation cells out-of-sample)"
}
results

## early stopping analysis (Table 3)
h <- fit$history_validation
validation <- c(
  "validation run length (epochs)" = max(h$epoch),
  "step with lowest validation loss" = fit$best_epoch,
  "steps used for the final fit" = epochs,
  "in-sample deviance without dropout at start (ccODP)" =
    h$train[h$epoch == 0],
  "in-sample deviance without dropout at the steps used" =
    h$train[h$epoch == epochs],
  "validation loss at start (ccODP)" = h$vali[h$epoch == 0],
  "validation loss at the steps used" = h$vali[h$epoch == epochs],
  "decrease in-sample deviance without dropout (%)" =
    100 * fit$decrease[["train"]],
  "decrease in-sample training loss with dropout (%, Figure 2)" =
    100 * fit$decrease[["dropout"]],
  "decrease out-of-sample validation loss (%)" = 100 * fit$decrease[["vali"]]
)
validation <- data.frame(quantity = names(validation),
                         value = unname(validation))
validation

## rolling origin: test deviance per test cell (their eq. (4.4));
## baselines: ccODP (chain ladder at each valuation date) for refit,
## ccODP_train (training cells) for partition; time_early_stop and
## time_refit: seconds of the Keras fit of the early-stopping run and of
## the test refit; time_build: of building the early-stopping network (the
## first one of an R session also starts Python)
ro <- fit$rolling_origin
if (!is.null(ro)) {
  ro$test_loss_per_cell_ccODP <- ro$test_loss_ccODP / ro$n_test
  ro$test_loss_per_cell_ccODP_train <- ro$test_loss_ccODP_train / ro$n_test
  ro$test_loss_per_cell_bCCNN <- ro$test_loss_bCCNN / ro$n_test
  # test error (4.4): sums over the test partitions;
  # per cell = total deviance / total cells
  tst <- ro[ro$partition != "final", ]
  test_error <- data.frame(partition = "test error (4.4)",
                           as.list(colSums(tst[, -1])))
  test_error[c("origin", "n_train", "n_vali", "best_epoch")] <- NA
  n_cells <- sum(tst$n_test)
  test_error$test_loss_per_cell_ccODP <- sum(tst$test_loss_ccODP) / n_cells
  test_error$test_loss_per_cell_ccODP_train <-
    sum(tst$test_loss_ccODP_train) / n_cells
  test_error$test_loss_per_cell_bCCNN <- sum(tst$test_loss_bCCNN) / n_cells
  ro <- rbind(ro, test_error)
  ro
}

## write the tables to output/tables
steps_chosen_by <- if (epochs == fit$best_epoch) "lowest validation loss" else
  "override (config epochs)"
tables <- list(
  settings = data.frame(setting = c("early stopping on", "final network",
                                    "steps chosen by", "units"),
                        value = c(train_cfg$validation, final_fit,
                                  steps_chosen_by,
                                  format(scale, scientific = FALSE))),
  results = results,
  validation = validation,
  rolling_origin = ro,
  by_origin = rbind(by_origin, data.frame(origin = "total", as.list(tot))),
  odp_parameters = data.frame(period = 1:n, c = odp$intercept,
                              alpha = odp$alpha, beta = odp$beta),
  mu_ccODP = data.frame(origin = 1:n, odp$mu, check.names = FALSE),
  mu_bCCNN = data.frame(origin = 1:n, mu_nn, check.names = FALSE),
  history_validation = fit$history_validation,
  history_fit = fit$history_fit,
  time = data.frame(fit = names(fit$time),
                    seconds = unname(fit$time),
                    seconds_keras = unname(fit$time_fit))
)
for (k in names(tables)) {
  if (!is.null(tables[[k]])) {
    fwrite(tables[[k]],
           file.path(tab_dir, paste0("bccnn_", variant, "_", k, ".csv")))
  }
}

##########################################
#########  figures
##########################################

unit <- format(scale, big.mark = ",", scientific = FALSE)
## the rolling-origin partitions are drawn by "bCCNN partitions.R"
ggsave("bCCNN validation losses.png",
       loss_plot(h, c(train_dropout = "training loss (in-sample)",
                      vali = "validation loss (out-of-sample)"),
                 fit$best_epoch,
                 paste("bCCNN early stopping:", train_cfg$validation)),
       path = fig_dir, width = 7, height = 5, dpi = 150)
ggsave("bCCNN fit losses.png",
       loss_plot(fit$history_fit,
                 c(train = "in-sample loss (training cells)",
                   vali = "validation loss",
                   truth = "out-of-sample loss (true lower triangle)"),
                 epochs,
                 paste("bCCNN final network:", final_fit),
                 free_y = TRUE),
       path = fig_dir, width = 7, height = 8, dpi = 150)
ggsave("bCCNN vs ccODP relative difference.png",
       triangle_heatmap(mu_nn / odp$mu - 1,
                        "bCCNN versus ccODP: mu_bCCNN / mu_ccODP - 1",
                        "relative\ndifference"),
       path = fig_dir, width = 8, height = 7, dpi = 150)

## Pearson residuals (y - mu) / sqrt(phi * mu) on the true lower triangle
## (Paper C Figure 7), on the same colour scale for both models
res_odp <- (truth - odp$mu) / sqrt(odp$phi * odp$mu)
res_nn <- (truth - mu_nn) / sqrt(phi_nn * mu_nn)
r_max <- max(abs(c(res_odp, res_nn)), na.rm = TRUE)
ggsave("ccODP Pearson residuals.png",
       triangle_heatmap(res_odp, "Pearson residuals ccODP (lower triangle)",
                        "Pearson\nresidual", c(-r_max, r_max)),
       path = fig_dir, width = 8, height = 7, dpi = 150)
ggsave("bCCNN Pearson residuals.png",
       triangle_heatmap(res_nn, "Pearson residuals bCCNN (lower triangle)",
                        "Pearson\nresidual", c(-r_max, r_max)),
       path = fig_dir, width = 8, height = 7, dpi = 150)
ggsave("bCCNN cumulative development factors.png",
       cum_factors_plot(odp$mu, mu_nn, "Cumulative development factors"),
       path = fig_dir, width = 7, height = 5, dpi = 150)
ggsave("bCCNN bias by accident year.png",
       bias_plot(by_origin,
                 paste0("Reserve bias by accident year (units of ", unit, ")")),
       path = fig_dir, width = 7, height = 5, dpi = 150)
