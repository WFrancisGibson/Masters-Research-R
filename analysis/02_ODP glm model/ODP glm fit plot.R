##########################################
#########  ODP GLM on the annual claims triangle
#########  over-dispersed Poisson GLM, England & Verrall (1999, 2002)
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
tri <- incr2cum(as.triangle(sets$upper))      # cumulative observed triangle
latest <- as.numeric(getLatestCumulative(tri))

##########################################
#########  ODP GLM
##########################################

## incremental payments ~ quasi-Poisson, log link, factor(origin) + factor(dev);
## standard errors by the formula and by the bootstrap (glmReserve defaults)
odp <- glmReserve(tri)
# the bootstrap's tweedie::rtweedie() warns "non-integer x" in an unused check;
# its draws, phi * rpois(mu / phi), are correct
odp_boot <- suppressWarnings(glmReserve(tri, mse.method = "bootstrap"))

## the ODP GLM reserves are the chain-ladder reserves
round(c(ODP = odp$summary["total", "IBNR"],
        CL = sum(predict(chainladder(tri))[, n] - latest)))

## reserves and back-test against the true reserves, to output/tables;
## glmReserve's summary leaves out accident year 1 (no reserve)
odp_reserves <- function(fit, name) {
  s <- fit$summary[as.character(1:n), ]
  res <- reserves_table(latest,
                        ibnr = ifelse(is.na(s$IBNR), 0, s$IBNR),
                        se = ifelse(is.na(s$S.E), 0, s$S.E),
                        true = rowSums(sets$test, na.rm = TRUE))
  total <- reserves_total(res,
                          ibnr = fit$summary["total", "IBNR"],
                          se = fit$summary["total", "S.E"],
                          tail = sum(sets$tail))
  save_reserves(res, total, name)
  total
}
total <- odp_reserves(odp, "odp_raw")
total_boot <- odp_reserves(odp_boot, "odp_boot_raw")
round(rbind(formula = total, bootstrap = total_boot))
fwrite(data.frame(total = rowSums(odp_boot$sims.reserve.pred)),
       file.path(paths$tables, "odp_boot_raw_simulations.csv"))

##########################################
#########  figures
##########################################

## plot.glmReserve: which = 2 the completed triangle, 3 the bootstrap reserves,
## 4 the residuals against the fitted values
save_plot("GLM ODP fit.png", plot(odp, which = 2))
save_plot("GLM ODP fit lattice.png", plot(odp, which = 2, lattice = TRUE))
save_plot("GLM ODP residuals.png", plot(odp, which = 4))
save_plot("GLM ODP bootstrap reserves.png", plot(odp_boot, which = 3),
          width = 1200, height = 700)
