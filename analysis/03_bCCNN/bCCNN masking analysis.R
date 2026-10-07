##########################################
#########  bCCNN on the claims triangle: periods without payments masked
#########  or scored in the early stopping and the test error, tables and
#########  figures (own design, not in Paper C)
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3.3;
#########  rolling origin and test error: Al-Mudafer, Avanzi, Taylor & Wong
#########  (2021), Section 3.1 and eq. (4.4)
##########################################

## reads the fits of all seeds of "bCCNN masking fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

n <- cfg$data$n_dev
scale <- cfg$data$scale            # tables in units of scale
ro_cfg <- cfg$data$rolling_origin
seeds <- cfg$seed + seq_len(cfg$bccnn$masking$seeds) - 1
splits <- c("claims_split", "rolling_origin_refit", "rolling_origin_partition")

##########################################
#########  triangles
##########################################

## observed triangle, true lower triangle, the halves of the claims split
## and the rolling-origin partitions, all cells and without the masked ones,
## as in the fit script; in units of scale
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
dat_upper <- sets$upper / scale
truth <- sets$test / scale          # true outstanding payments (lower triangle)
true_total <- sum(truth, na.rm = TRUE)
odp <- ccodp_fit(dat_upper)
train <- sets$train / scale
vali <- sets$vali / scale
vali_mask <- mask_zero_periods(vali, train)
odp_train <- ccodp_fit(train)
parts <- rolling_origin(dat_upper,
                        ro_cfg$test_periods,
                        ro_cfg$vali_periods,
                        ro_cfg$exclude)
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
