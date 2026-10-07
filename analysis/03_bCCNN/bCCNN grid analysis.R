##########################################
#########  bCCNN grid of hyper-parameters and architectures under four
#########  stopping rules: test errors, reserves, spread over the seeds and
#########  nagging predictors
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3;
#########  test error: rolling origin (Al-Mudafer, Avanzi, Taylor & Wong
#########  2021, eq. (4.4)); nagging predictors: Richman & Wuthrich (2020);
#########  stopping rules: Paper C Section 3.3.2, Harkonen (2021) Section
#########  3.2, Al-Mudafer et al. Section 4
##########################################

## reads the fits of all runs of "bCCNN grid fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

scale <- cfg$data$scale            # tables in units of scale
train_cfg <- cfg$bccnn$training
ro_cfg <- cfg$data$rolling_origin

## every combination of hidden layers, activation, dropout, optimiser and
## batch size with every seed: the runs of the fit script, one row each;
## every run is finished under each stopping rule of config.yml
## bccnn$stopping
grid_cfg <- cfg$bccnn$grid
rules <- unlist(cfg$bccnn$stopping$rules)
seeds <- cfg$seed + seq_len(grid_cfg$seeds) - 1
settings <- c("hidden", "activation", "dropout", "optimizer", "batch_size")
runs <- bccnn_grid_runs(grid_cfg, cfg$seed)
run_tab <- rbindlist(lapply(runs, function(p) {
  data.table(hidden = paste(p$hidden, collapse = "-"),
             activation = p$activation,
             dropout = p$dropout,
             optimizer = p$optimizer,
             batch_size = if (is.null(p$batch_size)) "full" else
               as.character(p$batch_size),
             seed = p$seed,
             learning_rate = p$learning_rate)
}))
run_tab$combo <- paste0(run_tab$hidden, "_", run_tab$activation,
                        "_d", run_tab$dropout, "_", run_tab$optimizer,
                        "_b", run_tab$batch_size)
run_tab$run <- names(runs)
## trainable parameters: the hidden layers on the 2 embeddings and w, B and
## c of the Response layer (13)
run_tab$parameters <- sapply(strsplit(run_tab$hidden, "-"), function(q) {
  q <- c(2, as.numeric(q))
  sum((q[-length(q)] + 1) * q[-1]) + q[length(q)] + 2
})
## the network of Paper C (config.yml bccnn$model and training) in the grid
paper_c <- paste0(paste(cfg$bccnn$model$hidden, collapse = "-"),
                  "_", cfg$bccnn$model$activation,
                  "_d", cfg$bccnn$model$dropout,
                  "_", train_cfg$optimizer,
                  "_b", if (is.null(train_cfg$batch_size)) "full" else
                    train_cfg$batch_size)

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
fits <- lapply(setNames(nm = run_tab$run), function(r) {
  readRDS(file.path(paths$processed, paste0("bccnn_grid_fit_", r, ".rds")))
})
## the file names carry neither final_fit nor the steps of the rule "fixed":
## all runs are of the same ones
stopifnot("runs of another final_fit" =
            length(unique(sapply(fits, `[[`, "final_fit"))) == 1,
          "runs with another fixed number of steps" =
            length(unique(sapply(fits, `[[`, "fixed"))) == 1)
fixed <- fits[[1]]$fixed
c("final fit" = fits[[1]]$final_fit, "fixed steps" = fixed)

##########################################
#########  single networks, chain ladder and nagging predictors
##########################################

## single networks, one row per run and stopping rule: steps of the final
## network, reserve, losses on the observed triangle and on the true lower
## triangle and rolling-origin test error per test cell (4.4); a diverged
## network has no scores. Seconds of the whole run (all rules): run_time by
## the clock (the first run of an R session also starts Python), time_fit of
## its Keras fits
grid <- rbindlist(lapply(seq_along(fits), function(i) {
  fit <- fits[[i]]
  rbindlist(lapply(rules, function(r) {
    data.table(run_tab[i],
               rule = r,
               steps = fit$steps[[r]],
               bccnn_scores(fit$mu[[r]],
                            fit$mu_test[[r]],
                            dat_upper,
                            truth,
                            parts),
               run_time = fit$run_time,
               time_fit = fit$time_fit)
  }))
}))
grid$rule <- factor(grid$rule, levels = rules)
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
## the networks of a block of seeds under one stopping rule averaged, on the
## observed triangle and at each test partition; one predictor per
## combination, rule and block of seeds of each size of config.yml
## bccnn$grid$nagging
mean_mu <- function(m) Reduce(`+`, m) / length(m)
combos <- unique(run_tab[, c("combo", settings), with = FALSE])
nag <- NULL
for (size in grid_cfg$nagging) {
  blocks <- split(seeds, ceiling(seq_along(seeds) / size))
  for (k in seq_len(nrow(combos))) {
    for (b in seq_along(blocks)) {
      members <- fits[run_tab$run[run_tab$combo == combos$combo[k] &
                                    run_tab$seed %in% blocks[[b]]]]
      for (r in rules) {
        mu <- mean_mu(lapply(members, function(fit) fit$mu[[r]]))
        mu_test <- lapply(seq_along(members[[1]]$mu_test[[r]]), function(j) {
          mean_mu(lapply(members, function(fit) fit$mu_test[[r]][[j]]))
        })
        nag <- rbind(nag,
                     data.table(combos[k],
                                rule = r,
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
}
nag$rule <- factor(nag$rule, levels = rules)
nag$true <- true_total
nag$bias_pct <- 100 * (nag$reserve / true_total - 1)
nag$predictor <- paste0("nag", nag$networks, "_b", nag$block)

##########################################
#########  tables
##########################################

## spread over the seeds per combination and stopping rule: steps, test
## error, out-of-sample loss and bias of the single networks (a diverged run
## left out), closer_than_cl the share of the seeds with a smaller absolute
## bias than the chain ladder, time_fit_mean the seconds of the Keras fits
## of a run (all rules); next to them the test error and bias of the nagging
## predictors (one column per predictor); ordered by the mean test error,
## which uses no future data
seed_spread <- grid[, .(parameters = parameters[1],
                        seeds = .N,
                        diverged = sum(!is.finite(reserve)),
                        steps_mean = mean(steps),
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
                    by = c(settings, "rule")]
nag_wide <- dcast(nag,
                  hidden + activation + dropout + optimizer + batch_size +
                    rule ~ predictor,
                  value.var = c("test_loss_per_cell", "bias_pct"))
seed_spread <- merge(seed_spread,
                     nag_wide,
                     by = c(settings, "rule"),
                     sort = FALSE)
seed_spread <- seed_spread[order(test_loss_mean)]
round_cols <- setdiff(names(seed_spread),
                      c(settings, "rule", "parameters", "seeds", "diverged"))
seed_spread[, (round_cols) := lapply(.SD, round, 4), .SDcols = round_cols]
seed_spread[, c(settings, "rule", "steps_mean", "test_loss_mean",
                "test_loss_sd", "bias_pct_mean", "bias_pct_sd",
                "closer_than_cl"), with = FALSE]

## main effects: the single networks averaged over all other settings and
## the seeds, per stopping rule and level of each setting; setting "rule":
## each rule over all combinations
main_effects <- rbindlist(lapply(c("rule", settings), function(v) {
  grid[, .(setting = v,
           runs = .N,
           diverged = sum(!is.finite(reserve)),
           steps = mean(steps),
           test_loss_per_cell = mean(test_loss_per_cell, na.rm = TRUE),
           loss_out = mean(loss_out, na.rm = TRUE),
           bias_pct = mean(bias_pct, na.rm = TRUE),
           abs_bias_pct = mean(abs(bias_pct), na.rm = TRUE)),
       by = .(rule, level = as.character(get(v)))]
}))
setcolorder(main_effects, c("setting", "level", "rule"))
cbind(main_effects[, 1:5], round(main_effects[, -(1:5)], 4))

## the stopping rules side by side, over all combinations and for the
## network of Paper C: steps chosen, reserve and its bias against the true
## reserve, rolling-origin test error (4.4) and loss on the true lower
## triangle of the single networks (a diverged run left out); fixed: the
## steps of the rule "fixed"
by_rule <- rbindlist(list("all combinations" = grid,
                          "Paper C network" = grid[combo == paper_c]),
                     idcol = "scope")
by_rule$scope <- factor(by_rule$scope, levels = unique(by_rule$scope))
rule_tab <- by_rule[, .(fixed = fixed,
                        runs = .N,
                        diverged = sum(!is.finite(reserve)),
                        steps_mean = mean(steps),
                        steps_sd = sd(steps),
                        steps_min = min(steps),
                        steps_median = median(steps),
                        steps_max = max(steps),
                        true = true[1],
                        reserve_mean = mean(reserve, na.rm = TRUE),
                        bias_pct_mean = mean(bias_pct, na.rm = TRUE),
                        bias_pct_sd = sd(bias_pct, na.rm = TRUE),
                        abs_bias_pct_mean = mean(abs(bias_pct), na.rm = TRUE),
                        closer_than_cl = mean(abs(reserve - true) <
                                                abs(cl$reserve - true),
                                              na.rm = TRUE),
                        test_loss_mean = mean(test_loss_per_cell, na.rm = TRUE),
                        test_loss_sd = sd(test_loss_per_cell, na.rm = TRUE),
                        loss_out_mean = mean(loss_out, na.rm = TRUE),
                        loss_out_sd = sd(loss_out, na.rm = TRUE)),
                    keyby = .(scope, rule)]
cbind(rule_tab[, 1:5], round(rule_tab[, -(1:5)], 4))

fwrite(grid, file.path(tab_dir, "bccnn_grid_runs.csv"))
fwrite(seed_spread, file.path(tab_dir, "bccnn_grid_seed_spread.csv"))
fwrite(nag, file.path(tab_dir, "bccnn_grid_nagging.csv"))
fwrite(main_effects, file.path(tab_dir, "bccnn_grid_main_effects.csv"))
fwrite(rule_tab, file.path(tab_dir, "bccnn_grid_rules.csv"))

##########################################
#########  figures
##########################################

## the stopping rules side by side: steps, bias of the reserves, rolling-
## origin test error and loss on the true lower triangle of the single
## networks, over all combinations and for the network of Paper C (dotted:
## chain ladder); a diverged run is left out
rule_measures <- c(steps = "gradient descent steps",
                   bias_pct = "bias (% of the true reserves)",
                   test_loss_per_cell = "rolling-origin test loss per cell",
                   loss_out = "loss on the true lower triangle")
d <- melt(by_rule,
          id.vars = c("scope", "rule"),
          measure.vars = names(rule_measures),
          variable.name = "measure")
levels(d$measure) <- rule_measures
cl_line <- data.frame(measure = factor(rule_measures[-1],
                                       levels = rule_measures),
                      value = unlist(cl[names(rule_measures)[-1]]))
ggsave("bCCNN grid stopping rules.png",
       ggplot(d, aes(x = rule, y = value)) +
         geom_hline(data = cl_line,
                    aes(yintercept = value),
                    colour = "grey50",
                    linetype = "dotted") +
         geom_boxplot(outlier.size = 0.6) +
         facet_grid(measure ~ scope, scales = "free_y") +
         labs(x = "stopping rule",
              y = NULL,
              title = "bCCNN under the four stopping rules",
              subtitle = paste0("boxes: the runs of the grid; dotted: chain ",
                                "ladder; fixed: ", fixed, " steps")) +
         theme_bw(),
       path = fig_dir, width = 9, height = 11, dpi = 150)

## rolling-origin test error and bias of the reserves by hidden layers and
## activation, a figure per stopping rule with a panel per dropout rate
## (columns) and optimiser and batch size (rows): one point per seed and one
## filled symbol per nagging predictor (dotted: chain ladder); a diverged
## run has no point
hidden_lab <- unique(grid$hidden)
grid$hidden <- factor(grid$hidden, levels = hidden_lab)
nag$hidden <- factor(nag$hidden, levels = hidden_lab)
measures <- c(test_loss_per_cell = "rolling-origin test loss per cell (4.4)",
              bias_pct = "bias (% of the true reserves)")
for (r in rules) {
  for (m in names(measures)) {
    ggsave(paste0("bCCNN grid ", m, " ", r, ".png"),
           ggplot(grid[rule == r],
                  aes(x = hidden, y = .data[[m]], colour = activation)) +
             geom_hline(yintercept = cl[[m]],
                        colour = "grey50",
                        linetype = "dotted") +
             geom_point(position = position_jitterdodge(jitter.width = 0.15,
                                                        dodge.width = 0.7),
                        size = 0.9,
                        alpha = 0.7) +
             geom_point(data = nag[rule == r],
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
                  title = paste("bCCNN by hidden layers, activation,",
                                "dropout, optimiser and batch size;",
                                "stopping rule:", r),
                  subtitle = "points: single seeds; dotted: chain ladder") +
             theme_bw() + theme(legend.position = "top"),
           path = fig_dir, width = 11, height = 12, dpi = 150)
  }
}
