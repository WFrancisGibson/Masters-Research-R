##########################################
#########  The simulated individual claims: description
#########  Gabrielli & Wuthrich (2018), Risks 6(2):29, Tables 3, 5, 6, 7
#########  and Figures A1-A4; Wuthrich (2018), EAJ 8:407-436, Figures 5-6
##########################################

source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "04_NN-chain-ladder/data-description")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$nncl$n_ay                          # I = 12, development years 0..11
first_ay <- cfg$nncl$first_ay                  # 1994
units <- cfg$nncl$risks_units                  # Risks tables in 10'000
pay_cols <- sprintf("Pay%02d", 0:(n_ay - 1))
ay_lab <- first_ay:(first_ay + n_ay - 1)

##########################################
#########  load data
##########################################

## claims of analysis/00_claim-simulation/individual_claims_simulation_machine.R
claims <- fread(file.path(paths$raw, cfg$nncl$data_dir, "claims.csv"),
                select = c("LoB", "cc", "AY", "AQ", "age", "inj_part",
                           "RepDel", pay_cols))
claims$i <- claims$AY - first_ay + 1           # accident year i = 1..I
pay <- as.matrix(claims[, pay_cols, with = FALSE])
## claim size = total payments (net of recoveries); K = number of development
## years with a payment (Risks Section 3); recoveries = negative payments
claims$size <- rowSums(pay)
claims$k <- rowSums(pay != 0)
claims$recovery <- rowSums(pay < 0) > 0
paid <- claims$k > 0

##########################################
#########  tables (Risks Tables 3, 5, 6, 7)
##########################################

## Table 3: reported claims by accident year and reporting delay T;
## observed at the end of 2005: AY + T <= 2005
n_rep <- claims[, .N, keyby = .(i, RepDel)]
tri_n <- matrix(0, n_ay, n_ay, dimnames = list(AY = ay_lab, T = 0:(n_ay - 1)))
tri_n[cbind(n_rep$i, n_rep$RepDel + 1)] <- n_rep$N
upper_triangle(tri_n)

## Table 5: cumulative payments (all LoBs) by accident and development year
tri_c <- t(apply(rowsum(pay, claims$i), 1, cumsum))
dimnames(tri_c) <- list(AY = ay_lab, dev = 0:(n_ay - 1))
round(upper_triangle(tri_c) / units)

## Table 6: chain-ladder predicted IBNYR claim counts (claims reported after
## 2005) and Mack's sqrt(msep), against the true IBNYR counts
mack_n <- nncl_mack(t(apply(tri_n, 1, cumsum)))
table6 <- data.frame(AY = ay_lab,
                     CL_IBNYR = mack_n$by_origin$ibnr,
                     msep_sqrt = mack_n$by_origin$se,
                     msep_pct = 100 * mack_n$by_origin$cv,
                     true_IBNYR = mack_n$by_origin$true)
table6 <- rbind(table6,
                data.frame(AY = "total",
                           CL_IBNYR = sum(table6$CL_IBNYR),
                           msep_sqrt = mack_n$total_se,
                           msep_pct = 100 * mack_n$total_se /
                             sum(table6$CL_IBNYR),
                           true_IBNYR = sum(table6$true_IBNYR)))
table6[, -1] <- round(table6[, -1])
table6

## Table 7: chain-ladder reserves and Mack's sqrt(msep) (in 10'000), against
## the true outstanding payments
mack_c <- nncl_mack(tri_c)
table7 <- data.frame(AY = ay_lab,
                     CL_reserves = mack_c$by_origin$ibnr,
                     msep_sqrt = mack_c$by_origin$se,
                     true_reserves = mack_c$by_origin$true)
table7 <- rbind(table7,
                data.frame(AY = "total",
                           CL_reserves = sum(table7$CL_reserves),
                           msep_sqrt = mack_c$total_se,
                           true_reserves = sum(table7$true_reserves)))
table7[, -1] <- round(table7[, -1] / units)
table7

fwrite(data.frame(AY = ay_lab, upper_triangle(tri_n), check.names = FALSE),
       file.path(tab_dir, "nncl_data_table3_reported_claims.csv"))
fwrite(data.frame(AY = ay_lab, upper_triangle(tri_c) / units,
                  check.names = FALSE),
       file.path(tab_dir, "nncl_data_table5_cumulative_payments.csv"))
fwrite(table6, file.path(tab_dir, "nncl_data_table6_ibnyr_counts.csv"))
fwrite(table7, file.path(tab_dir, "nncl_data_table7_cl_reserves.csv"))

##########################################
#########  figures (Risks Figs. A1-A4, EAJ Figs. 5-6)
##########################################

fig_dir <- file.path(paths$figures, "04_NN-chain-ladder/data-description")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

features <- c("LoB", "cc", "AY", "AQ", "age", "inj_part")

## Fig. A1: number of claims per label of each feature; EAJ Fig. 5: the same
## as relative frequencies
by_feature <- rbindlist(lapply(features, function(v) {
  claims[, .(panel = v, value = .N), keyby = .(label = get(v))]
}))
ggsave("NNCL data Fig A1 claims by feature.png",
       nncl_feature_bar_plot(by_feature,
                             "number of claims",
                             "Portfolio distributions (Risks Fig. A1)"),
       path = fig_dir, width = 10, height = 6, dpi = 150)
by_feature$value <- by_feature$value / nrow(claims)
ggsave("NNCL data Fig 5 relative frequencies.png",
       nncl_feature_bar_plot(by_feature,
                             "relative frequency",
                             "Marginal distributions (EAJ Fig. 5)"),
       path = fig_dir, width = 10, height = 6, dpi = 150)

## Fig. A2: by reporting delay T; Fig. A3: by number of payments K;
## claim sizes over the claims with a payment
panels <- c("(a) log number of claims",
            "(b) average claim size",
            "(c) average number of payments")
by_delay <- rbind(
  claims[, .(panel = panels[1], value = log(.N)), keyby = .(label = RepDel)],
  claims[paid, .(panel = panels[2], value = mean(size)),
         keyby = .(label = RepDel)],
  claims[, .(panel = panels[3], value = mean(k)), keyby = .(label = RepDel)]
)
ggsave("NNCL data Fig A2 by reporting delay.png",
       nncl_feature_bar_plot(by_delay,
                             NULL,
                             "By reporting delay T (Risks Fig. A2)",
                             data.frame(panel = panels[2:3],
                                        value = c(mean(claims$size[paid]),
                                                  mean(claims$k)))),
       path = fig_dir, width = 10, height = 4, dpi = 150)
panels <- c("(a) log number of claims",
            "(b) average claim size",
            "(c) number of claims with recoveries")
by_payments <- rbind(
  claims[, .(panel = panels[1], value = log(.N)), keyby = .(label = k)],
  claims[paid, .(panel = panels[2], value = mean(size)), keyby = .(label = k)],
  claims[, .(panel = panels[3], value = sum(recovery)), keyby = .(label = k)]
)
ggsave("NNCL data Fig A3 by number of payments.png",
       nncl_feature_bar_plot(by_payments,
                             NULL,
                             "By number of payments K (Risks Fig. A3)",
                             data.frame(panel = panels[2],
                                        value = mean(claims$size[paid]))),
       path = fig_dir, width = 10, height = 4, dpi = 150)

## Fig. A4: average claim size per label of each feature
size_by_feature <- rbindlist(lapply(features, function(v) {
  claims[paid, .(panel = v, value = mean(size)), keyby = .(label = get(v))]
}))
ggsave("NNCL data Fig A4 claim size by feature.png",
       nncl_feature_bar_plot(size_by_feature,
                             "average claim size",
                             "Average claim size (Risks Fig. A4)",
                             data.frame(panel = features,
                                        value = mean(claims$size[paid]))),
       path = fig_dir, width = 10, height = 6, dpi = 150)

## EAJ Fig. 6: two-dimensional contour plots of the portfolio distribution,
## numbers of claims relative to the largest one of each panel
pairs <- combn(c("LoB", "cc", "age", "inj_part"), 2)
contours <- rbindlist(lapply(seq_len(ncol(pairs)), function(k) {
  a <- pairs[1, k]
  b <- pairs[2, k]
  grid <- CJ(x = sort(unique(claims[[a]])), y = sort(unique(claims[[b]])))
  n_ab <- claims[, .N, by = c(a, b)]
  grid$n <- 0
  grid$n[match(paste(n_ab[[a]], n_ab[[b]]), paste(grid$x, grid$y))] <- n_ab$N
  grid$n <- grid$n / max(grid$n)
  grid$panel <- paste(b, "against", a)
  grid
}))
contours$panel <- factor(contours$panel, levels = unique(contours$panel))
ggsave("NNCL data Fig 6 contours.png",
       ggplot(contours, aes(x = x, y = y, z = n)) +
         geom_contour_filled(breaks = c(0, 0.01, 0.05, 0.1, 0.2, 0.4, 0.6,
                                        0.8, 1)) +
         facet_wrap(~panel, scales = "free") +
         labs(x = NULL, y = NULL, fill = "claims / maximum",
              title = "Two-dimensional portfolio distributions (EAJ Fig. 6)") +
         theme_bw(),
       path = fig_dir, width = 11, height = 7, dpi = 150)
