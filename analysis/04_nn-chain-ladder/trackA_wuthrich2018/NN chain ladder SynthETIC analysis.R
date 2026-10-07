##########################################
#########  NN chain ladder on the SynthETIC portfolio: reserves, tables
#########  and figures
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Tables 2-5 and Figures 2-4, 7-9
##########################################

## reads the cells of "NN chain ladder SynthETIC cells.R" and the fits of
## "NN chain ladder SynthETIC fit.R" (no Keras needed); Age of Claimant as
## four dummies or as an ordinal score (R_CONFIG_ACTIVE=age_numeric): the
## fits (tag) and outputs (out_dir) of the two codings are apart
source(here::here("analysis", "00_setup.R"))
stopifnot(cfg$data$generator == "synthetic")
tag <- cfg$nncl$synthetic$tag
out_dir <- file.path("04_NN-chain-ladder", cfg$nncl$synthetic$out_dir)
tab_dir <- file.path(paths$tables, out_dir)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # tables in millions
vali_split <- cfg$nncl$training$validation_split
features <- c("Legal Representation", "Injury Severity", "Age of Claimant",
              "Vehicle type", "Business use")
q_grid <- cfg$nncl$model$q
main_run <- paste0("paper_q", cfg$nncl$model$q_main)
run_names <- c(paste0("paper_q", q_grid),
               "s1_adam", "s2_early_stop", "s3_cl_start", "s4_balance")
fit_file <- function(run) {
  file.path(paths$processed, paste0(tag, "_fit_", run, ".rds"))
}

## hidden layers and optimisers (own design, not in the paper): every
## combination of hidden layers, optimiser and training with every seed, as
## in the fit script
grid_cfg <- cfg$nncl$grid
seeds <- cfg$seed + seq_len(grid_cfg$seeds) - 1
grid <- CJ(hidden = sapply(grid_cfg$hidden, paste, collapse = "-"),
           optimizer = grid_cfg$optimizers,
           training = grid_cfg$training,
           seed = seeds,
           sorted = FALSE)
grid$learning_rate <- unname(unlist(grid_cfg$learning_rate)[grid$optimizer])
grid$run <- paste0("grid_", grid$hidden, "_", grid$optimizer, "_",
                   grid$training, "_s", grid$seed)

## nagging predictors (Richman & Wuthrich 2020), one per combination and
## block of 'nagging' seeds
blocks <- split(seeds, ceiling(seq_along(seeds) / grid_cfg$nagging))
nag <- CJ(hidden = unique(grid$hidden),
          optimizer = unique(grid$optimizer),
          training = unique(grid$training),
          block = seq_along(blocks),
          sorted = FALSE)
nag$seeds <- unname(sapply(blocks[nag$block], function(s) {
  paste(range(s), collapse = "-")
}))
nag$run <- paste0("nag_", nag$hidden, "_", nag$optimizer, "_", nag$training,
                  "_b", nag$block)

## the grid can be under way (the final run fits it after the main runs,
## seed by seed: nncl_runs()): the blocks of seeds fitted in full enter, the
## first one at half of a grid of two blocks, and without one the tables and
## the figure of the grid are left out
full <- sapply(blocks, function(s) {
  all(file.exists(fit_file(grid$run[grid$seed %in% s])))
})
grid <- grid[seed %in% unlist(blocks[full])]
nag <- nag[block %in% which(full)]
c("runs of the grid" = nrow(grid), "nagging predictors" = nrow(nag))

##########################################
#########  load the cells and the fits
##########################################

## cells, feature value x_id of every cell, learning cells of development
## period j and part-1 diagonal cells of the cells script; latest
## development year m = I - i of the diagonal cells
cells <- readRDS(file.path(paths$interim, "nncl_synthetic_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])
inputs <- readRDS(file.path(paths$interim, paste0(tag, "_inputs.rds")))
x_id <- inputs$x_id
learn_rows <- inputs$learn_rows
diag_rows <- inputs$diag_rows
m_diag <- n_ay - cells$i[diag_rows]
rows <- which(cells$i > 1)                     # all cells to be reserved
homogeneous <- readRDS(file.path(paths$processed,
                                 "nncl_synthetic_homogeneous.rds"))
zero <- readRDS(file.path(paths$processed, "nncl_synthetic_zero_claims.rds"))

## per run the networks j = 1..J (losses, epochs, times) and f_x, the CL
## factors f_{j-1}(x) of the feature values (feature values x networks): the
## factor of a cell is row x_id
fits <- list()
f_x <- list()
for (r in c(run_names, grid$run)) {
  run <- readRDS(fit_file(r))
  fits[[r]] <- run$fits
  f_x[[r]] <- run$f_x
}

## nagging predictor: the CL factors f_{j-1}(x) of the networks of a block
## averaged, per development period j; its losses L'_j (6.1) on the learning
## cells and on Keras's validation rows
for (k in seq_len(nrow(nag))) {
  members <- f_x[grid$run[grid$hidden == nag$hidden[k] &
                            grid$optimizer == nag$optimizer[k] &
                            grid$training == nag$training[k] &
                            grid$seed %in% blocks[[nag$block[k]]]]]
  f_nag <- sapply(1:(n_ay - 1), function(j) {
    rowMeans(sapply(members, function(f) f[, j]))
  })
  f_x[[nag$run[k]]] <- f_nag
  fits[[nag$run[k]]] <- lapply(1:(n_ay - 1), function(j) {
    r <- learn_rows[[j]]
    res2 <- (cum[r, j + 1] - f_nag[x_id[r], j] * cum[r, j])^2 / cum[r, j]
    train <- seq_len(floor(length(r) * (1 - vali_split)))
    list(loss = sum(res2), loss_vali = sum(res2[-train]))
  })
}

##########################################
#########  reserves (5.1) and the true outstanding payments
##########################################

## part 1: C_{i,I-i}(x) (prod_{j=I-i}^{J-1} f_j(x) - 1), where network j
## (1..J) gives f_{j-1}; part 2: the zero claims features (Section 4.2);
## the portfolio is one LoB; a run with a diverged network (CL factors not
## finite) has no reserves
f_prod <- lapply(f_x, function(f) {
  f_diag <- f[x_id[diag_rows], ]
  exp(rowSums(ifelse(outer(m_diag, 1:(n_ay - 1), "<"), log(f_diag), 0)))
})
reserves <- lapply(f_prod, function(fp) {
  if (!all(is.finite(fp))) return(NULL)
  fp_all <- rep(1, length(rows))
  fp_all[match(diag_rows, rows)] <- fp
  nncl_reserves(rep(1, length(rows)),
                cells$i[rows],
                cells$c_diag[rows],
                fp_all,
                zero$ult_zero)
})
## networks with CL factors of the diagonal cells that are not finite
diverged <- sapply(f_x, function(f) {
  sum(colSums(!is.finite(f[x_id[diag_rows], ])) > 0)
})

## the truth: C_{i,J}(x) - C_{i,I-i}(x) of all claims (incl. those reported
## after year I), the true reserves of the Mack and bCCNN scripts
cells$true <- cum[, n_ay] - cells$c_diag

## Mack's chain ladder on the observed triangle (Mack 1993)
tri <- rowsum(cum, cells$i)                    # full cumulative triangle
mack <- nncl_mack(tri)

##########################################
#########  tables (EAJ Tables 2-5)
##########################################

## Table 4: cumulative payments (upper triangle) and true ultimates
table4 <- data.table(AY = 1:n_ay,
                     round(upper_triangle(unname(tri)) / units, 1),
                     ultimate = round(tri[, n_ay] / units, 1))
setnames(table4, paste0("V", 1:n_ay), paste0("dev_", 0:(n_ay - 1)))
table4

## Tables 2-3: true outstanding payments, NN reserves (q_main), Mack's CL
## reserves and sqrt(msep), by accident year, in millions
nn <- reserves[[main_run]]
table23 <- data.table(AY = as.character(1:n_ay),
                      true = mack$by_origin$true,
                      NN = c(0, nn$reserve),
                      NN_zero_claims = c(0, nn$part2),
                      CL = mack$by_origin$ibnr,
                      msep_sqrt = mack$by_origin$se)
table23 <- rbind(table23,
                 data.table(AY = "total",
                            true = sum(table23$true),
                            NN = sum(table23$NN),
                            NN_zero_claims = sum(table23$NN_zero_claims),
                            CL = sum(table23$CL),
                            msep_sqrt = mack$total_se))
num_cols <- c("true", "NN", "NN_zero_claims", "CL", "msep_sqrt")
table23[, (num_cols) := lapply(.SD, function(v) round(v / units, 1)),
        .SDcols = num_cols]
table23

## zero claims features (Section 4.2) by accident year: the diagonal cells
## with C_{i,I-i}(x) = 0, their claims and true outstanding payments, and the
## zero claims reserve (part 2 of (5.1), from the total volume C_{i,I-i})
zero_cells <- cells[i > 1,
                    .(cells = .N,
                      zero_cells = sum(c_diag <= 0),
                      zero_claims = sum(n_claims[c_diag <= 0]),
                      true = sum(true[c_diag <= 0]) / units),
                    keyby = i]
zero_cells$NN_zero_claims <- nn$part2 / units
cbind(zero_cells[, 1:4], round(zero_cells[, 5:6], 1))

## Table 5: parameters, run times and losses L'_j (6.1) in millions; the
## homogeneous model is Mack's CL factor on the learning cells
table5 <- data.table(model = "homogeneous",
                     j = homogeneous$j,
                     n_cells = homogeneous$n_cells,
                     parameters = 1,
                     run_time = NA,
                     loss = homogeneous$loss / units,
                     loss_vali = NA)
for (r in paste0("paper_q", q_grid)) {
  table5 <- rbind(table5,
                  data.table(model = r,
                             j = 1:(n_ay - 1),
                             n_cells = homogeneous$n_cells,
                             parameters = sapply(fits[[r]], `[[`, "n_par"),
                             run_time = sapply(fits[[r]], `[[`, "run_time"),
                             loss = sapply(fits[[r]], `[[`, "loss") / units,
                             loss_vali = sapply(fits[[r]], `[[`,
                                                "loss_vali") / units))
}
table5$model <- factor(table5$model, levels = unique(table5$model))
dcast(table5[, .(model, j, loss = round(loss, 1))],
      model ~ j,
      value.var = "loss")

## sensitivity runs: paper (q = 5, 10, 20) and S1-S4, each adding one
## change; epochs used/run per j, losses and reserves against the truth and
## Mack's CL reserves, in millions; zero_claims_pooled: the zero claims
## reserve of the accident years with a zero claims factor that took the
## ratio pooled over the accident years (own rule, not in the paper)
true_total <- sum(cells$true[rows])
pooled_ay <- unique(zero$factors$i[zero$factors$pooled])
sensitivity <- NULL
for (r in run_names) {
  res <- reserves[[r]]
  sensitivity <- rbind(
    sensitivity,
    data.table(run = r,
               true = true_total / units,
               CL = sum(mack$by_origin$ibnr) / units,
               reserve = sum(res$reserve) / units,
               zero_claims = sum(res$part2) / units,
               zero_claims_pooled = sum(res$part2[res$i %in% pooled_ay]) /
                 units,
               loss = sum(sapply(fits[[r]], `[[`, "loss")) / units,
               loss_vali = sum(sapply(fits[[r]], `[[`, "loss_vali")) / units,
               epochs = paste(sapply(fits[[r]], function(fit) {
                 paste0(fit$epochs_used, "/", fit$epochs_run)
               }),
               collapse = " "))
  )
}
sensitivity$bias_pct <- 100 * (sensitivity$reserve / sensitivity$true - 1)
sensitivity$bias_cl_pct <- 100 * (sensitivity$CL / sensitivity$true - 1)
round_cols <- setdiff(names(sensitivity), c("run", "epochs"))
sensitivity[, (round_cols) := lapply(.SD, round, 1), .SDcols = round_cols]
sensitivity[, !"epochs"]

fwrite(table4, file.path(tab_dir, "nncl_synthetic_table4_triangle.csv"))
fwrite(table23, file.path(tab_dir, "nncl_synthetic_tables2_3_reserves.csv"))
fwrite(table5, file.path(tab_dir, "nncl_synthetic_table5_losses.csv"))
fwrite(sensitivity, file.path(tab_dir, "nncl_synthetic_sensitivity_runs.csv"))
fwrite(zero$factors,
       file.path(tab_dir, "nncl_synthetic_zero_claims_factors.csv"))
fwrite(zero_cells, file.path(tab_dir, "nncl_synthetic_zero_claims_cells.csv"))

##########################################
#########  figures (EAJ Figures 2-4 and 7-9)
##########################################

fig_dir <- file.path(paths$figures, out_dir)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

## Figs. 2-4: part-1 NN reserves (q_main) by label against the true
## outstanding payments of the same cells (C_{i,I-i}(x) > 0); the zero
## claims reserve has no feature split and is left out
part1 <- data.table(cells[diag_rows, features, with = FALSE],
                    nn = cells$c_diag[diag_rows] * (f_prod[[main_run]] - 1),
                    true = cells$true[diag_rows])
by_label <- rbindlist(lapply(features, function(v) {
  part1[, .(panel = v, nn = sum(nn), true = sum(true)),
        keyby = .(label = as.character(get(v)))]
}))
note <- paste0("part-1 cells; zero claims reserve not split: ",
               round(sum(nn$part2) / units, 1),
               " (millions)")
ggsave("NNCL SynthETIC Fig 2-3 reserves by label.png",
       nncl_reserves_by_label_plot(by_label,
                                   paste("NN reserves by label",
                                         "(EAJ Figs. 2-3),", note)),
       path = fig_dir, width = 9, height = 12, dpi = 150)
ggsave("NNCL SynthETIC Fig 4 relative reserves.png",
       nncl_reserves_by_label_plot(by_label,
                                   "NN reserves / true reserves (EAJ Fig. 4)",
                                   relative = TRUE),
       path = fig_dir, width = 9, height = 12, dpi = 150)

## Fig. 7: training (in-sample) and validation losses per epoch, j = 1
loss_j1 <- NULL
for (r in paste0("paper_q", q_grid[c(1, length(q_grid))])) {
  h <- fits[[r]][[1]]$history
  loss_j1 <- rbind(loss_j1,
                   data.table(run = r,
                              epoch = rep(h$epoch, 2),
                              loss = c(h$loss, h$val_loss),
                              data = rep(c("training", "validation"),
                                         each = nrow(h))))
}
loss_j1$run <- factor(loss_j1$run,
                      levels = unique(loss_j1$run),
                      labels = paste("q =", q_grid[c(1, length(q_grid))]))
ggsave("NNCL SynthETIC Fig 7 losses j1.png",
       ggplot(loss_j1, aes(x = epoch, y = loss, colour = data)) +
         geom_point(size = 0.8) +
         facet_wrap(~run, scales = "free_y") +
         scale_colour_manual(values = c("red", "darkgreen"), name = NULL) +
         labs(title = "Keras mse losses for j = 1 (EAJ Fig. 7)") +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 9, height = 4.5, dpi = 150)

## Figs. 8-9: sensitivities (3.9) of f_{j-1}(x) (q_main) on the learning
## cells, weighted by C_{i,j-1}(x)
sens <- NULL
avg <- NULL
for (j in 1:(n_ay - 1)) {
  r <- learn_rows[[j]]
  d_j <- data.table(f = f_x[[main_run]][x_id[r], j],
                    w = cum[r, j],
                    cells[r, features, with = FALSE])
  avg <- rbind(avg, data.table(j = j, f = sum(d_j$f * d_j$w) / sum(d_j$w)))
  for (v in features) {
    sens <- rbind(sens,
                  d_j[, .(j = j, feature = v, f = sum(f * w) / sum(w)),
                      keyby = .(label = as.character(get(v)))])
  }
}
j_split <- list(1:6, 7:12, 13:(n_ay - 1))
for (js in j_split) {
  lab <- paste0("j", min(js), "-", max(js))
  ggsave(paste0("NNCL SynthETIC Fig 8-9 sensitivities ", lab, ".png"),
         nncl_sensitivity_plot(sens[j %in% js],
                               avg[j %in% js],
                               paste0("CL factor sensitivities, j = ",
                                      min(js), "..", max(js),
                                      " (EAJ Figs. 8-9)")),
         path = fig_dir, width = 12, height = 13, dpi = 150)
}

##########################################
#########  hidden layers and optimisers: tables and figure
##########################################

## left out while no block of seeds of the grid is fitted in full
if (nrow(grid) > 0) {
  ## all runs of the grid: parameters of the network of j = 1, run time,
  ## epochs used/run and networks diverged over the J networks, losses and
  ## reserves against the truth (bias of Mack's CL: bias_cl_pct above); the
  ## homogeneous model's loss for comparison
  grid$parameters <- sapply(fits[grid$run], function(run) run[[1]]$n_par)
  for (k in c("run_time", "epochs_used", "epochs_run", "loss", "loss_vali")) {
    grid[[k]] <- sapply(fits[grid$run], function(run) {
      sum(sapply(run, `[[`, k))
    })
  }
  grid$diverged <- diverged[grid$run]
  grid$loss <- grid$loss / units
  grid$loss_vali <- grid$loss_vali / units
  grid$loss_hom <- sum(homogeneous$loss) / units
  grid$true <- true_total / units
  grid$reserve <- sapply(reserves[grid$run], function(res) {
    if (is.null(res)) NA else sum(res$reserve)
  }) / units
  grid$bias_pct <- 100 * (grid$reserve / grid$true - 1)

  ## nagging predictors: networks diverged over the J development periods,
  ## losses and reserves against the truth
  nag$diverged <- diverged[nag$run]
  for (k in c("loss", "loss_vali")) {
    nag[[k]] <- sapply(fits[nag$run], function(run) {
      sum(sapply(run, `[[`, k))
    }) / units
  }
  nag$true <- true_total / units
  nag$reserve <- sapply(reserves[nag$run], function(res) {
    if (is.null(res)) NA else sum(res$reserve)
  }) / units
  nag$bias_pct <- 100 * (nag$reserve / nag$true - 1)

  ## spread over the seeds: reserves and bias of the single networks (a
  ## diverged run left out), closer_than_cl the share of the seeds with a
  ## smaller absolute bias than Mack's CL; next to them the bias of the
  ## nagging predictors (one column per block of seeds)
  cl_total <- sum(mack$by_origin$ibnr) / units
  seed_spread <- grid[, .(seeds = .N,
                          diverged = sum(diverged > 0),
                          reserve_mean = mean(reserve, na.rm = TRUE),
                          reserve_sd = sd(reserve, na.rm = TRUE),
                          bias_pct_mean = mean(bias_pct, na.rm = TRUE),
                          bias_pct_sd = sd(bias_pct, na.rm = TRUE),
                          bias_pct_min = min(bias_pct, na.rm = TRUE),
                          bias_pct_median = median(bias_pct, na.rm = TRUE),
                          bias_pct_max = max(bias_pct, na.rm = TRUE),
                          closer_than_cl = mean(abs(reserve - true) <
                                                  abs(cl_total - true),
                                                na.rm = TRUE)),
                      by = .(hidden, optimizer, training)]
  nag_wide <- dcast(nag, hidden + optimizer + training ~ block,
                    value.var = "bias_pct")
  setnames(nag_wide,
           as.character(which(full)),
           paste0("nagging_bias_pct_", which(full)))
  seed_spread <- merge(seed_spread, nag_wide, sort = FALSE)
  round_cols <- setdiff(names(seed_spread),
                        c("hidden", "optimizer", "training", "seeds",
                          "diverged"))
  seed_spread[, (round_cols) := lapply(.SD, round, 2), .SDcols = round_cols]
  print(seed_spread[order(training)])

  round_cols <- c("loss", "loss_vali", "true", "reserve", "bias_pct")
  nag[, (round_cols) := lapply(.SD, round, 1), .SDcols = round_cols]

  round_cols <- c("run_time", "loss", "loss_vali", "loss_hom", "true",
                  "reserve", "bias_pct")
  grid[, (round_cols) := lapply(.SD, round, 1), .SDcols = round_cols]
  print(grid[seed == cfg$seed, !c("run", "seed", "true", "loss_hom")])
  ## bias in % of the true reserves (first seed)
  print(dcast(grid[seed == cfg$seed],
              optimizer ~ training + hidden,
              value.var = "bias_pct"))

  fwrite(grid, file.path(tab_dir, "nncl_synthetic_layers_optimisers.csv"))
  fwrite(seed_spread, file.path(tab_dir, "nncl_synthetic_seed_spread.csv"))
  fwrite(nag, file.path(tab_dir, "nncl_synthetic_nagging.csv"))

  ## bias of the reserves in % of the true reserves by training, one point
  ## per seed and a diamond per nagging predictor (dotted: Mack's CL); a
  ## diverged run has no point; the axis is linear near 0 and logarithmic
  ## beyond (pseudo-log)
  hidden_lab <- unique(grid$hidden)
  grid$optimizer <- factor(grid$optimizer, levels = grid_cfg$optimizers)
  grid$hidden <- factor(grid$hidden, levels = hidden_lab)
  nag$optimizer <- factor(nag$optimizer, levels = grid_cfg$optimizers)
  nag$hidden <- factor(nag$hidden, levels = hidden_lab)
  for (tr in unique(grid$training)) {
    ggsave(paste0("NNCL SynthETIC layers and optimisers bias ", tr, ".png"),
           ggplot(grid[training == tr],
                  aes(x = optimizer, y = bias_pct, colour = hidden)) +
             geom_hline(yintercept = 0, colour = "grey50") +
             geom_hline(yintercept = sensitivity$bias_cl_pct[1],
                        colour = "grey50",
                        linetype = "dotted") +
             geom_point(position = position_jitterdodge(jitter.width = 0.15,
                                                        dodge.width = 0.7),
                        size = 0.9,
                        alpha = 0.7) +
             geom_point(data = nag[training == tr],
                        aes(fill = hidden),
                        position = position_dodge(width = 0.7),
                        shape = 23,
                        colour = "black",
                        size = 2.2) +
             scale_y_continuous(transform =
                                  scales::pseudo_log_trans(sigma = 5),
                                breaks = c(-100, -50, -20, -10, -5, -2, 0, 2,
                                           5, 10, 20, 50, 100, 200, 500, 1000,
                                           10000, 100000)) +
             guides(fill = "none") +
             labs(x = NULL,
                  y = "bias (% of the true reserves)",
                  colour = "hidden layers",
                  title = paste0("NN reserves by hidden layers and ",
                                 "optimiser, training ", tr),
                  subtitle = paste("points: single seeds; diamonds: nagging",
                                   "predictors of", grid_cfg$nagging,
                                   "networks")) +
             theme_bw() + theme(legend.position = "top"),
           path = fig_dir, width = 10, height = 5.5, dpi = 150)
  }
}
