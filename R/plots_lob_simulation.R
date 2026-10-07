##########################################
#########  Figures of the six lines of business
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Figures 9 and 10
##########################################

## densities of the reserves over the simulations with different seeds, a
## panel per LoB; d: columns panel, series (true reserves, CL reserves),
## value; the vertical lines give the averages of the series and the dots the
## selected simulation (sel: same columns); theme of the description figures
reserve_density_plot <- function(d, sel) {
  d$panel <- factor(d$panel, levels = unique(d$panel))
  d$series <- factor(d$series, levels = unique(d$series))
  sel$panel <- factor(sel$panel, levels = levels(d$panel))
  sel$series <- factor(sel$series, levels = levels(d$series))
  avg <- aggregate(value ~ panel + series, data = d, FUN = mean)
  ggplot(d, aes(x = value)) +
    geom_line(aes(linetype = series), stat = "density") +
    geom_vline(data = avg,
               aes(xintercept = value, linetype = series),
               colour = "grey50") +
    geom_point(data = sel, aes(y = 0, shape = series), size = 2) +
    facet_wrap(~panel, scales = "free") +
    scale_x_continuous(labels = scales::label_comma()) +
    labs(x = "reserves (in 1'000)", y = "density") +
    description_theme()
}
