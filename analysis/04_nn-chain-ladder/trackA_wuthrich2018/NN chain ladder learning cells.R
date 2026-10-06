##########################################
#########  NN chain ladder: learning cells of the CL factor networks
#########  Wuthrich (2018), Neural networks applied to chain-ladder
#########  reserving, EAJ 8:407-436, Section 3; figure layout after the
#########  Department's Research Assignment Guide (2026), Sections 5.3, 5.7
##########################################

## reads the cells of "NN chain ladder fit.R" (no Keras needed)
source(here::here("analysis", "00_setup.R"))
fig_dir <- file.path(paths$figures, "04_NN-chain-ladder/model")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$nncl$n_ay                          # I = 12, J = I - 1 = 11
nets <- c(1, 2, 5, 11)                         # networks j shown

##########################################
#########  learning cells per network
##########################################

cells <- readRDS(file.path(paths$interim, "nncl_cells.rds"))
cum <- as.matrix(cells[, paste0("cum_", 0:(n_ay - 1)), with = FALSE])

## learning cells of development period j: i <= I - j, C_{i,j-1}(x) > 0
n_learn <- sapply(nets, function(j) {
  sum(cells$i <= n_ay - j & cum[, j] > 0)
})

##########################################
#########  triangle cells by role
##########################################

## guide 5.3: a hard space separates the thousands
hard_space <- function(n) format(n, big.mark = " ", trim = TRUE)
net_lab <- sprintf("Network j = %d: C(%d) to C(%d)\n%s cells",
                   nets, nets - 1, nets, hard_space(n_learn))

roles <- c("input C(j-1)", "target C(j)", "observed, not used",
           "latest diagonal")
d <- NULL
for (k in seq_along(nets)) {
  j <- nets[k]
  g <- expand.grid(i = 1:n_ay, dev = 0:(n_ay - 1))
  g <- g[g$i + g$dev <= n_ay, ]                # observed upper triangle
  g$role <- "observed, not used"
  g$role[g$i + g$dev == n_ay] <- "latest diagonal"
  g$role[g$i <= n_ay - j & g$dev == j - 1] <- "input C(j-1)"
  g$role[g$i <= n_ay - j & g$dev == j] <- "target C(j)"
  g$net <- factor(net_lab[k], levels = net_lab)
  d <- rbind(d, g)
}
d$role <- factor(d$role, levels = roles)

##########################################
#########  figure
##########################################

## guide 5.7: no title in the figure (number and heading go below it in the
## report), axes marked, legible in black and white; 16.5 cm text width,
## Cambria 10 point
fill_role <- c("input C(j-1)" = "grey10",
               "target C(j)" = "grey55",
               "observed, not used" = "grey88",
               "latest diagonal" = "white")
p <- ggplot(d, aes(x = dev, y = i, fill = role)) +
  geom_tile(colour = "black", linewidth = 0.2) +
  facet_wrap(~net, ncol = 2) +
  scale_fill_manual(values = fill_role, name = NULL) +
  scale_x_continuous(breaks = 0:(n_ay - 1), expand = c(0, 0)) +
  scale_y_reverse(breaks = 1:n_ay, expand = c(0, 0)) +
  labs(x = "Development year", y = "Accident year") +
  theme_bw(base_size = 10, base_family = "Cambria") +
  theme(panel.grid = element_blank(),
        strip.text = element_text(hjust = 0),
        legend.position = "bottom")
ggsave("NNCL learning cells.png",
       p,
       path = fig_dir,
       device = ragg::agg_png,
       width = 16.5, height = 13, units = "cm", dpi = 300)
