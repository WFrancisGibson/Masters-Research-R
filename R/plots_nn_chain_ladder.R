##########################################
#########  Figures of the NN chain ladder
#########  Wuthrich (2018), EAJ 8:407-436, Figures 2-5 and 8-9;
#########  Gabrielli & Wuthrich (2018), Risks 6(2):29, Figures A1-A4
##########################################

## every k-th label on a crowded discrete axis (at most 8 labels)
nncl_breaks <- function(x) x[seq(1, length(x), by = ceiling(length(x) / 8))]

## bars by label, one panel per feature or quantity (EAJ Fig. 5, Risks
## Figs. A1-A4); d: columns panel, label, value; mean_line: columns panel,
## value, the portfolio averages in red (Risks Figs. A2-A4)
nncl_feature_bar_plot <- function(d, ylab, title, mean_line = NULL) {
  d$panel <- factor(d$panel, levels = unique(d$panel))
  d$label <- factor(d$label, levels = sort(unique(d$label)))
  p <- ggplot(d, aes(x = label, y = value)) +
    geom_col(fill = "grey40", width = 0.8) +
    facet_wrap(~panel, scales = "free") +
    scale_x_discrete(breaks = nncl_breaks) +
    labs(x = NULL, y = ylab, title = title) +
    theme_bw()
  if (!is.null(mean_line)) {
    mean_line$panel <- factor(mean_line$panel, levels = levels(d$panel))
    p <- p + geom_hline(data = mean_line,
                        aes(yintercept = value),
                        colour = "red")
  }
  p
}

## sensitivities of the CL factors (EAJ Figs. 8-9): marginal averages (3.9)
## of f_{j-1}(x) per label of each feature (blue) and the portfolio average
## f^NN_{j-1} (grey dotted); one row per development period j, one y-scale
## per row; d: columns j, feature, label, f; avg: columns j, f
nncl_sensitivity_plot <- function(d, avg, title) {
  d$feature <- factor(d$feature, levels = unique(d$feature))
  d$label <- factor(d$label, levels = sort(unique(d$label)))
  ggplot(d, aes(x = label, y = f)) +
    geom_hline(data = avg,
               aes(yintercept = f),
               colour = "grey50",
               linetype = "dotted") +
    geom_point(colour = "blue", size = 0.8) +
    facet_grid(j ~ feature, scales = "free", labeller = label_both) +
    scale_x_discrete(breaks = nncl_breaks) +
    labs(x = NULL, y = "CL factor", title = title) +
    theme_bw() +
    theme(axis.text.x = element_text(size = 6))
}

## NN reserves and true outstanding payments by label (EAJ Figs. 2-3), or
## their ratio (relative = TRUE, EAJ Fig. 4); d: columns panel, label, nn, true
nncl_reserves_by_label_plot <- function(d, title, relative = FALSE) {
  d$panel <- factor(d$panel, levels = unique(d$panel))
  d$label <- factor(d$label, levels = sort(unique(d$label)))
  if (relative) {
    p <- ggplot(d, aes(x = label, y = nn / true)) +
      geom_hline(yintercept = 1, colour = "grey50") +
      geom_point(colour = "blue") +
      coord_cartesian(ylim = c(0, 2)) +
      labs(y = "reserves / true outstanding")
  } else {
    series <- c("NN reserves", "true reserves")
    long <- data.frame(panel = d$panel,
                       label = d$label,
                       value = c(d$nn, d$true),
                       series = factor(rep(series, each = nrow(d)),
                                       levels = series))
    p <- ggplot(long, aes(x = label, y = value, colour = series)) +
      geom_point() +
      scale_colour_manual(values = c("blue", "red"), name = NULL) +
      labs(y = "reserves")
  }
  p +
    facet_wrap(~panel, scales = "free_x", ncol = 1) +
    scale_x_discrete(breaks = nncl_breaks) +
    labs(x = NULL, title = title) +
    theme_bw() +
    theme(legend.position = "top")
}
