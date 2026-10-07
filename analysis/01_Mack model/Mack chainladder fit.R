##########################################
#########  Mack chain ladder on the claims triangle of the data set
#########  Mack (1993), distribution-free chain ladder with standard errors
##########################################

source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "01_Mack")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

##########################################
#########  load data
##########################################

## n x n incremental triangle at the valuation date (period n), development
## periods 1..n, of "claims triangles.R": one triangle, i.e. a SynthETIC
## data set or one LoB of the six (DATASET=lob6 UNIT=lob1);
## the payments after development period n (sets$tail) are reported apart
n <- cfg$data$n_dev
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
tri <- incr2cum(as.triangle(sets$upper))       # cumulative observed triangle

##########################################
#########  Mack chain ladder
##########################################

mack <- MackChainLadder(tri, est.sigma = "Mack")
mack

## reserves and back-test against the true reserves to development period n
latest <- as.numeric(getLatestCumulative(tri))
res <- reserves_table(latest,
                      ibnr = as.numeric(mack$FullTriangle[, n]) - latest,
                      se = as.numeric(mack$Mack.S.E[, n]),
                      true = rowSums(sets$test, na.rm = TRUE))
total <- reserves_total(res,
                        ibnr = sum(res$ibnr),
                        se = unname(mack$Total.Mack.S.E),
                        tail = sum(sets$tail))
round(total)
save_reserves(res, total, "mack_raw", tab_dir)

##########################################
#########  figures
##########################################

fig_dir <- file.path(paths$figures, "01_Mack")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

save_plot("MackCL Development Pattern.png", plot(mack), dir = fig_dir)
save_plot("MackCL Triangle.png", plot(tri), dir = fig_dir)
save_plot("MackCL development by origin period.png",
          plot(mack, lattice = TRUE), dir = fig_dir)

## cumulative observed triangle to data/interim
fwrite(data.frame(origin = 1:n, unclass(tri), check.names = FALSE),
       file.path(paths$interim, "tri_mack.csv"))
