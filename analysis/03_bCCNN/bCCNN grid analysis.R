##########################################
#########  bCCNN grid of hyper-parameters and architectures: test errors,
#########  reserves, spread over the seeds and nagging predictors
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3;
#########  test error: rolling origin (Al-Mudafer, Avanzi, Taylor & Wong
#########  2021, eq. (4.4)); nagging predictors: Richman & Wuthrich (2020)
##########################################

## reads the fits of all runs of "bCCNN grid fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

scale <- cfg$data$scale            # tables in units of scale
ro_cfg <- cfg$data$rolling_origin

## every combination of hidden layers, activation, dropout, optimiser and
## batch size with every seed: the runs of the fit script, one row each
grid_cfg <- cfg$bccnn$grid
seeds <- cfg$seed + seq_len(grid_cfg$seeds) - 1
settings <- c("hidden", "activation", "dropout", "optimizer", "batch_size")
runs <- bccnn_grid_runs(grid_cfg, cfg$seed)
grid <- rbindlist(lapply(runs, function(p) {
  data.table(hidden = paste(p$hidden, collapse = "-"),
             activation = p$activation,
             dropout = p$dropout,
             optimizer = p$optimizer,
             batch_size = if (is.null(p$batch_size)) "full" else
               as.character(p$batch_size),
             seed = p$seed,
             learning_rate = p$learning_rate)
}))
grid$combo <- paste0(grid$hidden, "_", grid$activation, "_d", grid$dropout,
                     "_", grid$optimizer, "_b", grid$batch_size)
grid$run <- names(runs)
## trainable parameters: the hidden layers on the 2 embeddings and w, B and
## c of the Response layer (13)
grid$parameters <- sapply(strsplit(grid$hidden, "-"), function(q) {
  q <- c(2, as.numeric(q))
  sum((q[-length(q)] + 1) * q[-1]) + q[length(q)] + 2
})

##########################################
#########  load the triangles and the fits
##########################################

## observed triangle, true lower triangle and rolling-origin partitions, as
## in the fit script; in units of scale
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
true_total <- sum(truth, na.rm = TRUE)
parts <- rolling_origin(dat_upper,
                        ro_cfg$test_periods,
                        ro_cfg$vali_periods,
                        ro_cfg$exclude)
fits <- lapply(setNames(nm = grid$run), function(r) {
  readRDS(file.path(paths$processed, paste0("bccnn_grid_fit_", r, ".rds")))
})
## the file names do not carry final_fit: all runs are of the same one
stopifnot(length(unique(sapply(fits, `[[`, "final_fit"))) == 1)

##########################################
#########  single networks, chain ladder and nagging predictors
##########################################

## single networks: reserve, losses on the observed triangle and on the true
## lower triangle, rolling-origin test error per test cell (4.4), steps used
## and seconds: run_time of the run by the clock (the first run of an R
## session also starts Python), time_fit of its Keras fits; a diverged
## network has no scores
scores <- rbindlist(lapply(fits, function(fit) {
  bccnn_scores(fit$mu, fit$mu_test, dat_upper, truth, parts)
}))
grid <- cbind(grid, scores)
grid$best_epoch <- sapply(fits, `[[`, "best_epoch")
grid$run_time <- sapply(fits, `[[`, "run_time")
grid$time_fit <- sapply(fits, `[[`, "time_fit")
grid$true <- true_total
grid$bias_pct <- 100 * (grid$reserve / true_total - 1)

## the ccODP (chain ladder) on the observed triangle and at each test
## partition: the start of every network
odp <- ccodp_fit(dat_upper)
cl <- bccnn_scores(odp$mu,
                   lapply(parts[-length(parts)], function(part) {
                     ccodp_fit(part$y)$mu
                   }),
                   dat_upper,
                   truth,
                   parts)
cl$bias_pct <- 100 * (cl$reserve / true_total - 1)
round(cl, 4)

## nagging predictors (Richman & Wuthrich 2020): the predicted triangles of
## the networks of a block of seeds averaged, on the observed triangle and
## at each test partition; one predictor per combination and block of seeds
## of each size of config.yml bccnn$grid$nagging
mean_mu <- function(m) Reduce(`+`, m) / length(m)
combos <- unique(grid[, c("combo", settings), with = FALSE])
nag <- NULL
for (size in grid_cfg$nagging) {
  blocks <- split(seeds, ceiling(seq_along(seeds) / size))
  for (k in seq_len(nrow(combos))) {
    for (b in seq_along(blocks)) {
      members <- fits[grid$run[grid$combo == combos$combo[k] &
                                 grid$seed %in% blocks[[b]]]]
      mu <- mean_mu(lapply(members, `[[`, "mu"))
      mu_test <- lapply(seq_along(members[[1]]$mu_test), function(j) {
        mean_mu(lapply(members, function(fit) fit$mu_test[[j]]))
      })
      nag <- rbind(nag,
                   data.table(combos[k],
                              networks = size,
                              block = b,
                              seeds = paste(range(blocks[[b]]),
                                            collapse = "-"),
                              bccnn_scores(mu,
                                           mu_test,
                                           dat_upper,
                                           truth,
                                           parts)))
    }
  }
}
nag$true <- true_total
nag$bias_pct <- 100 * (nag$reserve / true_total - 1)
nag$predictor <- paste0("nag", nag$networks, "_b", nag$block)

##########################################
#########  tables
##########################################

## spread over the seeds per combination: test error, out-of-sample loss and
## bias of the single networks (a diverged run left out), closer_than_cl the
## share of the seeds with a smaller absolute bias than the chain ladder,
## time_fit_mean the seconds of the Keras fits of a run; next to them the
## test error and bias of the nagging predictors (one column per predictor);
## ordered by the mean test error, which uses no future data
seed_spread <- grid[, .(parameters = parameters[1],
                        seeds = .N,
                        diverged = sum(!is.finite(reserve)),
                        best_epoch_mean = mean(best_epoch),
                        time_fit_mean = mean(time_fit),
                        test_loss_mean = mean(test_loss_per_cell, na.rm = TRUE),
                        test_loss_sd = sd(test_loss_per_cell, na.rm = TRUE),
                        loss_out_mean = mean(loss_out, na.rm = TRUE),
                        loss_out_sd = sd(loss_out, na.rm = TRUE),
                        bias_pct_mean = mean(bias_pct, na.rm = TRUE),
                        bias_pct_sd = sd(bias_pct, na.rm = TRUE),
                        bias_pct_min = min(bias_pct, na.rm = TRUE),
                        bias_pct_median = median(bias_pct, na.rm = TRUE),
                        bias_pct_max = max(bias_pct, na.rm = TRUE),
                        closer_than_cl = mean(abs(reserve - true) <
                                                abs(cl$reserve - true),
                                              na.rm = TRUE)),
                    by = settings]
nag_wide <- dcast(nag,
                  hidden + activation + dropout + optimizer + batch_size ~
                    predictor,
                  value.var = c("test_loss_per_cell", "bias_pct"))
seed_spread <- merge(seed_spread, nag_wide, by = settings, sort = FALSE)
seed_spread <- seed_spread[order(test_loss_mean)]
round_cols <- setdiff(names(seed_spread),
                      c(settings, "parameters", "seeds", "diverged"))
seed_spread[, (round_cols) := lapply(.SD, round, 4), .SDcols = round_cols]
seed_spread[, c(settings, "test_loss_mean", "test_loss_sd", "bias_pct_mean",
                "bias_pct_sd", "closer_than_cl"), with = FALSE]

## main effects: the single networks averaged over all other settings and
## the seeds, per level of each setting
main_effects <- rbindlist(lapply(settings, function(v) {
  grid[, .(setting = v,
           runs = .N,
           diverged = sum(!is.finite(reserve)),
           best_epoch = mean(best_epoch),
           test_loss_per_cell = mean(test_loss_per_cell, na.rm = TRUE),
           loss_out = mean(loss_out, na.rm = TRUE),
           bias_pct = mean(bias_pct, na.rm = TRUE),
           abs_bias_pct = mean(abs(bias_pct), na.rm = TRUE)),
       by = .(level = as.character(get(v)))]
}))
setcolorder(main_effects, c("setting", "level"))
cbind(main_effects[, 1:4], round(main_effects[, -(1:4)], 4))

fwrite(grid, file.path(tab_dir, "bccnn_grid_runs.csv"))
fwrite(seed_spread, file.path(tab_dir, "bccnn_grid_seed_spread.csv"))
fwrite(nag, file.path(tab_dir, "bccnn_grid_nagging.csv"))
fwrite(main_effects, file.path(tab_dir, "bccnn_grid_main_effects.csv"))

##########################################
#########  figures
##########################################

## rolling-origin test error and bias of the reserves by hidden layers and
## activation, a panel per dropout rate (columns) and optimiser and batch
## size (rows): one point per seed and one filled symbol per nagging
## predictor (dotted: chain ladder); a diverged run has no point
hidden_lab <- unique(grid$hidden)
grid$hidden <- factor(grid$hidden, levels = hidden_lab)
nag$hidden <- factor(nag$hidden, levels = hidden_lab)
measures <- c(test_loss_per_cell = "rolling-origin test loss per cell (4.4)",
              bias_pct = "bias (% of the true reserves)")
for (m in names(measures)) {
  ggsave(paste0("bCCNN grid ", m, ".png"),
         ggplot(grid, aes(x = hidden, y = .data[[m]], colour = activation)) +
           geom_hline(yintercept = cl[[m]],
                      colour = "grey50",
                      linetype = "dotted") +
           geom_point(position = position_jitterdodge(jitter.width = 0.15,
                                                      dodge.width = 0.7),
                      size = 0.9,
                      alpha = 0.7) +
           geom_point(data = nag,
                      aes(fill = activation,
                          shape = factor(networks),
                          group = activation),
                      position = position_dodge(width = 0.7),
                      colour = "black",
                      size = 2.2) +
           scale_shape_manual(values = 22 + seq_along(grid_cfg$nagging),
                              name = "nagging predictor of (networks)") +
           facet_grid(optimizer + batch_size ~ dropout,
                      labeller = label_both,
                      scales = "free_y") +
           guides(fill = "none") +
           labs(x = "hidden layers",
                y = measures[[m]],
                title = paste("bCCNN by hidden layers, activation, dropout,",
                              "optimiser and batch size"),
                subtitle = "points: single seeds; dotted: chain ladder") +
           theme_bw() + theme(legend.position = "top"),
         path = fig_dir, width = 11, height = 12, dpi = 150)
}
