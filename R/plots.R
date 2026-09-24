
############################ PLOTTING FUNCTIONS ################################

save_plot <- function(filename, expr, ...) {
  png(file.path(paths$figures, filename), ...)
  on.exit(dev.off())
  expr
}


############################# ccODP / bCCNN FIGURES ############################



# Save a ggplot to output/figures/
save_gg <- function(filename, plot, width = 7, height = 5, dpi = 150) {
  file <- file.path(paths$figures, filename)
  ggplot2::ggsave(file, plot, width = width, height = height, dpi = dpi)
  invisible(file)
}

# Deviance losses by gradient-descent step
plot_loss_curves <- function(history,
                             series = c(train_dropout = "training loss (in-sample)", # nolint
                                        vali = "validation loss (out-of-sample)"), # nolint 
                             best_epoch = NULL, free_y = FALSE, title = NULL) {
  keep <- intersect(names(series), names(history))
  long <- do.call(rbind, lapply(keep, function(k) {
    data.frame(epoch = history$epoch, loss = history[[k]], series = series[[k]])
  }))
  long <- long[!is.na(long$loss), ]
  long$series <- factor(long$series, levels = unname(series[keep]))
  colours <- stats::setNames(c("blue",
                               "red",
                               "darkgreen",
                               "grey30")[seq_along(keep)],
                             unname(series[keep]))
  p <- ggplot2::ggplot(long,
                       ggplot2::aes(x = epoch, y = loss, colour = series)) +
    ggplot2::geom_point(size = 0.6) +
    ggplot2::scale_colour_manual(values = colours, name = NULL) +
    ggplot2::labs(x = "gradient descent iteration", y = "deviance losses",
                  title = title) +
    ggplot2::theme_bw() +
    ggplot2::theme(legend.position = "top")
  if (!is.null(best_epoch)) {
    p <- p + ggplot2::geom_vline(xintercept = best_epoch, linetype = "dotted")
  }
  if (free_y) {
    p <- p + ggplot2::facet_wrap(~series, ncol = 1, scales = "free_y")
  }
  p
}


# Heat map of an n x n matrix over accident x development periods, with the
# latest diagonal drawn as a staircase (observed cells above-left of it).
# Diverging colours around 0; values outside `limits` get the end colours.
triangle_heatmap <- function(z, title = NULL, fill_name = NULL, limits = NULL) {
  d <- triangle_long(z)
  n <- max(d$origin)
  if (is.null(limits)) {
    r <- max(abs(d$value), na.rm = TRUE)
    if (!is.finite(r) || r == 0) r <- 1
    limits <- c(-r, r)
  }
  stair <- data.frame(x = rep(n + 1.5 - seq_len(n), each = 2),
                      y = as.vector(rbind(seq_len(n) - 0.5, seq_len(n) + 0.5)))
  ggplot2::ggplot(d, ggplot2::aes(x = dev, y = origin, fill = value)) +
    ggplot2::geom_tile() +
    ggplot2::geom_path(data = stair, ggplot2::aes(x = x, y = y),
                       inherit.aes = FALSE, linewidth = 0.4) +
    ggplot2::scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                                  midpoint = 0, limits = limits,
                                  oob = scales::squish, na.value = "grey92",
                                  name = fill_name) +
    ggplot2::scale_x_continuous(breaks = seq_len(n), expand = c(0, 0)) +
    ggplot2::scale_y_reverse(breaks = seq_len(n), expand = c(0, 0)) +
    ggplot2::coord_fixed() +
    ggplot2::labs(x = "development period",
                  y = "accident period", title = title) +
    ggplot2::theme_bw() +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
}


# Relative difference of two fitted mean squares
plot_relative_difference <- function(mu_ref,
                                     mu_new,
                                     limits = NULL,
                                     title = NULL) {
  z <- unname(as.matrix(mu_new)) / unname(as.matrix(mu_ref)) - 1
  triangle_heatmap(z, title = title, fill_name = "relative\ndifference",
                   limits = limits)
}


#' Pearson residuals on a heat map (Paper C, Figure 7)
#'
#' (y - mu) / sqrt(phi * mu), shown where y is not NA: pass the true lower
#' triangle (triangle_sets()$test / scale) for Paper C's out-of-sample view,
#' or the observed upper triangle for in-sample residuals.
#'
#' @param y observed values, n x n, NA = not shown (units of mu).
#' @param mu n x n means; phi the model's dispersion.
#' @param limits colour-scale limits; use the same for the models compared.
#' @param title plot title.
plot_pearson_residuals <- function(y, mu, phi, limits = NULL, title = NULL) {
  triangle_heatmap(pearson_residuals(y, mu, phi), title = title,
                   fill_name = "Pearson\nresidual", limits = limits)
}


# Cumulative development factors, ccODP versus bCCNN

plot_cum_dev_factors <- function(mu_odp, mu_nn, title = NULL) {
  g_nn <- cum_dev_factors(mu_nn)
  n <- nrow(g_nn)
  lab_mid <- "bCCNN, other accident periods"
  lab_end <- "bCCNN, first and last accident period"
  d_nn <- data.frame(origin = rep(seq_len(n), times = ncol(g_nn)),
                     dev = rep(2:n, each = n), g = as.vector(g_nn))
  d_nn$model <- ifelse(d_nn$origin %in% c(1, n), lab_end, lab_mid)
  d_odp <- data.frame(dev = 2:n, g = cum_dev_factors(mu_odp)[1, ],
                      model = "ccODP CL factors")
  ends <- d_nn[d_nn$origin %in% c(1, n) & d_nn$dev == n, ]
  ggplot2::ggplot() +
    ggplot2::geom_line(data = d_nn,
                       ggplot2::aes(x = dev,
                                    y = g,
                                    group = origin,
                                    colour = model),
                       linewidth = 0.4) +
    ggplot2::geom_line(data = d_odp, ggplot2::aes(x = dev,
                                                  y = g,
                                                  colour = model),
                       linewidth = 0.9) +
    ggplot2::geom_text(data = ends, ggplot2::aes(x = dev,
                                                 y = g,
                                                 label = origin),
                       hjust = -0.4, size = 3, colour = "red") +
    ggplot2::scale_colour_manual(values = stats::setNames(c("black",
                                                            "blue",
                                                            "red"),
                                                          c("ccODP CL factors",
                                                            lab_mid, lab_end)),
                                 name = NULL) +
    ggplot2::scale_x_continuous(breaks = 2:n) +
    ggplot2::labs(x = "development period", y = "cumulative development factor",
                  title = title) +
    ggplot2::theme_bw() +
    ggplot2::theme(legend.position = "top")
}


# Reserve bias by accident period, CL versus bCCNN

plot_bias_by_origin <- function(by_origin, title = NULL) {
  bo <- by_origin[by_origin$origin != "total", ]
  d <- rbind(data.frame(origin = as.integer(bo$origin), model = "CL (ccODP)",
                        bias = bo$bias_CL),
             data.frame(origin = as.integer(bo$origin), model = "bCCNN",
                        bias = bo$bias_bCCNN))
  d$model <- factor(d$model, levels = c("CL (ccODP)", "bCCNN"))
  ggplot2::ggplot(d, ggplot2::aes(x = factor(origin), y = bias, fill = model)) +
    ggplot2::geom_col(position = "dodge") +
    ggplot2::geom_hline(yintercept = 0) +
    ggplot2::scale_fill_manual(values = c("CL (ccODP)" = "blue",
                                          "bCCNN" = "red"),
                               name = NULL) +
    ggplot2::labs(x = "accident period", y = "reserve - true reserve",
                  title = title) +
    ggplot2::theme_bw() +
    ggplot2::theme(legend.position = "top")
}


# Rolling-origin partition of a triangle into training, validation and test
# cells (Al-Mudafer et al. 2021, Figures 3 and 9); part is one element of
# rolling_origin_sets(), drawn on the full n x n grid
plot_partition <- function(part, title = NULL) {
  n <- part$n
  role <- matrix(NA_character_, n, n)
  idx <- seq_len(part$origin)
  role[idx, idx] <- part$role
  d <- triangle_long(role)
  d <- d[!is.na(d$value), ]
  d$value <- droplevels(factor(d$value,
                               levels = c("train", "validation", "test")))
  ggplot2::ggplot(d, ggplot2::aes(x = dev, y = origin, fill = value)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_manual(values = c(train = "green3",
                                          validation = "darkgreen",
                                          test = "red"),
                               name = NULL) +
    ggplot2::scale_x_continuous(limits = c(0.5, n + 0.5), expand = c(0, 0)) +
    ggplot2::scale_y_reverse(limits = c(n + 0.5, 0.5), expand = c(0, 0)) +
    ggplot2::coord_fixed() +
    ggplot2::labs(x = "development period", y = "accident period",
                  title = title) +
    ggplot2::theme_bw()
}
