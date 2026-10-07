##########################################
#########  bCCNN on the annual claims triangle: periods without payments
#########  masked or scored in the early stopping and the test error
#########  (own design, not in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3.3;
#########  rolling origin and test error: Al-Mudafer, Avanzi, Taylor & Wong
#########  (2021), Section 3.1 and eq. (4.4)
##########################################

## the network of Paper C (config.yml bccnn$model: 3 hidden layers, tanh)
## under the three splits of "bCCNN fit.R": Paper C's 50/50 claims split, and
## the rolling origin with the final network refitted on the observed
## triangle (refit) or kept from the final partition (partition); each with
## all validation and test cells scored and with the cells of the periods
## without payments left out (mask_zero_periods() in R/triangles.R), for
## every seed of config.yml bccnn$masking
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
library(keras3)

n <- cfg$data$n_dev
scale <- cfg$data$scale            # fit in millions (Paper C: in 1'000 CHF)
train_cfg <- cfg$bccnn$training
max_epochs <- train_cfg$max_epochs
seeds <- cfg$seed + seq_len(cfg$bccnn$masking$seeds) - 1

## bCCNN hyper-parameters (Paper C Section 3.3), as param of "bCCNN fit.R";
## the seed is set per fit
param <- list(hidden = cfg$bccnn$model$hidden,   # neurons of the hidden layers
              activation = cfg$bccnn$model$activation,
              dropout = cfg$bccnn$model$dropout,  # after every hidden layer
              trainable = cfg$bccnn$model$trainable_embeddings,
              optimizer = train_cfg$optimizer,             # rmsprop
              learning_rate = train_cfg$learning_rate,
              batch_size = train_cfg$batch_size)           # NULL = full batch

##########################################
#########  triangles
##########################################

## observed triangle and true lower triangle, as in "bCCNN fit.R"; in units
## of scale
trans <- fread(file.path(paths$raw, cfg$data$annual_dir, "transactions.csv"),
               select = c("claim_no", "occurrence_period", "payment_period",
                          "payment_inflated"), data.table = FALSE)
sets <- triangle_sets(trans, n)
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
true_total <- sum(truth, na.rm = TRUE)
odp <- ccodp_fit(dat_upper)

## claims split (Paper C Section 3.3.2): the validation half scored against
## the ccODP and bCCNN of the training half, all its cells or without the
## periods with no payments in the training half
train <- sets$train / scale
vali <- sets$vali / scale
vali_mask <- mask_zero_periods(vali, train)
odp_train <- ccodp_fit(train)

## rolling origin: validation cells without the periods with no payments in
## the training cells, test cells without the periods with no payments in
## any cell observed at the valuation date
parts <- rolling_origin(dat_upper,
                        cfg$bccnn$rolling_origin$test_periods,
                        cfg$bccnn$rolling_origin$vali_periods,
                        cfg$bccnn$rolling_origin$exclude)
parts_mask <- mask_partitions(parts)

##########################################
#########  cells masked
##########################################

## validation and test cells per split and partition, and the cells masked
part_lab <- sapply(seq_along(parts), function(k) {
  if (parts[[k]]$final) "final" else as.character(k)
})
n_vali <- sapply(parts, function(part) sum(part$vali))
n_test <- sapply(parts, function(part) sum(!is.na(part$test)))
cell_counts <- data.frame(
  split = c("claims_split", rep("rolling_origin", length(parts))),
  partition = c("halves", part_lab),
  origin = c(n, sapply(parts, `[[`, "origin")),
  n_vali = c(sum(!is.na(vali)), n_vali),
  vali_masked = c(sum(!is.na(vali)) - sum(!is.na(vali_mask)),
                  n_vali - sapply(parts_mask, function(part) sum(part$vali))),
  n_test = c(0, n_test),
  test_masked = c(0,
                  n_test - sapply(parts_mask, function(part) {
                    sum(!is.na(part$test))
                  }))
)
cell_counts

## the masked cells: their payment, the mean of the ccODP they are scored
## against at the start of the network (14) and their Poisson deviance (4)
## at that start
masked_cells <- function(split, partition, set, y, y_mask, mu) {
  cell <- which(!is.na(y) & is.na(y_mask), arr.ind = TRUE)
  y <- y[cell]
  mu <- mu[cell]
  data.frame(split = rep(split, nrow(cell)),
             partition = rep(partition, nrow(cell)),
             set = rep(set, nrow(cell)),
             origin = cell[, 1],
             dev = cell[, 2],
             payment = y,
             mu_ccODP = mu,
             deviance = 2 * (mu - y + ifelse(y > 0, y * log(y / mu), 0)))
}
masked <- masked_cells("claims_split", "halves", "validation",
                       vali, vali_mask, odp_train$mu)
for (k in seq_along(parts)) {
  part <- parts[[k]]
  part_mask <- parts_mask[[k]]
  masked <- rbind(masked,
                  masked_cells("rolling_origin", part_lab[k], "validation",
                               ifelse(part$vali, part$y, NA),
                               ifelse(part_mask$vali, part$y, NA),
                               ccodp_fit(part$y, cells = part$train)$mu))
  if (!part$final) {
    masked <- rbind(masked,
                    masked_cells("rolling_origin", part_lab[k], "test",
                                 part$test,
                                 part_mask$test,
                                 ccodp_fit(part$y)$mu))
  }
}
rownames(masked) <- NULL
masked

##########################################
#########  fits
##########################################

## per seed: the early-stopping runs of the three splits with all cells
## scored and with the masked cells left out, and their final networks; a
## finished seed (its .rds) is not refitted, so several R sessions can share
## the seeds
splits <- c("claims_split", "rolling_origin_refit", "rolling_origin_partition")
for (s in seeds) {
  seed_file <- file.path(paths$processed,
                         paste0("bccnn_masking_fit_s", s, ".rds"))
  if (file.exists(seed_file)) next
  param$seed <- s
  t0 <- Sys.time()
  #
  # claims split: masking changes the cells scored, not the training, so
  # one run on the training half gives both validation losses
  h_claims <- bccnn_fit(odp_train,
                        max_epochs,
                        param,
                        track = list(vali = vali,
                                     vali_mask = vali_mask))$history
  #
  # rolling origin, per final fit; no cell masked: the same fits
  ro <- list()
  for (f in c("refit", "partition")) {
    ro[[f]] <- list(all = rolling_origin_fit(parts,
                                             truth,
                                             param,
                                             max_epochs,
                                             f))
    ro[[f]]$masked <- if (identical(parts_mask, parts)) ro[[f]]$all else
      rolling_origin_fit(parts_mask, truth, param, max_epochs, f)
  }
  #
  # per split and cells scored: the early-stopping run of the final network
  # (validation loss on the cells scored in 'vali', its lowest step in
  # best_epoch) and the test partitions of the rolling origin
  fits <- list()
  for (m in c("all", "masked")) {
    h <- h_claims
    if (m == "masked") h$vali <- h$vali_mask
    fits[[paste("claims_split", m)]] <-
      list(history = h, best_epoch = h$epoch[which.min(h$vali)])
    for (f in names(ro)) {
      tst <- ro[[f]][[m]]$summary
      fits[[paste0("rolling_origin_", f, " ", m)]] <-
        c(ro[[f]][[m]]$final, list(test = tst[tst$partition != "final", ]))
    }
  }
  #
  # final networks: refitted on the observed triangle for the chosen steps
  # (Paper C Section 3.3.3), one refit per number of steps; partition: the
  # early-stopped network of the final partition (mu_path[[1]] is the
  # ccODP start)
  refit <- list()
  for (k in names(fits)) {
    steps <- fits[[k]]$best_epoch
    if (grepl("partition", k)) {
      fits[[k]]$mu <- fits[[k]]$mu_path[[steps + 1]]
    } else {
      if (is.null(refit[[as.character(steps)]])) {
        refit[[as.character(steps)]] <-
          bccnn_fit(odp, steps, param, track = list())$mu
      }
      fits[[k]]$mu <- refit[[as.character(steps)]]
    }
  }
  #
  # one row per split and cells scored: steps, validation losses of the
  # early-stopping run, reserve and losses of the final network on the
  # observed triangle and on the true lower triangle, and the rolling-origin
  # test error per test cell (4.4) with its baseline: the chain ladder at
  # each valuation date (refit) or the ccODP on the training cells
  # (partition); mu in units of scale
  runs <- NULL
  for (k in names(fits)) {
    fit <- fits[[k]]
    h <- fit$history
    steps <- fit$best_epoch
    tst <- fit$test
    base <- if (grepl("refit", k)) tst$test_loss_ccODP else
      tst$test_loss_ccODP_train
    runs <- rbind(runs, data.frame(
      seed = s,
      split = sub(" .*", "", k),
      cells = sub(".* ", "", k),
      steps = steps,
      vali_start = h$vali[h$epoch == 0],
      vali_steps = h$vali[h$epoch == steps],
      reserve = sum(lower_triangle(fit$mu), na.rm = TRUE),
      loss_in = poisson_deviance(dat_upper, fit$mu),
      loss_out = poisson_deviance(truth, fit$mu),
      test_loss_per_cell = if (is.null(tst)) NA else
        sum(tst$test_loss_bCCNN) / sum(tst$n_test),
      test_loss_per_cell_ccODP = if (is.null(tst)) NA else
        sum(base) / sum(tst$n_test)
    ))
  }
  run_time <- as.numeric(Sys.time() - t0, units = "secs")
  # the losses per step (loss curves) of the claims split and of the final
  # partition of the rolling origin, kept for the first seed
  history <- list(claims_split = h_claims,
                  rolling_origin = lapply(ro$refit, function(r) {
                    r$final$history
                  }))
  saveRDS(list(seed = s,
               param = param,
               run_time = run_time,
               runs = runs,
               rolling_origin = lapply(ro, lapply, `[[`, "summary"),
               mu = lapply(fits, `[[`, "mu"),
               history = if (s == cfg$seed) history),
          seed_file)
  cat(sprintf("%s seed %d: %.0f s, steps %s\n",
              format(Sys.time(), "%H:%M"),
              s,
              run_time,
              paste(runs$steps, collapse = " ")))
}

##########################################
#########  tables
##########################################

fits <- lapply(seeds, function(s) {
  readRDS(file.path(paths$processed, paste0("bccnn_masking_fit_s", s, ".rds")))
})
runs <- rbindlist(lapply(fits, `[[`, "runs"))
runs$split <- factor(runs$split, levels = splits)
runs$vali_decrease_pct <- 100 * (1 - runs$vali_steps / runs$vali_start)
runs$true <- true_total
runs$bias_pct <- 100 * (runs$reserve / true_total - 1)

## the chain ladder (ccODP) on the observed triangle: the start of every
## final network that is refitted
cl <- c("reserve" = sum(odp$reserve_o),
        "bias_pct" = 100 * (sum(odp$reserve_o) / true_total - 1),
        "loss_in" = odp$deviance,
        "loss_out" = poisson_deviance(truth, odp$mu))
round(cl, 4)

## spread over the seeds per split and cells scored
seed_spread <- runs[, .(seeds = .N,
                        steps_mean = mean(steps),
                        steps_sd = sd(steps),
                        steps_min = min(steps),
                        steps_median = median(steps),
                        steps_max = max(steps),
                        vali_start = mean(vali_start),
                        vali_decrease_pct_mean = mean(vali_decrease_pct),
                        bias_pct_mean = mean(bias_pct),
                        bias_pct_sd = sd(bias_pct),
                        loss_in_mean = mean(loss_in),
                        loss_out_mean = mean(loss_out),
                        loss_out_sd = sd(loss_out),
                        test_loss_mean = mean(test_loss_per_cell),
                        test_loss_sd = sd(test_loss_per_cell),
                        test_loss_ccODP = mean(test_loss_per_cell_ccODP)),
                    keyby = .(split, cells)]
cbind(seed_spread[, 1:3], round(seed_spread[, -(1:3)], 4))

## effect of the masking per split: masked minus all cells scored, paired by
## seed; steps_changed and reserve_changed count the seeds with other steps
## and another reserve
both <- merge(runs[cells == "all"],
              runs[cells == "masked"],
              by = c("seed", "split"),
              suffixes = c("_all", "_masked"))
effect <- both[, .(seeds = .N,
                   steps_changed = sum(steps_masked != steps_all),
                   steps_diff_mean = mean(steps_masked - steps_all),
                   steps_diff_max = max(abs(steps_masked - steps_all)),
                   reserve_changed = sum(reserve_masked != reserve_all),
                   bias_pct_diff_mean = mean(bias_pct_masked - bias_pct_all),
                   bias_pct_diff_max = max(abs(bias_pct_masked -
                                                 bias_pct_all)),
                   loss_out_diff_mean = mean(loss_out_masked - loss_out_all),
                   test_loss_diff_mean = mean(test_loss_per_cell_masked -
                                                test_loss_per_cell_all)),
               keyby = split]
cbind(effect[, 1:3], round(effect[, -(1:3)], 4))

fwrite(cell_counts, file.path(tab_dir, "bccnn_masking_cells.csv"))
fwrite(masked, file.path(tab_dir, "bccnn_masking_masked_cells.csv"))
fwrite(runs, file.path(tab_dir, "bccnn_masking_runs.csv"))
fwrite(seed_spread, file.path(tab_dir, "bccnn_masking_seed_spread.csv"))
fwrite(effect, file.path(tab_dir, "bccnn_masking_effect.csv"))

##########################################
#########  figures
##########################################

cells_lab <- c(all = "all cells scored", masked = "masked cells left out")
cells_col <- c("#2a78d6", "#eb6834")   # distinct under colour blindness
split_lab <- c(claims_split = "claims split",
               rolling_origin_refit = "rolling origin, refit",
               rolling_origin_partition = "rolling origin, partition")

## validation losses by gradient descent step of the first seed, as change
## from the ccODP start (the masked cells shift the level): the claims split
## and the final partition of the rolling origin (the same run for refit and
## partition); dotted: the step with the lowest validation loss
h_claims <- fits[[1]]$history$claims_split
h_ro <- fits[[1]]$history$rolling_origin
panel <- c("claims split", "rolling origin, final partition")
curves <- list(h_claims$vali, h_claims$vali_mask,
               h_ro$all$vali, h_ro$masked$vali)
d <- data.frame(epoch = rep(h_claims$epoch, 4),
                change = unlist(lapply(curves, function(v) v - v[1])),
                split = factor(rep(panel, each = 2 * nrow(h_claims)),
                               levels = panel),
                cells = factor(rep(rep(cells_lab, each = nrow(h_claims)), 2),
                               levels = cells_lab))
best <- data.frame(epoch = sapply(curves, which.min) - 1,
                   split = factor(rep(panel, each = 2), levels = panel),
                   cells = factor(rep(cells_lab, 2), levels = cells_lab))
ggsave("bCCNN masking validation losses.png",
       ggplot(d, aes(x = epoch, y = change, colour = cells)) +
         geom_line(aes(linewidth = cells)) +
         geom_vline(data = best,
                    aes(xintercept = epoch, colour = cells, linetype = cells),
                    show.legend = FALSE) +
         scale_colour_manual(values = cells_col, name = NULL) +
         scale_linewidth_manual(values = c(1.2, 0.4), name = NULL) +
         scale_linetype_manual(values = c("dashed", "dotted")) +
         facet_wrap(~split, ncol = 1, scales = "free_y") +
         labs(x = "gradient descent iteration",
              y = "validation loss - validation loss at the ccODP start",
              title = paste("bCCNN early stopping with and without the",
                            "masked cells, seed", cfg$seed)) +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 7, height = 7, dpi = 150)

## steps used and bias of the reserves by split: one point per seed
## (dotted: chain ladder)
measures <- c(steps = "gradient descent steps",
              bias_pct = "bias (% of the true reserves)")
d <- data.frame(split = rep(runs$split, 2),
                cells = factor(rep(cells_lab[runs$cells], 2),
                               levels = cells_lab),
                measure = factor(rep(measures, each = nrow(runs)),
                                 levels = measures),
                value = c(runs$steps, runs$bias_pct))
cl_line <- data.frame(measure = factor(measures[["bias_pct"]],
                                       levels = measures),
                      value = cl[["bias_pct"]])
ggsave("bCCNN masking seed spread.png",
       ggplot(d, aes(x = split, y = value, colour = cells, shape = cells)) +
         geom_hline(data = cl_line,
                    aes(yintercept = value),
                    inherit.aes = FALSE,
                    colour = "grey50",
                    linetype = "dotted") +
         geom_point(position = position_jitterdodge(jitter.width = 0.15,
                                                    jitter.height = 0,
                                                    dodge.width = 0.6,
                                                    seed = cfg$seed),
                    size = 1.6,
                    alpha = 0.8) +
         scale_colour_manual(values = cells_col, name = NULL) +
         scale_shape_manual(values = c(16, 4), name = NULL) +
         scale_x_discrete(labels = split_lab) +
         facet_wrap(~measure, ncol = 1, scales = "free_y") +
         labs(x = NULL,
              y = NULL,
              title = "bCCNN with and without the masked cells, by split",
              subtitle = "points: single seeds; dotted: chain ladder") +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 7, height = 7, dpi = 150)
