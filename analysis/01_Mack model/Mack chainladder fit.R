##########################################
#########  Mack chain ladder on the annual claims triangle
#########  Mack (1993), distribution-free chain ladder with standard errors
##########################################

source(here::here("analysis", "00_setup.R"))

##########################################
#########  load data
##########################################

## 20 x 20 incremental triangle at the valuation date (year 20),
## development years 1..20;
## the payments after development year 20 (sets$tail) are reported apart
n <- cfg$data$n_dev
trans <- fread(file.path(paths$raw, cfg$data$annual_dir, "transactions.csv"),
               select = c("claim_no", "occurrence_period", "payment_period",
                          "payment_inflated"), data.table = FALSE)
sets <- triangle_sets(trans, n)
tri <- incr2cum(as.triangle(sets$upper))       # cumulative observed triangle

##########################################
#########  Mack chain ladder
##########################################

mack <- MackChainLadder(tri, est.sigma = "Mack")
mack

## reserves and back-test against the true reserves to development year 20
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
save_reserves(res, total, "mack_raw")

##########################################
#########  figures
##########################################

save_plot("MackCL Development Pattern.png", plot(mack))
save_plot("MackCL Triangle.png", plot(tri))
save_plot("MackCL development by origin period.png",
          plot(mack, lattice = TRUE))

## cumulative observed triangle to data/interim
fwrite(data.frame(origin = 1:n, unclass(tri), check.names = FALSE),
       file.path(paths$interim, "tri_mack.csv"))
