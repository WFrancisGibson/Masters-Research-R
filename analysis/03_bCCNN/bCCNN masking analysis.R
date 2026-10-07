##########################################
#########  bCCNN on the claims triangle: periods without payments masked
#########  or scored in the early stopping, tables and figures (own design,
#########  not in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3.3
##########################################

## reads the fits of all seeds of "bCCNN masking fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

scale <- cfg$data$scale            # tables in units of scale
seeds <- cfg$seed + seq_len(cfg$bccnn$masking$seeds) - 1

##########################################
#########  triangles
##########################################

## observed triangle, true lower triangle and the halves of the claims split
## (Paper C Section 3.3.2), all validation cells and without the masked
## ones, as in the fit script; in units of scale
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
true_total <- sum(truth, na.rm = TRUE)
odp <- ccodp_fit(dat_upper)
train <- sets$train / scale
vali <- sets$vali / scale
vali_mask <- mask_zero_periods(vali, train)
odp_train <- ccodp_fit(train)

##########################################
#########  cells masked
##########################################

## validation cells of the claims split and those masked
cell_counts <- data.frame(n_vali = sum(!is.na(vali)),
                          vali_masked = sum(!is.na(vali)) -
                            sum(!is.na(vali_mask)))
cell_counts

## the masked cells: their payment, the mean of the ccODP of the training
## half they are scored against at the start of the network (14) and their
## Poisson deviance (4) at that start
cell <- which(!is.na(vali) & is.na(vali_mask), arr.ind = TRUE)
y <- vali[cell]
mu <- odp_train$mu[cell]
masked <- data.frame(origin = cell[, 1],
                     dev = cell[, 2],
                     payment = y,
                     mu_ccODP = mu,
                     deviance = 2 * (mu - y +
                                       ifelse(y > 0, y * log(y / mu), 0)))
rownames(masked) <- NULL
masked

##########################################
#########  tables
##########################################

## one row per seed and cells scored (all, masked)
fits <- lapply(seeds, function(s) {
  readRDS(file.path(paths$processed, paste0("bccnn_masking_fit_s", s, ".rds")))
})
runs <- rbindlist(lapply(fits, `[[`, "runs"))
runs$vali_decrease_pct <- 100 * (1 - runs$vali_steps / runs$vali_start)
runs$true <- true_total
runs$bias_pct <- 100 * (runs$reserve / true_total - 1)

## the chain ladder (ccODP) on the observed triangle: the start of every
## final network
cl <- c("reserve" = sum(odp$reserve_o),
        "bias_pct" = 100 * (sum(odp$reserve_o) / true_total - 1),
        "loss_in" = odp$deviance,
        "loss_out" = poisson_deviance(truth, odp$mu))
round(cl, 4)

## spread over the seeds per cells scored
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
                        loss_out_sd = sd(loss_out)),
                    keyby = cells]
cbind(seed_spread[, 1:2], round(seed_spread[, -(1:2)], 4))

## effect of the masking: masked minus all cells scored, paired by seed;
## steps_changed and reserve_changed count the seeds with other steps and
## another reserve
both <- merge(runs[cells == "all"],
              runs[cells == "masked"],
              by = "seed",
              suffixes = c("_all", "_masked"))
effect <- both[, .(seeds = .N,
                   steps_changed = sum(steps_masked != steps_all),
                   steps_diff_mean = mean(steps_masked - steps_all),
                   steps_diff_max = max(abs(steps_masked - steps_all)),
                   reserve_changed = sum(reserve_masked != reserve_all),
                   bias_pct_diff_mean = mean(bias_pct_masked - bias_pct_all),
                   bias_pct_diff_max = max(abs(bias_pct_masked -
                                                 bias_pct_all)),
                   loss_out_diff_mean = mean(loss_out_masked - loss_out_all))]
cbind(effect[, 1:2], round(effect[, -(1:2)], 4))

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

## validation losses of the claims split by gradient descent step of the
## first seed, as change from the ccODP start (the masked cells shift the
## level); dotted: the step with the lowest validation loss
h_claims <- fits[[1]]$history
curves <- list(h_claims$vali, h_claims$vali_mask)
d <- data.frame(epoch = rep(h_claims$epoch, 2),
                change = unlist(lapply(curves, function(v) v - v[1])),
                cells = factor(rep(cells_lab, each = nrow(h_claims)),
                               levels = cells_lab))
best <- data.frame(epoch = sapply(curves, which.min) - 1,
                   cells = factor(cells_lab, levels = cells_lab))
ggsave("bCCNN masking validation losses.png",
       ggplot(d, aes(x = epoch, y = change, colour = cells)) +
         geom_line(aes(linewidth = cells)) +
         geom_vline(data = best,
                    aes(xintercept = epoch, colour = cells, linetype = cells),
                    show.legend = FALSE) +
         scale_colour_manual(values = cells_col, name = NULL) +
         scale_linewidth_manual(values = c(1.2, 0.4), name = NULL) +
         scale_linetype_manual(values = c("dashed", "dotted")) +
         labs(x = "gradient descent iteration",
              y = "validation loss - validation loss at the ccODP start",
              title = "bCCNN early stopping with and without the masked cells",
              subtitle = paste("claims split, seed", cfg$seed)) +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 7, height = 5, dpi = 150)

## steps used and bias of the reserves by cells scored: one point per seed
## (dotted: chain ladder)
measures <- c(steps = "gradient descent steps",
              bias_pct = "bias (% of the true reserves)")
d <- data.frame(cells = factor(rep(cells_lab[runs$cells], 2),
                               levels = cells_lab),
                measure = factor(rep(measures, each = nrow(runs)),
                                 levels = measures),
                value = c(runs$steps, runs$bias_pct))
cl_line <- data.frame(measure = factor(measures[["bias_pct"]],
                                       levels = measures),
                      value = cl[["bias_pct"]])
ggsave("bCCNN masking seed spread.png",
       ggplot(d, aes(x = cells, y = value, colour = cells, shape = cells)) +
         geom_hline(data = cl_line,
                    aes(yintercept = value),
                    inherit.aes = FALSE,
                    colour = "grey50",
                    linetype = "dotted") +
         geom_point(position = position_jitter(width = 0.15,
                                               height = 0,
                                               seed = cfg$seed),
                    size = 1.6,
                    alpha = 0.8) +
         scale_colour_manual(values = cells_col, name = NULL) +
         scale_shape_manual(values = c(16, 4), name = NULL) +
         facet_wrap(~measure, ncol = 1, scales = "free_y") +
         labs(x = NULL,
              y = NULL,
              title = paste("bCCNN under the claims split with and without",
                            "the masked cells"),
              subtitle = "points: single seeds; dotted: chain ladder") +
         theme_bw() + theme(legend.position = "none"),
       path = fig_dir, width = 7, height = 7, dpi = 150)
