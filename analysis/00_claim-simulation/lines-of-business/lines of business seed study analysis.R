##########################################
#########  Six lines of business: reserves of the simulations with
#########  different seeds
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Appendix A, Table 8
#########  and Figures 9-10 (SSRN version of 2018: Table 7, Figures 7-8)
##########################################

## the data set of this script, all its LoBs: no unit, whatever the session
## inherits (the paths of a unit are <dataset>/<unit>)
Sys.setenv(DATASET = "lob6", UNIT = "")
source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "00_claim-simulation/lines-of-business")
fig_dir <- file.path(paths$figures, "00_claim-simulation/lines-of-business")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
units <- cfg$data$scale                        # reserves in 1'000
## the paper: seeds 1 to 100, the selected simulation (seed 75) among them
seeds <- union(seq_len(cfg$lob$seed_study$seeds), cfg$lob$simulation$seed1)
selected <- as.character(cfg$lob$simulation$seed1)

##########################################
#########  load the simulations
##########################################

## files of "lines of business seed study.R", one per seed: number of
## claims, true reserves and chain-ladder reserves by LoB, and the seconds
## the simulation took
runs <- lapply(seeds, function(s) {
  readRDS(file.path(paths$processed, sprintf("lob_seed_study_%03d.rds", s)))
})
names(runs) <- seeds
round(summary(sapply(runs, function(r) r$seconds)))
runs <- lapply(runs, function(r) r$reserves)

##########################################
#########  Table 8
##########################################

## reserves in 1'000, LoB x seed
true <- sapply(runs, function(r) r[, "true"]) / units
cl_res <- sapply(runs, function(r) r[, "cl"]) / units
lob <- paste("LoB", rownames(true))

table8 <- rbind(rowMeans(true),
                apply(true, 1, sd),
                100 * apply(true, 1, sd) / rowMeans(true),
                true[, selected],
                rowMeans(cl_res),
                apply(cl_res, 1, sd),
                100 * apply(cl_res, 1, sd) / rowMeans(cl_res),
                cl_res[, selected],
                rowMeans(cl_res - true),
                cl_res[, selected] - true[, selected])
paper8 <- rbind(
  "(1) average true reserves" = c(40533, 40232, 18661, 73224, 73445, 33689),
  "(2) standard deviation" = c(1871, 1986, 1645, 3029, 2918, 2493),
  "(3) coefficient of variation %" = c(4.6, 4.9, 8.8, 4.1, 4.0, 7.4),
  "(4) true reserves, selected seed" =
    c(39689, 37037, 16878, 71630, 72548, 31117),
  "(5) average CL reserves" = c(38513, 38232, 17735, 70280, 70594, 32563),
  "(6) standard deviation" = c(1560, 1619, 1585, 2796, 2430, 2303),
  "(7) coefficient of variation %" = c(4.0, 4.2, 8.9, 4.0, 3.4, 7.1),
  "(8) CL reserves, selected seed" =
    c(38569, 35460, 15692, 67574, 70166, 29409),
  "(9) average bias" = c(-2020, -1999, -925, -2944, -2851, -1126),
  "(10) bias, selected seed" = c(-1120, -1577, -1186, -4056, -2382, -1708)
)
colnames(paper8) <- lob
table8 <- paper_check(table8, paper8, digits = c(0, 0, 1, 0, 0, 0, 1, 0, 0, 0))
table8

## the simulations: one row per seed and LoB
by_seed <- data.frame(seed = rep(seeds, each = nrow(true)),
                      LoB = rep(as.integer(rownames(true)), times = ncol(true)),
                      claims = unlist(lapply(runs, function(r) r[, "claims"]),
                                      use.names = FALSE),
                      true_reserves = as.vector(true),
                      cl_reserves = as.vector(cl_res))

fwrite(table8, file.path(tab_dir, "lob_seeds_paper_c_table8.csv"))
fwrite(by_seed, file.path(tab_dir, "lob_seeds_reserves_by_seed.csv"))

##########################################
#########  figures (Figures 9 and 10)
##########################################

## Figure 9: densities of the true reserves and of the CL reserves over the
## simulations by LoB; dots: the selected simulation, vertical lines: the
## averages
series <- c("true reserves", "CL reserves")
dens <- data.frame(panel = rep(lob, times = 2 * ncol(true)),
                   series = rep(series, each = length(true)),
                   value = c(true, cl_res))
sel <- data.frame(panel = rep(lob, times = 2),
                  series = rep(series, each = nrow(true)),
                  value = c(true[, selected], cl_res[, selected]))
save_figure("LoB seeds Fig 9 reserves by LoB.png",
            reserve_density_plot(dens, sel),
            fig_dir,
            height = 12)

## Figure 10: the same, aggregated over the six LoBs
dens_all <- data.frame(panel = "all LoBs",
                       series = rep(series, each = ncol(true)),
                       value = c(colSums(true), colSums(cl_res)))
sel_all <- data.frame(panel = "all LoBs",
                      series = series,
                      value = c(sum(true[, selected]),
                                sum(cl_res[, selected])))
save_figure("LoB seeds Fig 10 reserves all LoBs.png",
            reserve_density_plot(dens_all, sel_all),
            fig_dir,
            height = 8,
            width = 12)
