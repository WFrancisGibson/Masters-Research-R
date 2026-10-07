##########################################
#########  Six lines of business: description of the simulated data
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Tables 1 and 2;
#########  Harkonen (2021), Section 3: Tables 1, 4, 5 and 12-17, Figure 3
##########################################

source(here::here("analysis", "00_setup.R"))
lob_dir <- here::here("analysis", "00_claim-simulation", "lines-of-business")
data_dir <- file.path(paths$raw, cfg$lob$data_dir)
tab_dir <- file.path(paths$tables, "00_claim-simulation/lines-of-business")
fig_dir <- file.path(paths$figures, "00_claim-simulation/lines-of-business")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

n_ay <- cfg$lob$n_ay                           # I = 12, development years 0..11
ay_lab <- cfg$lob$first_ay + 1:n_ay - 1        # 1994..2005
last_ay <- max(ay_lab)                         # 2005, the valuation date I
units <- cfg$lob$units                         # payments in 1'000

##########################################
#########  load data
##########################################

## files of "lines of business simulation.R": payments by LoB, accident year
## AY and development year DY; claim counts N by reporting delay RepDel and
## payments X by payment delay PayDel, by set (vali); paid and X in 1'000
tri_long <- fread(file.path(data_dir, "triangles.csv"), data.table = FALSE)
counts <- fread(file.path(data_dir, "counts.csv"))
payments <- fread(file.path(data_dir, "payments.csv"))
## AY x DY squares of the payments by LoB, incremental and cumulative
tri <- lapply(split(tri_long, tri_long$LoB), function(d) {
  tapply(d$paid, list(AY = d$AY, DY = d$DY), sum)
})
cum <- lapply(tri, function(y) t(apply(y, 1, cumsum)))
lob <- paste("LoB", names(tri))
## claims reported by the end of 2005 (RBNS) and after (IBNR)
reported <- counts$AY + counts$RepDel <= last_ay

##########################################
#########  Harkonen Table 1 (the claims of Paper C Table 1)
##########################################

## number of claims, total payments, share of the claims reported by the end
## of 2005 and true reserves (the payments after 2005)
n_claims <- tapply(counts$N, counts$LoB, sum)
res <- lob_reserves(tri)
harkonen1 <- rbind(
  "N" = c(250040, 250197, 99969, 249683, 249298, 99701),
  "payment" = c(285989, 278621, 108345, 429344, 437728, 171482),
  "RBNS %" = c(99.40, 99.41, 99.26, 99.20, 99.19, 99.10),
  "reserve" = c(39689, 37037, 16878, 71630, 72548, 31117)
)
colnames(harkonen1) <- lob
table1 <- paper_check(
  rbind(n_claims,
        sapply(tri, sum),
        100 * tapply(counts$N * reported, counts$LoB, sum) / n_claims,
        res[, "true"]),
  harkonen1,
  digits = c(0, 0, 2, 0)
)
table1

## Paper C Listing 2: claims of the training set (vali = 1) and of the
## validation set (vali = 2)
tapply(counts$N, list(LoB = counts$LoB, vali = counts$vali), sum)

##########################################
#########  Harkonen Tables 4 and 5, rows "True"
##########################################

## claims reported after 2005 (IBNR), and the payments after 2005 of the
## IBNR claims and of the claims reported by 2005 (RBNS). Her models take the
## payments by accident year, reporting delay and payment delay with the
## negative cells set to zero (Section 3.1); the reserves are shown that way
## and as simulated, both against her Table 5
cells <- payments[, .(X = sum(X)), keyby = .(LoB, AY, RepDel, PayDel)]
cells$X0 <- pmax(cells$X, 0)
ibnr <- cells$AY + cells$RepDel > last_ay
rbns <- cells$AY + cells$RepDel + cells$PayDel > last_ay & !ibnr
ibnr_paper <- c(1597, 1538, 603, 3594, 2739, 1048)
rbns_paper <- c(38093, 35500, 16275, 68038, 69810, 30070)
harkonen45 <- rbind("IBNR claims" = c(1490, 1479, 740, 1992, 2008, 893),
                    "IBNR reserve, negative cells 0" = ibnr_paper,
                    "RBNS reserve, negative cells 0" = rbns_paper,
                    "IBNR reserve, as simulated" = ibnr_paper,
                    "RBNS reserve, as simulated" = rbns_paper)
colnames(harkonen45) <- lob
table45 <- paper_check(
  rbind(tapply(counts$N * (!reported), counts$LoB, sum),
        tapply(cells$X0 * ibnr, cells$LoB, sum),
        tapply(cells$X0 * rbns, cells$LoB, sum),
        tapply(cells$X * ibnr, cells$LoB, sum),
        tapply(cells$X * rbns, cells$LoB, sum)),
  harkonen45
)
table45

##########################################
#########  Harkonen Tables 12-17: cumulative payments
##########################################

## the full squares in 1'000, one row per LoB and accident year
table12_17 <- do.call(rbind, lapply(names(cum), function(m) {
  data.frame(LoB = as.integer(m),
             AY = ay_lab,
             round(cum[[m]]),
             row.names = NULL,
             check.names = FALSE)
}))
names(table12_17)[-(1:2)] <- paste0("DY", 0:(n_ay - 1))
table12_17
## her tables, read off the thesis (the file is next to this script); the
## largest difference of a cell by LoB: 0 if the triangles are hers
harkonen12_17 <- fread(file.path(lob_dir, "harkonen_2021_tables_12-17.csv"),
                       data.table = FALSE)
stopifnot(table12_17$LoB == harkonen12_17$LoB,
          table12_17$AY == harkonen12_17$AY)
cell_diff <- abs(as.matrix(table12_17[, -(1:2)]) -
                   as.matrix(harkonen12_17[, -(1:2)]))
tapply(apply(cell_diff, 1, max), table12_17$LoB, max)

##########################################
#########  Paper C Table 2: chain-ladder reserves
##########################################

## ccODP model on the upper triangles in 1'000: CL reserves, in-sample loss
## (4), out-of-sample loss (6) on the lower triangles, dispersion (5), and
## Mack's rmsep; the bootstrap and analytic rmsep of the table are left to
## the model scripts
table2 <- sapply(names(tri), function(m) {
  y <- tri[[m]]
  odp <- ccodp_fit(upper_triangle(y))
  true <- sum(lower_triangle(y), na.rm = TRUE)
  c(true,
    sum(odp$reserve_o),
    sum(odp$reserve_o) - true,
    odp$deviance,
    poisson_deviance(lower_triangle(y), odp$mu),
    odp$phi_deviance,
    nncl_mack(cum[[m]])$total_se)
})
## the ccODP reserves are the chain-ladder reserves
stopifnot(isTRUE(all.equal(unname(table2[2, ]),
                           unname(res[, "cl"]),
                           tolerance = 1e-6)))
paper2 <- rbind(
  "true reserves" = c(39689, 37037, 16878, 71630, 72548, 31117),
  "CL reserves" = c(38569, 35460, 15692, 67574, 70166, 29409),
  "bias" = c(-1120, -1577, -1186, -4056, -2382, -1708),
  "in-sample loss" = c(491.2, 794.8, 214.4, 999.3, 781.3, 450.0),
  "out-of-sample loss" = c(389.0, 706.9, 331.2, 870.0, 1254.9, 565.8),
  "dispersion" = c(8.93, 14.45, 3.90, 18.17, 14.21, 8.18),
  "Mack rmsep" = c(925, 1106, 424, 1814, 1869, 831)
)
colnames(paper2) <- lob
table2 <- paper_check(table2, paper2, digits = c(0, 0, 0, 1, 1, 2, 0))
table2

fwrite(table1, file.path(tab_dir, "lob_data_harkonen_table1.csv"))
fwrite(table45, file.path(tab_dir, "lob_data_harkonen_tables4-5_true.csv"))
fwrite(table12_17,
       file.path(tab_dir, "lob_data_harkonen_tables12-17_cumulative.csv"))
fwrite(table2, file.path(tab_dir, "lob_data_paper_c_table2.csv"))

##########################################
#########  figures (Harkonen Figure 3)
##########################################

## left: payments of a development year (in 1'000), averaged over the twelve
## accident years of the full square (the caption says "in thousands": the
## payments of the triangle, not per claim)
dy_fig <- data.frame(panel = "development year",
                     series = rep(lob, each = n_ay),
                     x = rep(0:(n_ay - 1), times = length(tri)),
                     value = unlist(lapply(tri, colMeans), use.names = FALSE))
save_figure("LoB data Fig 3 left payments by development year.png",
            series_plot(dy_fig,
                        "development year",
                        "average payment (in 1'000)"),
            fig_dir,
            height = 8)

## right: average claim cost by accident year, the payments of an accident
## year over its number of claims
n_by_ay <- tapply(counts$N, list(AY = counts$AY, LoB = counts$LoB), sum)
ay_fig <- data.frame(panel = "accident year",
                     series = rep(lob, each = n_ay),
                     x = rep(ay_lab, times = length(tri)),
                     value = as.vector(units * sapply(tri, rowSums) / n_by_ay))
save_figure("LoB data Fig 3 right claim cost by accident year.png",
            series_plot(ay_fig, "accident year", "average claim cost"),
            fig_dir,
            height = 8)
