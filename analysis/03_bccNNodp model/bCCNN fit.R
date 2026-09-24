# bCCNN model on the annual claims triangle
#
# Paper C: Gabrielli, Richman & Wuthrich (2020), Neural network embedding of
# the over-dispersed Poisson reserving model (Gabrielli 2020, PhD thesis ETH
# Zurich, Chapter 4). One triangle: 20 accident x 20 development years.
#
#   1. full / training / validation / test triangles from the simulated
#      claims; training and validation are a 50/50 claims split (Section 3.3.1)
#   2. early-stopping analysis on the split (Section 3.3.2: Figure 2, Table 3)
#   3. ccODP (= chain-ladder) model and bCCNN on the full observed triangle
#      (Section 3.3.3: Tables 2 and 4)
#   4. tables to output/tables, figures to output/figures (after Figures 2, 3,
#      5, 7, 8), triangles to data/interim, the network to models/
#
# Settings: config.yml (data:, odp:, bccnn:). Keras runs on Python through
# reticulate; point it at a Python with tensorflow and keras before the first
# Keras call, e.g. with a line in .Renviron such as
#   RETICULATE_PYTHON=C:/Users/<you>/AppData/Local/Programs/Python/Python312/python.exe

source(here::here("analysis", "00_setup.R"))
# 'R/fit ODP GLM' has no .R extension, so 00_setup.R does not source it
source(here::here("R", "fit ODP GLM"))

dat_cfg <- cfg$data
nn_cfg  <- cfg$bccnn
raw_dir <- file.path(paths$raw, dat_cfg$annual_dir)


## 1. triangles ----------------------------------------------------------------
transactions <- fread(file.path(raw_dir, "transactions.csv"),
                      select = c("claim_no", "occurrence_period",
                                 "payment_period", "payment_inflated"))
claims <- fread(file.path(raw_dir, "claims.csv"),
                select = c("claim_no", "occurrence_period"))
sets <- triangle_sets(transactions, n_dev = dat_cfg$n_dev, claims = claims,
                      runoff = dat_cfg$runoff)
print(sets$n_claims)   # claims per accident year in the two halves

# the full square is the simulator's triangle.csv
tri_csv <- as.matrix(fread(file.path(raw_dir, "triangle.csv"))[, -1])
stopifnot(isTRUE(all.equal(unname(sets$full), unname(tri_csv))))

for (k in c("full", "upper", "test", "train", "vali")) {
  fwrite(as.data.table(sets[[k]], keep.rownames = "origin"),
         file.path(paths$interim, paste0("tri_annual_", k, ".csv")))
}


## 2.-3. validation run, ccODP and bCCNN ----------------------------------------
res <- bccnn_calibrate(sets,
                       scale = dat_cfg$scale,
                       phi = cfg$odp$phi,
                       max_epochs = nn_cfg$training$max_epochs,
                       epochs = nn_cfg$training$epochs,
                       batch_size = nn_cfg$training$batch_size,
                       q = nn_cfg$model$hidden,
                       dropout = nn_cfg$model$dropout,
                       activation = nn_cfg$model$activation,
                       trainable_embeddings = nn_cfg$model$trainable_embeddings,
                       learning_rate = nn_cfg$training$learning_rate,
                       rho = nn_cfg$training$rho,
                       epsilon = nn_cfg$training$epsilon,
                       seed = cfg$seed)

# the ccODP reserves are the chain-ladder reserves
cl <- fit_chainladder(sets$upper, cum = FALSE)
stopifnot(isTRUE(all.equal(res$odp$reserve * dat_cfg$scale,
                           unname(cl$total[["ibnr"]]), tolerance = 1e-6)))


## 4. tables and figures ----------------------------------------------------------
tabs <- bccnn_tables(res, sets)
write_tables(tabs, "bccnn_annual")
print(tabs$results)
print(tabs$validation)

save_gg("bCCNN validation losses.png",
        plot_loss_curves(res$validation$history,
                         best_epoch = res$validation$best_epoch,
                         title = "bCCNN on the 50/50 claims split"))
save_gg("bCCNN fit losses.png",
        plot_loss_curves(res$nn$history,
                         series = c(train = "in-sample loss (observed triangle)",
                                    test = "out-of-sample loss (true lower triangle)"),
                         free_y = TRUE, title = "bCCNN on the full triangle"),
        height = 7)
save_gg("bCCNN vs ccODP relative difference.png",
        plot_relative_difference(res$odp$mu, res$nn$mu,
                                 title = "bCCNN versus ccODP: mu_bCCNN / mu_ccODP - 1"),
        width = 8, height = 7)

test <- unname(sets$test) / dat_cfg$scale
r_max <- max(abs(c(pearson_residuals(test, res$odp$mu, res$phi[["ccODP"]]),
                   pearson_residuals(test, res$nn$mu, res$phi[["bCCNN"]]))),
             na.rm = TRUE)
save_gg("ccODP Pearson residuals.png",
        plot_pearson_residuals(test, res$odp$mu, res$phi[["ccODP"]],
                               limits = c(-r_max, r_max),
                               title = "Pearson residuals ccODP (lower triangle)"),
        width = 8, height = 7)
save_gg("bCCNN Pearson residuals.png",
        plot_pearson_residuals(test, res$nn$mu, res$phi[["bCCNN"]],
                               limits = c(-r_max, r_max),
                               title = "Pearson residuals bCCNN (lower triangle)"),
        width = 8, height = 7)
save_gg("bCCNN cumulative development factors.png",
        plot_cum_dev_factors(res$odp$mu, res$nn$mu,
                             title = "Cumulative development factors"))
save_gg("bCCNN bias by accident year.png",
        plot_bias_by_origin(tabs$by_origin,
                            title = "Reserve bias by accident year (millions)"))

save_model(res$nn$model, file.path(paths$models, "bccnn_annual.keras"),
           overwrite = TRUE)
