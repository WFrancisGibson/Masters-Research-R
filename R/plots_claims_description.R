##########################################
#########  Figures of the claims description
#########  no title and grey fills, as the Department's Research Assignment
#########  Guide (2026, 5.7) asks: the number and heading go below the figure
##########################################

## theme of the description figures: as partition_plot() in plots.R
description_theme <- function() {
  theme_bw(base_size = 10, base_family = "Cambria") +
    theme(panel.grid.minor = element_blank(),
          legend.position = "top",
          legend.title = element_blank())
}

## save a ggplot figure to dir, 12 or 16 cm wide (the guide asks for one or
## two figure sizes)
save_figure <- function(file, plot, dir, height, width = 16) {
  ggsave(file,
         plot,
         path = dir,
         device = ragg::agg_png,
         width = width,
         height = height,
         units = "cm",
         dpi = 300)
}

## bars by label, one panel per quantity (Risks Figs. A2-A3); d: columns
## panel, label, value; ref: columns panel, value, a reference value per
## panel (dashed); at most 8 labels on an axis (nncl_breaks)
panel_bar_plot <- function(d, xlab, ref = NULL) {
  d$panel <- factor(d$panel, levels = unique(d$panel))
  d$label <- factor(d$label, levels = unique(d$label))
  p <- ggplot(d, aes(x = label, y = value)) +
    geom_col(fill = "grey40", width = 0.8) +
    facet_wrap(~panel, scales = "free") +
    scale_x_discrete(breaks = nncl_breaks) +
    scale_y_continuous(labels = scales::label_comma()) +
    labs(x = xlab, y = NULL) +
    description_theme()
  if (!is.null(ref)) {
    ref$panel <- factor(ref$panel, levels = levels(d$panel))
    p <- p + geom_hline(data = ref,
                        aes(yintercept = value),
                        linetype = "dashed")
  }
  p
}

## lines over x, a panel per quantity; d: columns panel, series, x, value;
## the series are told apart by their line type, or by a label at the end of
## the line (end_labels = TRUE: series that differ between the panels)
series_plot <- function(d, xlab, ylab = NULL, end_labels = FALSE) {
  d$panel <- factor(d$panel, levels = unique(d$panel))
  d$series <- factor(d$series, levels = unique(d$series))
  p <- ggplot(d, aes(x = x, y = value)) +
    facet_wrap(~panel, scales = "free_y", ncol = 1) +
    scale_y_continuous(labels = scales::label_comma()) +
    expand_limits(y = 0) +
    labs(x = xlab, y = ylab) +
    description_theme()
  if (end_labels) {
    p +
      geom_line(aes(group = series)) +
      geom_text(data = d[d$x == max(d$x), ],
                aes(label = series),
                hjust = 0,
                nudge_x = 0.3,
                size = 2.8,
                family = "Cambria") +
      scale_x_continuous(expand = expansion(mult = c(0.03, 0.22)))
  } else {
    p + geom_line(aes(linetype = series))
  }
}

## values by covariate level: a row per level, the levels grouped by feature
## in panels of a height proportional to their number; d: columns feature,
## level, value and optionally series (a shape per series; the later series
## are drawn smaller so that equal values stay visible), lower and upper
## (intervals) and panel (columns of panels, one x-scale); ref: a vertical
## reference line
level_plot <- function(d,
                       xlab,
                       ref = NULL,
                       transform = "identity",
                       breaks = waiver(),
                       bars = FALSE) {
  d$feature <- factor(d$feature, levels = unique(d$feature))
  d$level <- factor(d$level, levels = rev(unique(as.character(d$level))))
  has_series <- "series" %in% names(d)
  if (has_series) d$series <- factor(d$series, levels = unique(d$series))
  p <- ggplot(d, aes(x = value, y = level))
  if (!is.null(ref)) p <- p + geom_vline(xintercept = ref, colour = "grey60")
  if (bars) p <- p + geom_col(fill = "grey40", width = 0.7)
  if ("lower" %in% names(d)) {
    p <- p + geom_linerange(aes(xmin = lower, xmax = upper), na.rm = TRUE)
  }
  if (has_series) {
    k <- seq_len(nlevels(d$series))
    p <- p +
      geom_point(aes(shape = series, size = series)) +
      scale_shape_manual(values = c(4, 1, 16)[k]) +
      scale_size_manual(values = c(1.8, 2.6, 1.1)[k])
  } else if (!bars) {
    p <- p + geom_point(size = 1.8)
  }
  if ("panel" %in% names(d)) {
    p <- p + facet_grid(feature ~ panel, scales = "free_y", space = "free_y")
  } else {
    p <- p + facet_grid(feature ~ ., scales = "free_y", space = "free_y")
  }
  p +
    scale_x_continuous(transform = transform,
                       breaks = breaks,
                       labels = scales::label_number(big.mark = ",",
                                                     drop0trailing = TRUE)) +
    labs(x = xlab, y = NULL) +
    description_theme() +
    theme(strip.text.y = element_text(angle = 0, hjust = 0))
}

## a curve per covariate level (black) against the portfolio's (grey), one
## panel per level; d: columns panel, x, value; avg: columns x, value
level_curve_plot <- function(d, avg, xlab, ylab, transform = "identity") {
  d$panel <- factor(d$panel, levels = unique(d$panel))
  ggplot(d, aes(x = x, y = value)) +
    geom_line(data = avg, colour = "grey60", linewidth = 0.9) +
    geom_line() +
    geom_point(size = 0.6) +
    facet_wrap(~panel, ncol = 5) +
    scale_y_continuous(transform = transform) +
    labs(x = xlab, y = ylab) +
    description_theme() +
    theme(strip.text = element_text(size = 6.3))
}

## heat map of the values of two categorical variables, light = small and
## dark = large (white: no value), with the cell labels printed; d: columns
## x, y, value, label and optionally panel (one panel below the other)
tile_plot <- function(d, xlab, ylab, fill, transform = "identity") {
  d$x <- factor(d$x, levels = unique(d$x))
  d$y <- factor(d$y, levels = rev(unique(as.character(d$y))))
  p <- ggplot(d, aes(x = x, y = y, fill = value)) +
    geom_tile(colour = "grey40") +
    geom_text(aes(label = label), size = 2.6, family = "Cambria") +
    scale_fill_gradient(low = "grey94",
                        high = "grey45",
                        transform = transform,
                        labels = scales::label_number(drop0trailing = TRUE),
                        na.value = "white",
                        name = fill) +
    scale_x_discrete(expand = c(0, 0)) +
    scale_y_discrete(expand = c(0, 0)) +
    labs(x = xlab, y = ylab) +
    description_theme() +
    theme(legend.title = element_text(), panel.grid = element_blank())
  if ("panel" %in% names(d)) {
    p <- p + facet_wrap(~panel, scales = "free", ncol = 1)
  }
  p
}
