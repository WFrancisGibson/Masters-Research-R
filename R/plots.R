##########################################
#########  Figures
#########  after Paper C (Gabrielli, Richman & Wuthrich 2020), Figures 2, 7, 8
#########  and Al-Mudafer et al. (2021), Figures 3 and 9
##########################################

## save a base graphics or lattice figure (e.g. the ChainLadder plots) to
## output/figures; R evaluates 'expr' (draws the plot) only at out <- expr,
## after png() opened the file
save_plot <- function(file, expr, ...) {
  png(file.path(paths$figures, file), ...)
  on.exit(dev.off())
  out <- expr
  # lattice figures only draw when printed
  if (inherits(out, "trellis")) print(out)
  invisible(out)
}

## deviance losses by gradient descent step (Paper C Figure 2)
loss_plot <- function(h, series, best, title, free_y = FALSE) {
  # e.g. the refit history has no 'vali'
  series <- series[names(series) %in% names(h)]
  d <- data.frame(epoch = rep(h$epoch, length(series)),
                  loss = unlist(h[names(series)]),
                  series = factor(rep(series, each = nrow(h)), levels = series))
  d <- d[!is.na(d$loss), ]
  p <- ggplot(d, aes(x = epoch, y = loss, colour = series)) +
    geom_point(size = 0.6) +
    geom_vline(xintercept = best, linetype = "dotted") +
    scale_colour_manual(values = c("blue",
                                   "red",
                                   "darkgreen")[seq_along(series)],
                        name = NULL) +
    labs(x = "gradient descent iteration",
         y = "deviance losses",
         title = title) +
    theme_bw() + theme(legend.position = "top")
  if (free_y) p <- p + facet_wrap(~series, ncol = 1, scales = "free_y")
  p
}

## heat map of an n x n matrix z (accident x development periods) around 0,
## with the latest diagonal as a staircase; values outside the limits get the
## end colours
triangle_heatmap <- function(z, title, fill, limits = NULL) {
  n <- nrow(z)
  d <- data.frame(AY = as.vector(row(z)),
                  DY = as.vector(col(z)),
                  z = as.vector(z))
  if (is.null(limits)) limits <- c(-1, 1) * max(abs(d$z), na.rm = TRUE)
  stair <- data.frame(x = rep(n + 1.5 - 1:n, each = 2),
                      y = as.vector(rbind(1:n - 0.5, 1:n + 0.5)))
  ggplot(d, aes(x = DY, y = AY, fill = z)) +
    geom_tile() +
    geom_path(data = stair,
              aes(x = x, y = y),
              inherit.aes = FALSE,
              linewidth = 0.4) +
    scale_fill_gradient2(low = "blue",
                         mid = "white",
                         high = "red",
                         midpoint = 0,
                         limits = limits,
                         oob = scales::squish,
                         na.value = "grey92",
                         name = fill) +
    scale_x_continuous(breaks = 1:n, expand = c(0, 0)) +
    scale_y_reverse(breaks = 1:n, expand = c(0, 0)) +
    coord_fixed() +
    labs(x = "development period", y = "accident period", title = title) +
    theme_bw() + theme(panel.grid = element_blank())
}

## cumulative development factors
## g(i,j) = sum_{l <= j} mu(i,l) / mu(i,1), j = 2..n:
## one line per accident period for the bCCNN, the CL factors for the ccODP
## (Paper C Figure 8)
cum_factors_plot <- function(mu_odp, mu_nn, title) {
  n <- nrow(mu_nn)
  # the ccODP has the same CL factors in every accident period:
  # take accident period 1
  g_odp <- cumsum(mu_odp[1, ])[-1] / mu_odp[1, 1]
  # apply() over the rows returns them as columns, t() turns them back
  g_nn <- (t(apply(mu_nn, 1, cumsum)) / mu_nn[, 1])[, -1]
  lab_mid <- "bCCNN, other accident periods"
  lab_end <- "bCCNN, first and last accident period"
  d_nn <- data.frame(AY = rep(1:n, times = n - 1), DY = rep(2:n, each = n),
                     g = as.vector(g_nn))
  d_nn$model <- ifelse(d_nn$AY %in% c(1, n), lab_end, lab_mid)
  d_odp <- data.frame(DY = 2:n, g = g_odp, model = "ccODP CL factors")
  ends <- d_nn[d_nn$AY %in% c(1, n) & d_nn$DY == n, ]
  ggplot() +
    geom_line(data = d_nn,
              aes(x = DY,
                  y = g,
                  group = AY,
                  colour = model),
              linewidth = 0.4) +
    geom_line(data = d_odp,
              aes(x = DY,
                  y = g,
                  colour = model),
              linewidth = 0.9) +
    geom_text(data = ends,
              aes(x = DY,
                  y = g,
                  label = AY),
              hjust = -0.4,
              size = 3,
              colour = "red") +
    scale_colour_manual(values = setNames(c("black",
                                            "blue",
                                            "red"),
                                          c("ccODP CL factors",
                                            lab_mid,
                                            lab_end)),
                        name = NULL) +
    scale_x_continuous(breaks = 2:n) +
    labs(x = "development period",
         y = "cumulative development factor",
         title = title) +
    theme_bw() + theme(legend.position = "top")
}

## reserve bias by accident period, CL versus bCCNN
bias_plot <- function(by_origin, title) {
  models <- c("CL (ccODP)", "bCCNN")
  d <- data.frame(AY = rep(by_origin$origin, 2),
                  model = factor(rep(models, each = nrow(by_origin)),
                                 levels = models),
                  bias = c(by_origin$bias_CL, by_origin$bias_bCCNN))
  ggplot(d, aes(x = factor(AY), y = bias, fill = model)) +
    geom_col(position = "dodge") +
    geom_hline(yintercept = 0) +
    scale_fill_manual(values = c("blue", "red"), name = NULL) +
    labs(x = "accident period", y = "reserve - true reserve", title = title) +
    theme_bw() + theme(legend.position = "top")
}

## training, validation and test cells of a rolling-origin partition on the
## n x n grid (Al-Mudafer et al. 2021, Figures 3 and 9)
partition_plot <- function(part, title) {
  n <- part$n
  role <- matrix(NA, part$origin, part$origin)
  role[part$train] <- "train"
  role[part$vali] <- "validation"
  if (!part$final) role[!is.na(part$test)] <- "test"
  d <- data.frame(AY = as.vector(row(role)),
                  DY = as.vector(col(role)),
                  role = factor(as.vector(role),
                                levels = c("train", "validation", "test")))
  d <- d[!is.na(d$role), ]
  ggplot(d, aes(x = DY, y = AY, fill = role)) +
    geom_tile() +
    scale_fill_manual(values = c(train = "green3",
                                 validation = "darkgreen",
                                 test = "red"),
                      name = NULL) +
    scale_x_continuous(limits = c(0.5, n + 0.5), expand = c(0, 0)) +
    scale_y_reverse(limits = c(n + 0.5, 0.5), expand = c(0, 0)) +
    coord_fixed() +
    labs(x = "development period", y = "accident period", title = title) +
    theme_bw()
}
