##########################################
#########  NN chain ladder on the SynthETIC portfolio: training,
#########  validation and test cells of the CL factor networks
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Section 3 and Listing 2; figure layout
#########  after the Department's Research Assignment Guide (2026), Sections
#########  5.3 and 5.7
##########################################

## reads the cells of "NN chain ladder SynthETIC fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
fig_dir <- file.path(paths$figures, "04_NN-chain-ladder/synthetic")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$data$n_dev                         # I = 20, J = I - 1 = 19
vali_split <- cfg$nncl$training$validation_split
nets <- c(1, 2, 10, 19)                        # networks j of the first figure

##########################################
#########  training, validation and test cells per network
##########################################

cells <- readRDS(file.path(paths$interim, "nncl_synthetic_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])

## learning cells of development period j: i <= I - j, C_{i,j-1}(x) > 0, in
## the row order of the fit script (accident year, then the features); Keras
## trains on the first floor(0.9 n_j) rows and validates on the last 10%
## (validation_split, no shuffling); train, vali: rows by accident year i
## and development period j
train <- vali <- matrix(0, n_ay, n_ay - 1)
for (j in 1:(n_ay - 1)) {
  r <- which(cells$i <= n_ay - j & cum[, j] > 0)
  n_train <- floor(length(r) * (1 - vali_split))  # Keras's split
  train[, j] <- tabulate(cells$i[r[seq_len(n_train)]], n_ay)
  vali[, j] <- tabulate(cells$i[r[-seq_len(n_train)]], n_ay)
}

## test: the accident years i > I - j, where network j gives the factor of
## the cells with C_{i,I-i}(x) > 0 (5.1); C_{i,j}(x) is not observed at the
## end of year I (SynthETIC: the truth is known)
n_test <- sapply(1:(n_ay - 1), function(j) {
  sum(cells$i > n_ay - j & cells$c_diag > 0)
})

## rows and accident years of the three sets by development period
ay_range <- function(rows) {
  apply(rows > 0, 2, function(k) paste(range(which(k)), collapse = "-"))
}
data.frame(j = 1:(n_ay - 1),
           learning = colSums(train + vali),
           train = colSums(train),
           validation = colSums(vali),
           ay_train = ay_range(train),
           ay_validation = ay_range(vali),
           test = n_test,
           ay_test = paste0(n_ay - 1:(n_ay - 1) + 1, "-", n_ay))

##########################################
#########  triangle cells by role
##########################################

## as "NN chain ladder learning cells.R": per network j the triangle, with
## the columns C(j-1) (input) and C(j) (target) by the set of their rows.
## The accident year in which Keras's split falls has training and validation
## rows: its tiles are split at the share of the training rows, training
## rows above the validation rows (the row order)
roles <- c("train", "validation", "test", "observed, not used")
d <- NULL
for (j in 1:(n_ay - 1)) {
  g <- expand.grid(i = 1:n_ay, dev = 0:(n_ay - 1), j = j)
  g$ymin <- g$i - 0.5
  g$ymax <- g$i + 0.5
  pair <- g$dev %in% c(j - 1, j)
  learn <- g[pair & g$i <= n_ay - j, ]
  split <- learn$ymin + (train[, j] / (train[, j] + vali[, j]))[learn$i]
  d <- rbind(d,
             cbind(transform(learn, ymax = split), role = "train"),
             cbind(transform(learn, ymin = split), role = "validation"),
             cbind(g[pair & g$i > n_ay - j, ], role = "test"),
             cbind(g[!pair & g$i + g$dev <= n_ay, ],
                   role = "observed, not used"))
}
d <- d[d$ymax > d$ymin, ]
d$role <- factor(d$role, levels = roles)

##########################################
#########  figures
##########################################

## guide 5.7: no title in the figure (number and heading go below it in the
## report), axes marked, legible in black and white; 16.5 cm text width,
## Cambria 10 point; fills of partition_plot() in R/plots.R;
## by: every by-th year on the axes
fill_role <- c("train" = "grey88",
               "validation" = "grey10",
               "test" = "grey55",
               "observed, not used" = "white")
role_plot <- function(d, net_lab, ncol, by, linewidth) {
  d$net <- factor(net_lab[d$j], levels = net_lab)
  ggplot(d, aes(xmin = dev - 0.5,
                xmax = dev + 0.5,
                ymin = ymin,
                ymax = ymax,
                fill = role)) +
    geom_rect(colour = "black", linewidth = linewidth) +
    facet_wrap(~net, ncol = ncol) +
    scale_fill_manual(values = fill_role, name = NULL) +
    scale_x_continuous(breaks = seq(0, n_ay - 1, by), expand = c(0, 0)) +
    scale_y_reverse(breaks = unique(c(1, seq(by, n_ay, by))),
                    expand = c(0, 0)) +
    labs(x = "Development year", y = "Accident year") +
    theme_bw(base_size = 10, base_family = "Cambria") +
    theme(panel.grid = element_blank(),
          axis.text = element_text(size = 7),
          strip.text = element_text(hjust = 0),
          legend.position = "bottom")
}

## four networks, with the cells of the three sets (guide 5.3: a hard space
## separates the thousands)
hard_space <- function(n) format(n, big.mark = " ", trim = TRUE)
net_lab <- sprintf(paste0("Network j = %d: C(%d) to C(%d)\n",
                          "%s train, %s validation, %s test cells"),
                   1:(n_ay - 1),
                   1:(n_ay - 1) - 1,
                   1:(n_ay - 1),
                   hard_space(colSums(train)),
                   hard_space(colSums(vali)),
                   hard_space(n_test))
ggsave("NNCL SynthETIC train validation test cells.png",
       role_plot(d[d$j %in% nets, ],
                 net_lab,
                 ncol = 2,
                 by = 1,
                 linewidth = 0.2),
       path = fig_dir,
       device = ragg::agg_png,
       width = 16.5, height = 17.5, units = "cm", dpi = 300)

## all networks j = 1..J
net_lab <- sprintf("j = %d: C(%d) to C(%d)",
                   1:(n_ay - 1),
                   1:(n_ay - 1) - 1,
                   1:(n_ay - 1))
ggsave("NNCL SynthETIC train validation test cells all networks.png",
       role_plot(d,
                 net_lab,
                 ncol = 4,
                 by = 5,
                 linewidth = 0.1),
       path = fig_dir,
       device = ragg::agg_png,
       width = 16.5, height = 21, units = "cm", dpi = 300)
