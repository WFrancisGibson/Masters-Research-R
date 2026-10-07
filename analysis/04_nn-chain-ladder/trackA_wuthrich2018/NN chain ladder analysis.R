##########################################
#########  NN chain ladder: reserves, tables and figures
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Tables 2-5 and Figures 2-4, 7-9
##########################################

## reads the fits of "NN chain ladder fit.R" (no Keras needed) on the paper's
## four LoBs, the data set machine4: cells in data/interim/machine4, fits in
## data/processed/machine4 (the fits made before the data sets had folders
## of their own: copy them there, see the fit script)
Sys.setenv(DATASET = "machine4", UNIT = "")
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "04_NN-chain-ladder/model")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$data$n_dev                         # I = 12, J = I - 1 = 11
first_ay <- cfg$data$first_ay                  # 1994
units <- cfg$nncl$units                        # EAJ tables in 1'000
ay_lab <- first_ay:(first_ay + n_ay - 1)
features <- c("LoB", "cc", "AQ", "age", "inj_part")
q_grid <- cfg$nncl$model$q
main_run <- paste0("paper_q", cfg$nncl$model$q_main)
run_names <- c(paste0("paper_q", q_grid),
               "s1_adam", "s2_early_stop", "s3_cl_start", "s4_balance")

##########################################
#########  load the cells and the fits
##########################################

cells <- readRDS(file.path(paths$interim, "nncl_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])
homogeneous <- readRDS(file.path(paths$processed, "nncl_homogeneous.rds"))
zero <- readRDS(file.path(paths$processed, "nncl_zero_claims.rds"))
fits <- lapply(setNames(run_names, run_names), function(r) {
  readRDS(file.path(paths$processed, paste0("nncl_fit_", r, ".rds")))$fits
})

## learning cells of development period j and part-1 diagonal cells, as in
## the fit script; latest development year m = I - i of the diagonal cells
learn_rows <- lapply(1:(n_ay - 1), function(j) {
  which(cells$i <= n_ay - j & cum[, j] > 0)
})
diag_rows <- which(cells$i > 1 & cells$c_diag > 0)
m_diag <- n_ay - cells$i[diag_rows]
rows <- which(cells$i > 1)                     # all cells to be reserved
lobs <- sort(unique(cells$LoB))

##########################################
#########  reserves (5.1) and the true outstanding payments
##########################################

## part 1: C_{i,I-i}(x) (prod_{j=I-i}^{J-1} f_j(x) - 1), where network j
## (1..J) gives f_{j-1}; part 2: the zero claims features (Section 4.2)
f_prod <- lapply(fits, function(run) {
  f_diag <- sapply(run, function(fit) fit$f_diag)
  exp(rowSums(ifelse(outer(m_diag, 1:(n_ay - 1), "<"), log(f_diag), 0)))
})
reserves <- lapply(f_prod, function(fp) {
  fp_all <- rep(1, length(rows))
  fp_all[match(diag_rows, rows)] <- fp
  nncl_reserves(cells$LoB[rows],
                cells$i[rows],
                cells$c_diag[rows],
                fp_all,
                zero$ult_zero)
})

## the truth: C_{i,J}(x) - C_{i,I-i}(x) of all claims (incl. those reported
## after 2005), known here because the simulated claims are fully developed
cells$true <- cum[, n_ay] - cells$c_diag
truth <- cells[, .(true = sum(true)), keyby = .(LoB, i)]

## Mack's chain ladder per LoB on the observed triangles (Mack 1993)
tri <- lapply(lobs, function(l) {
  r <- which(cells$LoB == l)
  rowsum(cum[r, ], cells$i[r])                 # full cumulative triangle
})
mack <- lapply(tri, nncl_mack)

##########################################
#########  tables (EAJ Tables 2-5)
##########################################

## Table 4: cumulative payments per LoB (upper triangle) and true ultimates
table4 <- rbindlist(lapply(lobs, function(l) {
  data.table(LoB = l,
             AY = ay_lab,
             round(upper_triangle(unname(tri[[l]])) / units),
             ultimate = round(tri[[l]][, n_ay] / units))
}))
setnames(table4, paste0("V", 1:n_ay), paste0("dev_", 0:(n_ay - 1)))
table4

## Tables 2-3: true outstanding payments, NN reserves (q_main), Mack's CL
## reserves and sqrt(msep), by LoB and accident year, in 1'000
nn <- reserves[[main_run]]
table23 <- rbindlist(lapply(lobs, function(l) {
  res <- data.table(LoB = l,
                    AY = as.character(ay_lab),
                    true = mack[[l]]$by_origin$true,
                    NN = c(0, nn[LoB == l, reserve]),
                    NN_zero_claims = c(0, nn[LoB == l, part2]),
                    CL = mack[[l]]$by_origin$ibnr,
                    msep_sqrt = mack[[l]]$by_origin$se)
  rbind(res, data.table(LoB = l,
                        AY = "total",
                        true = sum(res$true),
                        NN = sum(res$NN),
                        NN_zero_claims = sum(res$NN_zero_claims),
                        CL = sum(res$CL),
                        msep_sqrt = mack[[l]]$total_se))
}))
num_cols <- c("true", "NN", "NN_zero_claims", "CL", "msep_sqrt")
table23[, (num_cols) := lapply(.SD, function(v) round(v / units)),
        .SDcols = num_cols]
table23
## the paper's totals (Tables 2-3), in 1'000
paper_totals <- data.frame(LoB = lobs,
                           true = c(268338, 208376, 214768, 424738),
                           NN = c(267167, 209964, 245378, 418923),
                           CL = c(261342, 194838, 234760, 409843),
                           msep_sqrt = c(4886, 7699, 4736, 6663))
paper_totals

## Table 5: parameters, run times and losses L'_j (6.1) in millions; the
## homogeneous model is Mack's CL factor on the learning cells
paper_loss <- list(
  homogeneous = c(2255.9, 252.9, 51.4, 24.6, 16.9, 8.7, 5.9, 2.0, 1.3, 1.2,
                  0.4),
  paper_q5 = c(1906.5, 224.8, 46.4, 22.8, 16.0, 8.3, 5.7, 1.9, 1.2, 1.1, 0.4),
  paper_q10 = c(1901.8, 224.5, 46.7, 22.8, 16.0, 8.3, 5.7, 1.9, 1.2, 1.1,
                0.4),
  paper_q20 = c(1892.9, 224.1, 46.6, 22.8, 16.1, 8.2, 5.7, 1.9, 1.2, 1.1, 0.4)
)
table5 <- data.table(model = "homogeneous",
                     j = homogeneous$j,
                     parameters = 1,
                     run_time = NA,
                     loss = homogeneous$loss / 1e6,
                     loss_vali = NA,
                     paper_loss = paper_loss$homogeneous)
for (r in paste0("paper_q", q_grid)) {
  table5 <- rbind(table5,
                  data.table(model = r,
                             j = 1:(n_ay - 1),
                             parameters = sapply(fits[[r]], `[[`, "n_par"),
                             run_time = sapply(fits[[r]], `[[`, "run_time"),
                             loss = sapply(fits[[r]], `[[`, "loss") / 1e6,
                             loss_vali = sapply(fits[[r]], `[[`,
                                                "loss_vali") / 1e6,
                             paper_loss = paper_loss[[r]]))
}
table5$model <- factor(table5$model, levels = unique(table5$model))
dcast(table5[, .(model, j, loss = round(loss, 1))],
      model ~ j,
      value.var = "loss")

## sensitivity runs: paper (q_main) and S1-S4, each adding one change;
## epochs used/run per j, losses and reserves by LoB against the truth, in
## 1'000
true_lob <- truth[i > 1, .(true = sum(true)), keyby = LoB]
sensitivity <- NULL
for (r in c(main_run, run_names[-seq_along(q_grid)])) {
  res <- reserves[[r]][, .(reserve = sum(reserve), zero = sum(part2)),
                       keyby = LoB]
  sensitivity <- rbind(
    sensitivity,
    data.table(run = r,
               LoB = c(lobs, "total"),
               true = c(true_lob$true, sum(true_lob$true)) / units,
               reserve = c(res$reserve, sum(res$reserve)) / units,
               zero_claims = c(res$zero, sum(res$zero)) / units,
               loss = sum(sapply(fits[[r]], `[[`, "loss")) / 1e6,
               loss_vali = sum(sapply(fits[[r]], `[[`, "loss_vali")) / 1e6,
               epochs = paste(sapply(fits[[r]], function(fit) {
                 paste0(fit$epochs_used, "/", fit$epochs_run)
               }),
               collapse = " "))
  )
}
sensitivity$bias_pct <- 100 * (sensitivity$reserve / sensitivity$true - 1)
sensitivity[, c("true", "reserve", "zero_claims", "loss", "loss_vali",
                "bias_pct") := lapply(.SD, round, 1),
            .SDcols = c("true", "reserve", "zero_claims", "loss",
                        "loss_vali", "bias_pct")]
sensitivity

fwrite(table4, file.path(tab_dir, "nncl_table4_triangles.csv"))
fwrite(table23, file.path(tab_dir, "nncl_tables2_3_reserves.csv"))
fwrite(table5, file.path(tab_dir, "nncl_table5_losses.csv"))
fwrite(sensitivity, file.path(tab_dir, "nncl_sensitivity_runs.csv"))
fwrite(zero$factors, file.path(tab_dir, "nncl_zero_claims_factors.csv"))

##########################################
#########  figures (EAJ Figures 2-4 and 7-9)
##########################################

fig_dir <- file.path(paths$figures, "04_NN-chain-ladder/model")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

## Figs. 2-4: part-1 NN reserves (q_main) by label against the true
## outstanding payments of the same cells (C_{i,I-i}(x) > 0, over all LoBs);
## the zero claims reserve has no feature split and is left out
part1 <- data.table(cells[diag_rows, c("cc", "age", "inj_part")],
                    nn = cells$c_diag[diag_rows] * (f_prod[[main_run]] - 1),
                    true = cells$true[diag_rows])
by_label <- function(v) {
  part1[, .(panel = v, nn = sum(nn), true = sum(true)),
        keyby = .(label = get(v))]
}
note <- paste0("part-1 cells; zero claims reserve not split: ",
               format(round(sum(nn$part2) / units), big.mark = ","),
               " (1'000)")
ggsave("NNCL Fig 2 reserves by cc.png",
       nncl_reserves_by_label_plot(by_label("cc"),
                                   paste("NN reserves by cc (EAJ Fig. 2),",
                                         note)),
       path = fig_dir, width = 9, height = 4.5, dpi = 150)
ggsave("NNCL Fig 3 reserves by inj_part.png",
       nncl_reserves_by_label_plot(by_label("inj_part"),
                                   paste("NN reserves by inj_part",
                                         "(EAJ Fig. 3),", note)),
       path = fig_dir, width = 9, height = 4.5, dpi = 150)
ggsave("NNCL Fig 4 relative reserves.png",
       nncl_reserves_by_label_plot(rbind(by_label("cc"),
                                         by_label("age"),
                                         by_label("inj_part")),
                                   "NN reserves / true reserves (EAJ Fig. 4)",
                                   relative = TRUE),
       path = fig_dir, width = 9, height = 9, dpi = 150)

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
ggsave("NNCL Fig 7 losses j1.png",
       ggplot(loss_j1, aes(x = epoch, y = loss, colour = data)) +
         geom_point(size = 0.8) +
         facet_wrap(~run, scales = "free_y") +
         scale_colour_manual(values = c("red", "darkgreen"), name = NULL) +
         labs(title = "Keras mse losses for j = 1 (EAJ Fig. 7)") +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 9, height = 4.5, dpi = 150)

## Figs. 8-9: sensitivities (3.9) of f_{j-1}(x) (q_main) on the learning
## cells, weighted by C_{i,j-1}(x); age in 5-year bands
sens <- NULL
avg <- NULL
for (j in 1:(n_ay - 1)) {
  r <- learn_rows[[j]]
  d_j <- data.table(f = fits[[main_run]][[j]]$f_learn,
                    w = cum[r, j],
                    cells[r, features, with = FALSE])
  d_j$age <- 5 * floor(d_j$age / 5)
  avg <- rbind(avg, data.table(j = j, f = sum(d_j$f * d_j$w) / sum(d_j$w)))
  for (v in features) {
    sens <- rbind(sens,
                  d_j[, .(j = j, feature = v, f = sum(f * w) / sum(w)),
                      keyby = .(label = get(v))])
  }
}
ggsave("NNCL Fig 8 sensitivities j1-5.png",
       nncl_sensitivity_plot(sens[j <= 5], avg[j <= 5],
                             "CL factor sensitivities, j = 1..5 (EAJ Fig. 8)"),
       path = fig_dir, width = 12, height = 11, dpi = 150)
ggsave("NNCL Fig 9 sensitivities j6-11.png",
       nncl_sensitivity_plot(sens[j > 5], avg[j > 5],
                             "CL factor sensitivities, j = 6..11 (EAJ Fig. 9)"),
       path = fig_dir, width = 12, height = 13, dpi = 150)
