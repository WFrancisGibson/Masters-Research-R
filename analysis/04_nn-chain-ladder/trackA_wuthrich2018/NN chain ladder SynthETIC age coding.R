##########################################
#########  NN chain ladder on the SynthETIC portfolio: Age of Claimant as
#########  four dummies or as an ordinal score
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Section 3.3 (MinMaxScaler (3.8)) and the
#########  sensitivities (3.9)
##########################################

## reads the fits of "NN chain ladder SynthETIC fit.R" under both codings of
## Age of Claimant (profiles default and age_numeric; no Keras needed) and
## compares them run by run: same cells, rows of Keras's split, seeds and
## training; the networks differ in the inputs (14 or 11), hence in the
## parameters (321 or 261 for one layer of 20). The codings are judged on
## the reserves by age band; an error is the error on this one simulated
## portfolio, not a bias
source(here::here("analysis", "00_setup.R"))
out_dir <- file.path("04_NN-chain-ladder", "synthetic-age-coding")
tab_dir <- file.path(paths$tables, out_dir)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
units <- cfg$data$scale                        # tables in millions
vali_split <- cfg$nncl$training$validation_split
q_main <- cfg$nncl$model$q_main
run_names <- c(paste0("paper_q", cfg$nncl$model$q),
               "s1_adam", "s2_early_stop", "s3_cl_start", "s4_balance")
## networks compared one by one: j = 2..8, the networks that leave the CL
## start in nearly every run under both codings (table kept below)
j_net <- 2:8
j_fig <- 2:5                                   # networks of the age figure

## the two codings: where their fits are saved
codings <- c("dummy", "numeric")
tags <- sapply(c(dummy = "default", numeric = "age_numeric"), function(p) {
  config::get("nncl", config = p, file = here::here("config.yml"))$synthetic$tag
})

## runs of the grid (hidden layers, optimiser, training, seed), as in the
## fit script; predictor: the block of seeds of a nagging predictor, as in
## the analysis script
grid_cfg <- cfg$nncl$synthetic
grid <- CJ(hidden = sapply(grid_cfg$hidden, paste, collapse = "-"),
           optimizer = names(grid_cfg$optimizers),
           training = unlist(grid_cfg$training),
           seed = cfg$seed + seq_len(grid_cfg$seeds) - 1,
           sorted = FALSE)
grid$combination <- paste(grid$hidden, grid$optimizer, grid$training)
grid$block <- ceiling((grid$seed - cfg$seed + 1) / grid_cfg$nagging)
grid$predictor <- paste(grid$combination, grid$block)
grid$run <- paste0("grid_", grid$hidden, "_", grid$optimizer, "_",
                   grid$training, "_s", grid$seed)

##########################################
#########  the cells, the truth and the benchmarks
##########################################

cells <- readRDS(file.path(paths$interim, "nncl_synthetic_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])
zero <- readRDS(file.path(paths$processed, "nncl_synthetic_zero_claims.rds"))
homogeneous <- readRDS(file.path(paths$processed,
                                 "nncl_synthetic_homogeneous.rds"))
age <- cells[["Age of Claimant"]]
bands <- sort(unique(age))

## learning cells and part-1 diagonal cells, as in the fit script; network j
## develops a part-1 cell if j is beyond its diagonal, j > I - i
learn_rows <- lapply(1:(n_ay - 1), function(j) {
  which(cells$i <= n_ay - j & cum[, j] > 0)
})
diag_rows <- which(cells$i > 1 & cells$c_diag > 0)
ahead <- outer(n_ay - cells$i[diag_rows], 1:(n_ay - 1), "<")
c_prev <- cum[diag_rows, -n_ay]                # C_{i,j-1}(x), the truth
c_next <- cum[diag_rows, -1]                   # C_{i,j}(x), the truth
age_diag <- age[diag_rows]
ay_band <- paste(cells$i[diag_rows], age_diag)

## the true outstanding payments (payment units): of all cells, and of the
## part-1 cells by age band and by accident year and age band; no
## recoveries: part 2 of (5.1) is the zero claims ultimate (Section 4.2),
## without features and the same under both codings
true_total <- sum((cum[, n_ay] - cells$c_diag)[cells$i > 1])
true_cell <- cum[diag_rows, n_ay] - cells$c_diag[diag_rows]
true_band <- rowsum(true_cell, age_diag)[, 1]
true_ay_band <- rowsum(true_cell, ay_band)[, 1]
reserve_zero <- sum(zero$ult_zero)

## Mack's chain ladder on the observed triangle: error and sqrt(msep) in %
## of the true reserves
mack <- nncl_mack(rowsum(cum, cells$i))
error_cl <- 100 * (sum(mack$by_origin$ibnr) / true_total - 1)
se_cl <- 100 * mack$total_se / true_total
round(c("true reserves" = true_total / units,
        "of the part-1 cells" = sum(true_cell) / units,
        "zero claims reserves" = reserve_zero / units,
        "error of Mack's CL (%)" = error_cl,
        "sqrt(msep) of Mack's CL (%)" = se_cl), 2)
round(true_band / units, 1)

## CL factors f_{j-1} by age band on the cells r
band_factors <- function(r, j) {
  (rowsum(cum[r, j + 1], age[r]) / rowsum(cum[r, j], age[r]))[, 1]
}

## loss (6.1) of the CL factors f_diag (part-1 cells x networks j) on the
## true lower triangle, per network j
low_loss <- function(f_diag) {
  colSums(ifelse(ahead, (c_next - f_diag * c_prev)^2 / c_prev, 0))
}

## three benchmarks on the part-1 cells, CL factors with age the only
## feature: none (homogeneous), log-linear in the age score of the numeric
## coding (loss (6.1) on the learning cells), one factor per age band
score <- unlist(grid_cfg$age_midpoints)
score <- (2 * (score - min(score)) / (max(score) - min(score)) - 1)[age]
f_hom <- matrix(homogeneous$f_hom, length(diag_rows), n_ay - 1, byrow = TRUE)
f_score <- sapply(1:(n_ay - 1), function(j) {
  r <- learn_rows[[j]]
  fit <- glm(cum[r, j + 1] / cum[r, j] ~ score[r],
             family = gaussian(link = "log"),
             weights = cum[r, j],
             start = c(log(homogeneous$f_hom[j]), 0))
  exp(coef(fit)[1] + coef(fit)[2] * score[diag_rows])
})
f_band <- sapply(1:(n_ay - 1), function(j) {
  band_factors(learn_rows[[j]], j)[age_diag]
})
low_hom <- low_loss(f_hom)

## measures of CL factors f_diag: error of the reserves (5.1) in % of the
## true reserves; of the part-1 reserves by age band the sum of the absolute
## errors and the root mean squared error by accident year and band
## (millions) and the error in % of the band's true reserves; lower-triangle
## loss of the networks j_net relative to the homogeneous factors
band_cols <- paste0("band_", gsub("[- ]", "_", bands))
low_cols <- paste0("low_", j_net)
loss_cols <- paste0("loss_", j_net)
measures <- function(f_diag) {
  f_prod <- exp(rowSums(ifelse(ahead, log(f_diag), 0)))
  part1 <- cells$c_diag[diag_rows] * (f_prod - 1)
  band <- rowsum(part1, age_diag)[, 1]
  ay_band_error <- rowsum(part1, ay_band)[, 1] - true_ay_band
  data.table(error_pct = 100 * ((sum(part1) + reserve_zero) / true_total - 1),
             band_abs_error = sum(abs(band - true_band)) / units,
             ay_band_rmse = sqrt(mean(ay_band_error^2)) / units,
             t(setNames(100 * (band / true_band - 1), band_cols)),
             t(setNames((low_loss(f_diag) / low_hom)[j_net], low_cols)))
}
## (the homogeneous factors on the cells with the zero claims reserves are
## not Mack's CL on the triangle: their totals differ)
benchmarks <- data.table(coding = "benchmark",
                         run = c("homogeneous CL factors",
                                 "CL factors log-linear in the age score",
                                 "CL factors of the age band"),
                         rbind(measures(f_hom),
                               measures(f_score),
                               measures(f_band)))

##########################################
#########  the fits of the two codings
##########################################

## the runs fitted under both codings; the fits of a coding can be under
## way: the grid is compared on the seeds fitted in full
fit_file <- function(coding, run) {
  file.path(paths$processed, paste0(tags[coding], "_fit_", run, ".rds"))
}
fitted <- function(run) {
  file.exists(fit_file("dummy", run)) & file.exists(fit_file("numeric", run))
}
full <- tapply(fitted(grid$run), grid$seed, all)
grid <- grid[full[as.character(seed)]]
all_runs <- c(run_names[fitted(run_names)], grid$run)
c("runs fitted under both codings" = length(all_runs),
  "seeds of the grid" = uniqueN(grid$seed))

## every run of both codings: its measures, the parameters of network j = 1
## and the loss L'_j (6.1) on the learning cells of the networks j_net
## relative to the homogeneous loss; epochs: the epochs used by the 19
## networks (0: the CL start is kept); f_nag: the CL factors summed over
## the seeds of a nagging predictor that are finite under both codings
res <- list()
epochs <- array(NA,
                c(length(codings), length(all_runs), n_ay - 1),
                dimnames = list(codings, all_runs, NULL))
nag <- unique(grid[, .(hidden, optimizer, training, block, predictor)])
nag$seeds <- 0
f_nag <- lapply(setNames(nm = codings), function(coding) {
  setNames(rep(list(0), nrow(nag)), nag$predictor)
})
for (run in all_runs) {
  f_run <- list()
  for (coding in codings) {
    fits <- readRDS(fit_file(coding, run))$fits
    f_run[[coding]] <- sapply(fits, `[[`, "f_diag")
    loss <- sapply(fits, `[[`, "loss") / homogeneous$loss
    res[[paste(coding, run)]] <- data.table(coding = coding,
                                            run = run,
                                            parameters = fits[[1]]$n_par,
                                            measures(f_run[[coding]]),
                                            t(setNames(loss[j_net], loss_cols)))
    epochs[coding, run, ] <- sapply(fits, `[[`, "epochs_used")
  }
  k <- match(grid$predictor[match(run, grid$run)], nag$predictor)
  if (!is.na(k) && all(is.finite(unlist(f_run)))) {
    for (coding in codings) {
      f_nag[[coding]][[k]] <- f_nag[[coding]][[k]] + f_run[[coding]]
    }
    nag$seeds[k] <- nag$seeds[k] + 1
  }
}
res <- rbindlist(res)
## a run with a diverged network has no reserves: left out of the summaries
measure_cols <- setdiff(names(res), c("coding", "run", "parameters"))
res[!is.finite(error_pct), (measure_cols) := NA]
## absolute errors: of the total and of the age bands (%)
abs_cols <- paste0("abs_", band_cols)
res$error_abs <- abs(res$error_pct)
res[, (abs_cols) := lapply(.SD, abs), .SDcols = band_cols]
wide <- dcast(res,
              run ~ coding,
              value.var = setdiff(names(res), c("coding", "run")))

##########################################
#########  tables
##########################################

## the benchmarks, the runs of the paper and the sensitivity runs S1-S4
## (first seed): error of the total (%), sum of the absolute errors by age
## band and root mean squared error by accident year and band (millions),
## error by age band (%), losses of the networks j_net
main_runs <- rbind(benchmarks,
                   res[run %in% run_names][order(match(run, run_names))],
                   fill = TRUE)
main_runs <- main_runs[, c("run", "coding", "parameters", "error_pct",
                           "band_abs_error", "ay_band_rmse", band_cols,
                           low_cols, loss_cols), with = FALSE]
cbind(main_runs[, 1:3], round(main_runs[, 4:11], 1))

## CL start: share of the networks of development period j that keep the
## start (the CL factor of Keras's training rows), by coding and under both
## codings (there the two codings give the same factor by construction)
cl_runs <- grid$run[grid$training == "cl_start"]
kept <- data.table(j = 1:(n_ay - 1),
                   dummy = colMeans(epochs["dummy", cl_runs, ] == 0),
                   numeric = colMeans(epochs["numeric", cl_runs, ] == 0),
                   both = colMeans(epochs["dummy", cl_runs, ] == 0 &
                                     epochs["numeric", cl_runs, ] == 0))
round(kept, 2)

## paired difference numeric - dummy over the seeds (initial weights; the
## portfolio is fixed): mean, 95% t-interval, seeds with the smaller value
## under the numeric coding and Wilcoxon's signed-rank test
paired <- function(d) {
  n <- length(d)
  half <- qt(0.975, n - 1) * sd(d) / sqrt(n)
  list(seeds = n,
       mean_diff = mean(d),
       lower = mean(d) - half,
       upper = mean(d) + half,
       numeric_smaller = sum(d < 0),
       p_wilcoxon = wilcox.test(d)$p.value)
}

## the grid, by hidden layers, optimiser and training: runs with a diverged
## network and medians over the seeds by coding; under the CL start the
## paired difference of the sum of the absolute errors by age band (p_holm:
## Holm's adjustment over its combinations). The errors of the paper's
## training are heavy-tailed: medians only
pairs <- merge(grid, wide, by = "run", sort = FALSE)
both <- !is.na(pairs$error_pct_dummy) & !is.na(pairs$error_pct_numeric)
cl <- both & pairs$training == "cl_start"
by_combination <- merge(
  pairs[, .(diverged_dummy = sum(is.na(error_pct_dummy)),
            diverged_numeric = sum(is.na(error_pct_numeric)),
            band_abs_error_dummy = median(band_abs_error_dummy, na.rm = TRUE),
            band_abs_error_numeric = median(band_abs_error_numeric,
                                            na.rm = TRUE),
            ay_band_rmse_dummy = median(ay_band_rmse_dummy, na.rm = TRUE),
            ay_band_rmse_numeric = median(ay_band_rmse_numeric, na.rm = TRUE),
            error_abs_dummy = median(error_abs_dummy, na.rm = TRUE),
            error_abs_numeric = median(error_abs_numeric, na.rm = TRUE)),
        by = .(hidden, optimizer, training)],
  pairs[cl,
        paired(band_abs_error_numeric - band_abs_error_dummy),
        by = .(hidden, optimizer, training)],
  by = c("hidden", "optimizer", "training"),
  all.x = TRUE,
  sort = FALSE
)
by_combination$p_holm <- p.adjust(by_combination$p_wilcoxon, "holm")
cbind(by_combination[, 1:5], round(by_combination[, 6:11], 1))[order(training)]
cbind(by_combination[training == "cl_start", c(1:2, 12)],
      round(by_combination[training == "cl_start", 13:15], 1),
      by_combination[training == "cl_start", 16],
      p_holm = signif(by_combination[training == "cl_start"]$p_holm, 2))

## the CL start with the seed as the unit (the same initial weights recur in
## every combination): each measure averaged over the combinations with all
## seeds finite under both codings, then the paired difference over the
## seeds. The first measure is the primary comparison; p_holm: Holm's
## adjustment over the other measures. abs_band: absolute error of the band
## (%); low_j, loss_j: loss of network j on the true lower triangle and on
## the learning cells, relative to the homogeneous CL factor
n_finite <- tapply(both, pairs$combination, sum)
balanced <- names(n_finite)[n_finite == uniqueN(grid$seed)]
use <- cl & pairs$combination %in% balanced
cmp <- c("band_abs_error", "ay_band_rmse", "error_abs", abs_cols, low_cols,
         loss_cols)
by_seed <- rbindlist(lapply(cmp, function(m) {
  d <- data.table(seed = pairs$seed,
                  dummy = pairs[[paste0(m, "_dummy")]],
                  numeric = pairs[[paste0(m, "_numeric")]])
  d <- d[use, .(dummy = mean(dummy), numeric = mean(numeric)), by = seed]
  c(list(measure = m,
         mean_dummy = mean(d$dummy),
         mean_numeric = mean(d$numeric)),
    paired(d$numeric - d$dummy))
}))
by_seed$p_holm <- c(NA, p.adjust(by_seed$p_wilcoxon[-1], "holm"))
c("combinations with the CL start" = sum(grepl("cl_start", balanced)))
ratio <- by_seed$measure %in% c(low_cols, loss_cols)
num_cols <- c("mean_dummy", "mean_numeric", "mean_diff", "lower", "upper")
cbind(by_seed[!ratio, "measure"],
      round(by_seed[!ratio, num_cols, with = FALSE], 2),
      by_seed[!ratio, c("seeds", "numeric_smaller")],
      p_wilcoxon = signif(by_seed$p_wilcoxon[!ratio], 2),
      p_holm = signif(by_seed$p_holm[!ratio], 2))
cbind(by_seed[ratio, "measure"],
      round(by_seed[ratio, num_cols, with = FALSE], 4),
      by_seed[ratio, c("seeds", "numeric_smaller")],
      p_holm = signif(by_seed$p_holm[ratio], 2))

## error of the reserves by age band in % of the band's true reserves:
## median and standard deviation over the seeds per combination and coding,
## and median and quartiles over all runs per training and coding
band_long <- melt(merge(grid, res, by = "run"),
                  id.vars = c("hidden", "optimizer", "training", "seed",
                              "coding"),
                  measure.vars = band_cols,
                  variable.name = "age",
                  value.name = "error_pct")
band_long$age <- bands[match(band_long$age, band_cols)]
band_combination <- band_long[, .(median = median(error_pct, na.rm = TRUE),
                                  sd = sd(error_pct, na.rm = TRUE)),
                              by = .(hidden, optimizer, training, coding, age)]
band_training <- band_long[, .(q25 = quantile(error_pct, 0.25, na.rm = TRUE),
                               median = median(error_pct, na.rm = TRUE),
                               q75 = quantile(error_pct, 0.75, na.rm = TRUE)),
                           by = .(training, coding, age)]
band_wide <- dcast(band_training,
                   training + coding ~ age,
                   value.var = "median")
cbind(band_wide[, 1:2], round(band_wide[, -(1:2)], 1))

## nagging predictors (Richman & Wuthrich 2020) of the blocks of seeds of
## the analysis script: the CL factors averaged over the seeds of a block
## that are finite under both codings; the two blocks of a coding show what
## the seeds alone change
nag <- nag[seeds > 0]
nagging <- rbindlist(lapply(codings, function(coding) {
  rbindlist(lapply(seq_len(nrow(nag)), function(k) {
    data.table(nag[k, .(hidden, optimizer, training, block, seeds)],
               coding = coding,
               measures(f_nag[[coding]][[nag$predictor[k]]] / nag$seeds[k]))
  }))
}))
nag_wide <- dcast(nagging,
                  hidden + optimizer + training + block + seeds ~ coding,
                  value.var = c("error_pct", "band_abs_error"))
cbind(nag_wide[, 1:5], round(nag_wide[, 6:9], 1))[order(training)]

## what the networks learn for Age of Claimant: the CL factor f_{j-1} of
## every age band, the average (3.9) of f_{j-1}(x) over the learning cells
## of the band weighted by C_{i,j-1}(x), for the seeds of the paper's
## network (one hidden layer, rmsprop) and of S3 (adam, CL start): mean and
## range over the seeds. Benchmarks: the band's factor on all 20 accident
## years (the truth included), on the learning cells, on Keras's training
## rows, and the homogeneous factor
age_runs <- pairs[both & hidden == q_main &
                    ((training == "paper" & optimizer == "rmsprop") |
                       (training == "cl_start" & optimizer == "adam"))]
benchmark_names <- c("all accident years", "learning cells", "training rows",
                     "homogeneous")
age_factors <- list()
for (j in j_net) {
  r <- learn_rows[[j]]
  train <- r[seq_len(floor(length(r) * (1 - vali_split)))]
  age_factors[[paste("benchmark", j)]] <- data.table(
    training = "benchmark",
    coding = rep(benchmark_names, each = length(bands)),
    seed = NA,
    j = j,
    age = bands,
    factor = c(band_factors(which(cum[, j] > 0), j),
               band_factors(r, j),
               band_factors(train, j),
               rep(homogeneous$f_hom[j], length(bands)))
  )
}
for (coding in codings) {
  for (k in seq_len(nrow(age_runs))) {
    fits <- readRDS(fit_file(coding, age_runs$run[k]))$fits
    for (j in j_net) {
      r <- learn_rows[[j]]
      f <- rowsum(fits[[j]]$f_learn * cum[r, j], age[r]) /
        rowsum(cum[r, j], age[r])
      age_factors[[paste(coding, k, j)]] <- data.table(
        training = age_runs$training[k],
        coding = coding,
        seed = age_runs$seed[k],
        j = j,
        age = bands,
        factor = f[, 1]
      )
    }
  }
}
age_factors <- rbindlist(age_factors)[, .(seeds = sum(!is.na(seed)),
                                          lower = min(factor),
                                          upper = max(factor),
                                          factor = mean(factor)),
                                      by = .(training, coding, j, age)]
factor_wide <- dcast(age_factors[j %in% j_fig],
                     j + training + coding ~ age,
                     value.var = "factor")
cbind(factor_wide[, 1:3], round(factor_wide[, -(1:3)], 3))

fwrite(main_runs,
       file.path(tab_dir, "nncl_synthetic_age_coding_main_runs.csv"))
fwrite(pairs, file.path(tab_dir, "nncl_synthetic_age_coding_runs.csv"))
fwrite(kept, file.path(tab_dir, "nncl_synthetic_age_coding_kept_start.csv"))
fwrite(by_combination,
       file.path(tab_dir, "nncl_synthetic_age_coding_combinations.csv"))
fwrite(by_seed, file.path(tab_dir, "nncl_synthetic_age_coding_seeds.csv"))
fwrite(band_combination,
       file.path(tab_dir, "nncl_synthetic_age_coding_band_combinations.csv"))
fwrite(band_training,
       file.path(tab_dir, "nncl_synthetic_age_coding_band_training.csv"))
fwrite(nagging, file.path(tab_dir, "nncl_synthetic_age_coding_nagging.csv"))
fwrite(age_factors,
       file.path(tab_dir, "nncl_synthetic_age_coding_factors.csv"))

##########################################
#########  figures
##########################################

fig_dir <- file.path(paths$figures, out_dir)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
coding_labels <- c(dummy = "dummy coding", numeric = "numeric coding")
benchmark_labels <- setNames(c("homogeneous", "log-linear in the age score",
                               "one per age band"),
                             benchmarks$run)

## Fig. 1: error of the reserves by age band of the runs with the CL start
## (boxes: the optimisers and seeds), by hidden layers and coding, and the
## three benchmarks
band_fig <- band_long[training == "cl_start" & !is.na(error_pct)]
band_fig$hidden <- factor(paste("hidden layers", band_fig$hidden),
                          levels = paste("hidden layers", unique(grid$hidden)))
band_fig$coding <- coding_labels[band_fig$coding]
bench_fig <- melt(benchmarks,
                  id.vars = "run",
                  measure.vars = band_cols,
                  variable.name = "age",
                  value.name = "error_pct")
bench_fig$age <- bands[match(bench_fig$age, band_cols)]
bench_fig$run <- factor(benchmark_labels[bench_fig$run],
                        levels = benchmark_labels)
save_figure("NNCL SynthETIC age coding band errors.png",
            ggplot(band_fig, aes(x = age, y = error_pct)) +
              geom_hline(yintercept = 0, colour = "grey60") +
              geom_boxplot(aes(fill = coding),
                           linewidth = 0.3,
                           outlier.size = 0.4) +
              geom_point(data = bench_fig, aes(shape = run), size = 1.6) +
              facet_wrap(~hidden, ncol = 1) +
              scale_fill_manual(values = c("white", "grey70")) +
              scale_shape_manual(values = c(4, 8, 3)) +
              labs(x = "Age of Claimant",
                   y = "error in % of the true reserves of the age band",
                   fill = NULL,
                   shape = "benchmark CL factors:") +
              description_theme() +
              theme(legend.title = element_text(),
                    legend.box = "vertical",
                    legend.margin = margin(0, 0, 0, 0)),
            fig_dir,
            height = 19)

## Fig. 2: the runs with the CL start under the two codings (same seed), on
## the diagonal the codings agree; left: sum of the absolute errors by age
## band, lines: the three benchmarks; right: error of the total reserves,
## grey square: Mack's sqrt(msep) around the truth
panels <- c("sum of the absolute errors by age band (millions)",
            "error of the total reserves (%)")
pair_fig <- rbind(data.table(panel = panels[1],
                             dummy = pairs$band_abs_error_dummy[cl],
                             numeric = pairs$band_abs_error_numeric[cl]),
                  data.table(panel = panels[2],
                             dummy = pairs$error_pct_dummy[cl],
                             numeric = pairs$error_pct_numeric[cl]))
pair_fig$panel <- factor(pair_fig$panel, levels = panels)
ref_fig <- data.table(panel = factor(panels[1], levels = panels),
                      benchmark = factor(benchmark_labels,
                                         levels = benchmark_labels),
                      value = benchmarks$band_abs_error)
se_fig <- data.table(panel = factor(panels[2], levels = panels))
save_figure("NNCL SynthETIC age coding runs.png",
            ggplot(pair_fig, aes(x = dummy, y = numeric)) +
              geom_rect(data = se_fig,
                        aes(xmin = -se_cl,
                            xmax = se_cl,
                            ymin = -se_cl,
                            ymax = se_cl),
                        fill = "grey85",
                        inherit.aes = FALSE) +
              geom_abline(colour = "grey50") +
              geom_hline(data = ref_fig,
                         aes(yintercept = value, linetype = benchmark)) +
              geom_vline(data = ref_fig,
                         aes(xintercept = value, linetype = benchmark)) +
              geom_point(shape = 16, size = 0.6, alpha = 0.4) +
              geom_blank(aes(x = numeric, y = dummy)) +
              facet_wrap(~panel, scales = "free") +
              scale_linetype_manual(values = c("dotted", "dashed", "dotdash")) +
              labs(x = "dummy coding",
                   y = "numeric coding",
                   linetype = "benchmark CL factors:") +
              description_theme() +
              theme(legend.title = element_text(), aspect.ratio = 1),
            fig_dir,
            height = 10)

## Fig. 3: CL factors by age band relative to the homogeneous CL factor, per
## network j and for the paper's network and S3: the band's factor on all
## accident years, and the networks of the two codings (mean and range over
## the seeds)
series <- c(benchmark_names[1], coding_labels)
training_labels <- c(paper = "paper's network (rmsprop, 100 epochs)",
                     cl_start = "S3 (adam, CL start)")
factor_fig <- rbind(
  age_factors[j %in% j_fig & training != "benchmark"],
  rbindlist(lapply(unique(age_runs$training), function(tr) {
    data.table(training = tr,
               age_factors[j %in% j_fig & coding == series[1], -1])
  }))
)
factor_fig$series <- factor(ifelse(factor_fig$coding == series[1],
                                   series[1],
                                   coding_labels[factor_fig$coding]),
                            levels = series)
factor_fig$training <- factor(training_labels[factor_fig$training],
                              levels = training_labels)
for (v in c("factor", "lower", "upper")) {
  factor_fig[[v]] <- factor_fig[[v]] / homogeneous$f_hom[factor_fig$j]
}
factor_fig$j <- paste("j =", factor_fig$j)
save_figure("NNCL SynthETIC age coding factors.png",
            ggplot(factor_fig,
                   aes(x = age, y = factor, shape = series, group = series)) +
              geom_hline(yintercept = 1, linetype = "dotted") +
              geom_linerange(aes(ymin = lower, ymax = upper),
                             linewidth = 0.3,
                             position = position_dodge(width = 0.5)) +
              geom_point(size = 1.4, position = position_dodge(width = 0.5)) +
              facet_grid(j ~ training) +
              scale_shape_manual(values = c(4, 1, 16)) +
              labs(x = "Age of Claimant",
                   y = "CL factor relative to the homogeneous CL factor") +
              description_theme(),
            fig_dir,
            height = 16)
