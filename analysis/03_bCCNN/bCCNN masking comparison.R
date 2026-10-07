##########################################
#########  bCCNN: the rolling-origin analysis with and without the masking
#########  of periods without payments
##########################################

## The bCCNN fit and the hyperparameter search are run twice, in the masked
## form (config.yml default: bccnn$rolling_origin$mask = true) and in the
## unmasked form (profile no_mask, outputs in output/no_mask and
## data/processed/no_mask), then compared here. From the project folder:
##
##   Rscript "analysis/03_bCCNN/bCCNN fit.R"
##   R_CONFIG_ACTIVE=no_mask Rscript "analysis/03_bCCNN/bCCNN fit.R"
##   Rscript "analysis/03_bCCNN/bCCNN hyperparameter search.R"
##   R_CONFIG_ACTIVE=no_mask Rscript "analysis/03_bCCNN/bCCNN hyperparameter search.R"
##   Rscript "analysis/03_bCCNN/bCCNN masking comparison.R"
##
## (Windows cmd: set R_CONFIG_ACTIVE=no_mask before the Rscript line, and
## set R_CONFIG_ACTIVE= afterwards.) This script needs no Keras. Part 1 needs
## only the triangle of "bCCNN fit.R" (data/interim/tri_annual_upper.csv)
## and shows which cells the masking leaves out: if none, the two forms are
## the same analysis and their results differ only by Keras's run-to-run
## noise. Parts 2-4 use whichever outputs exist and skip the others.
## Tables to output/tables/03_bCCNN/bccnn_masking_*.csv, the figure to
## output/figures/03_bCCNN.
source(here::here("analysis", "00_setup.R"))
stopifnot(isTRUE(cfg$bccnn$rolling_origin$mask))   # run in the masked form
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

## the table directories of the two forms
no_mask_paths <- config::get(file = here::here("config.yml"),
                             config = "no_mask")$paths
form_dir <- c(masked = tab_dir,
              not_masked = file.path(here::here(no_mask_paths$tables),
                                     "03_bCCNN"))
read_form <- function(file) {
  lapply(form_dir, function(d) {
    f <- file.path(d, file)
    if (file.exists(f)) fread(f) else NULL
  })
}
have_both <- function(x, what) {
  ok <- !vapply(x, is.null, TRUE)
  if (!all(ok)) {
    message(what, ": missing for ", paste(names(x)[!ok], collapse = ", "),
            ", skipped")
  }
  all(ok)
}

##########################################
#########  1. the cells left out by the masking (no Keras)
##########################################

scale <- cfg$data$scale
dat_upper <- as.matrix(fread(file.path(paths$interim,
                                       "tri_annual_upper.csv"))[, -1]) / scale
parts <- rolling_origin(dat_upper,
                        cfg$bccnn$rolling_origin$test_periods,
                        cfg$bccnn$rolling_origin$vali_periods,
                        cfg$bccnn$rolling_origin$exclude)
masked_cells <- rolling_origin_masked(parts)
masked_cells
fwrite(masked_cells, file.path(tab_dir, "bccnn_masking_cells.csv"))
if (sum(masked_cells$n_vali_masked + masked_cells$n_test_masked) == 0) {
  message("no period without payments in any partition: the masked and ",
          "unmasked forms score the same cells")
}

##########################################
#########  2. the bCCNN fit: results and rolling-origin summary
##########################################

## side by side: quantity, masked, not masked, difference
side_by_side <- function(x, key, value) {
  m <- merge(x$masked[, c(key, value), with = FALSE],
             x$not_masked[, c(key, value), with = FALSE],
             by = key, sort = FALSE, suffixes = c("_masked", "_not_masked"))
  for (v in value) {
    if (is.numeric(m[[paste0(v, "_masked")]])) {
      m[[paste0(v, "_difference")]] <- m[[paste0(v, "_masked")]] -
        m[[paste0(v, "_not_masked")]]
    }
  }
  m
}

results <- read_form("bccnn_annual_results.csv")
if (have_both(results, "fit results")) {
  results <- side_by_side(results, "quantity", "value")
  print(results)
  fwrite(results, file.path(tab_dir, "bccnn_masking_results.csv"))
}

ro <- read_form("bccnn_annual_rolling_origin.csv")
if (have_both(ro, "rolling-origin summary")) {
  cols <- intersect(c("n_vali", "n_test", "best_epoch",
                      "test_loss_per_cell_ccODP", "test_loss_per_cell_bCCNN",
                      "test_bCCNN", "test_actual"),
                    intersect(names(ro$masked), names(ro$not_masked)))
  ro <- side_by_side(ro, "partition", cols)
  print(ro)
  fwrite(ro, file.path(tab_dir, "bccnn_masking_rolling_origin.csv"))
}

##########################################
#########  3. the hyperparameter search
##########################################

best <- read_form("bccnn_tuning_best.csv")
if (have_both(best, "chosen hyperparameters")) {
  best <- side_by_side(best, "hyperparameter", "value")
  best$same <- best$value_masked == best$value_not_masked
  print(best)
  fwrite(best, file.path(tab_dir, "bccnn_masking_tuning_best.csv"))
}

scores <- read_form("bccnn_tuning_table.csv")
if (have_both(scores, "search scores")) {
  scores <- side_by_side(scores, "label", c("score", "score_baseline"))
  scores <- scores[order(scores$score_masked), ]
  print(scores)
  fwrite(scores, file.path(tab_dir, "bccnn_masking_tuning_scores.csv"))
}

final <- read_form("bccnn_tuning_final.csv")
if (have_both(final, "tuned fits")) {
  final <- side_by_side(final, "model",
                        c("steps", "test_error", "reserves",
                          "out_of_sample_loss"))
  print(final)
  fwrite(final, file.path(tab_dir, "bccnn_masking_tuning_final.csv"))
}

##########################################
#########  4. figure: early stopping on the final partition
##########################################

## validation deviance of the final partition's run, as the change from the
## start (the forms score different cells, so their levels differ), and the
## step chosen by each
hist <- read_form("bccnn_annual_history_validation.csv")
if (have_both(hist, "validation histories")) {
  d <- rbindlist(lapply(names(hist), function(f) {
    h <- hist[[f]]
    data.table(form = f, epoch = h$epoch, change = h$vali - h$vali[1])
  }))
  d$form <- factor(d$form, levels = c("masked", "not_masked"),
                   labels = c("masked", "not masked"))
  best_d <- d[, .SD[which.min(change)], by = form]
  print(best_d)
  p <- ggplot(d, aes(epoch, change, colour = form, linetype = form)) +
    geom_hline(yintercept = 0, colour = "grey85", linewidth = 0.4) +
    geom_line(linewidth = 0.8) +
    geom_point(data = best_d, size = 2.5, show.legend = FALSE) +
    geom_text(data = best_d, aes(label = paste("t* =", epoch)),
              vjust = 1.8, size = 3, show.legend = FALSE,
              family = "Cambria") +
    scale_colour_manual(values = c("masked" = "#2a78d6",
                                   "not masked" = "#eb6834"),
                        name = NULL) +
    scale_linetype_manual(values = c("masked" = "solid",
                                     "not masked" = "22"),
                          name = NULL) +
    labs(x = "Gradient-descent step",
         y = "Change in validation deviance from the start") +
    theme_bw(base_size = 10, base_family = "Cambria") +
    theme(panel.grid.minor = element_blank(),
          legend.position = "bottom")
  ggsave("bCCNN masking validation losses.png", p, path = fig_dir,
         device = ragg::agg_png, width = 16.5, height = 9, units = "cm",
         dpi = 300)
}
