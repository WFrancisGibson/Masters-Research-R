##########################################
#########  ODP GLM on the annual claims triangle
#########  over-dispersed Poisson GLM, England & Verrall (1999, 2002);
#########  dispersion and parametric bootstrap: Paper C (Gabrielli, Richman
#########  & Wuthrich 2020) eq. (5) and Section 2.3
##########################################

source(here::here("analysis", "00_setup.R"))
tab_dir <- file.path(paths$tables, "02_ODP-glm")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

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
## standard errors by the formula and by the bootstrap (cfg$odp$nsim samples)
odp <- glmReserve(tri)
# the bootstrap's tweedie::rtweedie() warns "non-integer x" in an unused check;
# its draws, phi * rpois(mu / phi), are correct
odp_boot <- suppressWarnings(glmReserve(tri,
                                        mse.method = "bootstrap",
                                        nsim = cfg$odp$nsim))

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
  save_reserves(res, total, name, tab_dir)
  total
}
total <- odp_reserves(odp, "odp_raw")
total_boot <- odp_reserves(odp_boot, "odp_boot_raw")
round(rbind(formula = total, bootstrap = total_boot))
fwrite(data.frame(total = rowSums(odp_boot$sims.reserve.pred)),
       file.path(tab_dir, "odp_boot_raw_simulations.csv"))

##########################################
#########  dispersion: Pearson (glmReserve) and Paper C eq. (5)
##########################################

## the ccODP of Paper C eq. (3) is glmReserve's GLM; in units of scale
scale <- cfg$data$scale
ccodp <- ccodp_fit(sets$upper / scale)
phi <- c(pearson = ccodp$phi_pearson, deviance = ccodp$phi_deviance)

## glmReserve's phi: Pearson's statistic over |D_I| - (I + J) degrees of
## freedom; its glm stops earlier (epsilon 1e-8, 6e-8 apart)
phi_glm <- with(odp$model, sum(weights * residuals^2) / df.residual) / scale
stopifnot(isTRUE(all.equal(phi[["pearson"]], phi_glm, tolerance = 1e-6)))

## bootstraps of the Pearson residuals r: glmReserve multiplies them by
## sqrt(|D_I| / (|D_I| - (I + J))) and redraws a pseudo triangle until no
## cell is negative, England & Verrall (1999) keep them all; the cells are
## drawn independently, so a pseudo triangle has no negative cell with
## probability prod over the cells of P(factor * r >= -sqrt(mu))
cells <- ccodp$cells
mu <- ccodp$mu[cells]
r <- (ccodp$y[cells] - mu) / sqrt(mu)
boot_factor <- sqrt(sum(cells) / ccodp$df)
p_glm <- prod(sapply(sqrt(mu), function(s) mean(boot_factor * r >= -s)))
p_ev <- prod(sapply(sqrt(mu), function(s) mean(r >= -s)))
dispersion <- c(
  "observed cells |D_I|" = sum(cells),
  "parameters I + J" = sum(cells) - ccodp$df,
  "degrees of freedom |D_I| - (I + J)" = ccodp$df,
  "Pearson statistic" = sum(r^2),
  "Poisson deviance (unscaled)" = ccodp$deviance,
  "phi Pearson (glmReserve, E&V 1999)" = phi[["pearson"]],
  "phi deviance (Paper C eq. (5))" = phi[["deviance"]],
  "phi deviance / phi Pearson" = phi[["deviance"]] / phi[["pearson"]],
  "glmReserve residual factor sqrt(|D_I| / (|D_I| - (I + J)))" = boot_factor,
  "glmReserve pseudo triangles kept (%)" = 100 * p_glm,
  "glmReserve draws per bootstrap sample" = 1 / p_glm,
  "E&V 1999 pseudo triangles with a negative cell (%)" = 100 * (1 - p_ev),
  "amounts in units of" = scale
)
dispersion <- data.frame(quantity = names(dispersion),
                         value = unname(dispersion))
cbind(dispersion[1],
      value = format(dispersion$value,
                     digits = 4,
                     scientific = FALSE,
                     drop0trailing = TRUE))

##########################################
#########  prediction uncertainty: RMSEP
#########  Paper C eq. (6); England & Verrall (1999) Section 4
##########################################

## RMSEP^2 = process variance phi * reserve + estimation error, by accident
## period and in total, in units of scale; reserve = the CL reserves
reserve <- ccodp$reserve_o
true_o <- rowSums(sets$test, na.rm = TRUE) / scale
nsim <- cfg$odp$nsim

## analytic (glmReserve's formula): both terms are linear in phi, so under
## phi_k its S.E. times sqrt(phi_k / phi_glm)
se <- odp$summary[c(as.character(2:n), "total"), "S.E"] / scale
res_tot <- c(reserve[-1], sum(reserve))
rmsep <- NULL
for (k in names(phi)) {
  ratio <- phi[[k]] / phi_glm
  rmsep <- rbind(rmsep,
                 data.frame(method = paste("analytic, phi", k),
                            origin = c(2:n, "total"),
                            phi = phi[[k]],
                            reserve = res_tot,
                            boot_mean = NA,
                            process_sd = sqrt(phi[[k]] * res_tot),
                            estimation_sd = sqrt(ratio *
                                                   (se^2 - phi_glm * res_tot)),
                            rmsep = se * sqrt(ratio),
                            mc_se = NA))
}

## glmReserve's bootstrap (the current method): its predictive draws hold the
## process error, so its S.E. is the RMSEP (phi = 0 below); estimation error:
## the refitted means, process error: mean of phi*_b * R*_b (law of total
## variance)
boot_glm <- rmsep_table("glmReserve bootstrap",
                        0,
                        reserve,
                        cbind(0, odp_boot$sims.reserve.pred) / scale)
b_mean <- odp_boot$sims.reserve.mean / scale
b_mean <- cbind(b_mean, rowSums(b_mean))
phi_b <- odp_boot$sims.par[, "phi"] / scale
boot_glm$phi <- mean(phi_b)
boot_glm$boot_mean <- colMeans(b_mean)
boot_glm$process_sd <- sqrt(colMeans(phi_b * b_mean))
boot_glm$estimation_sd <- apply(b_mean, 2, sd)
rmsep <- rbind(rmsep, boot_glm)

## England & Verrall (1999) Section 4: Pearson's phi and the bootstrap
## variance, without and with their factor |D_I| / (|D_I| - (I + J))
set.seed(cfg$seed)
boot_ev <- ev_bootstrap(ccodp, nsim)
rmsep <- rbind(rmsep,
               rmsep_table("E&V 1999", phi[["pearson"]], reserve, boot_ev),
               rmsep_table("E&V 1999 x n/(n-p)",
                           phi[["pearson"]],
                           reserve,
                           boot_ev,
                           factor = boot_factor^2))

## Paper C Section 2.3: parametric bootstrap from (1) with phi (5), and with
## Pearson's phi for comparison; no further factor (Paper C: it is in (5))
boot_pc <- list()
for (k in names(phi)) {
  set.seed(cfg$seed)
  boot_pc[[k]] <- ccodp_bootstrap(ccodp, phi[[k]], nsim)
  rmsep <- rbind(rmsep,
                 rmsep_table(paste("Paper C, phi", k),
                             phi[[k]],
                             reserve,
                             boot_pc[[k]]))
}
rownames(rmsep) <- NULL

## totals (Paper C Table 2): RMSEP, coefficient of variation and the bias of
## the CL reserves against the true reserves
rmsep_total <- rmsep[rmsep$origin == "total", -2]
rmsep_total$cv <- rmsep_total$rmsep / rmsep_total$reserve
rmsep_total$true <- sum(true_o)
rmsep_total$bias <- rmsep_total$reserve - rmsep_total$true
rownames(rmsep_total) <- NULL
cbind(rmsep_total[1], round(rmsep_total[-1], 3))

## RMSEP by accident period (rows) and method (columns)
methods <- unique(rmsep$method)
round(matrix(rmsep$rmsep,
             ncol = length(methods),
             dimnames = list(origin = c(2:n, "total"), method = methods)),
      2)

## bootstrap totals of the estimated CL reserves (estimation error only)
boot_totals <- data.frame(
  method = rep(c("glmReserve (refitted means)", "E&V 1999",
                 "Paper C, phi pearson", "Paper C, phi deviance"),
               each = nsim),
  total = c(rowSums(odp_boot$sims.reserve.mean) / scale,
            rowSums(boot_ev),
            rowSums(boot_pc$pearson),
            rowSums(boot_pc$deviance))
)

## write the tables to output/tables
tables <- list(dispersion = dispersion,
               rmsep_by_origin = rmsep,
               rmsep_total = rmsep_total,
               bootstrap_totals = boot_totals)
for (k in names(tables)) {
  fwrite(tables[[k]], file.path(tab_dir, paste0("odp_", k, ".csv")))
}

##########################################
#########  figures
##########################################

fig_dir <- file.path(paths$figures, "02_ODP-glm")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

## plot.glmReserve: which = 2 the completed triangle, 3 the bootstrap reserves,
## 4 the residuals against the fitted values
save_plot("GLM ODP fit.png", plot(odp, which = 2), dir = fig_dir)
save_plot("GLM ODP fit lattice.png",
          plot(odp, which = 2, lattice = TRUE),
          dir = fig_dir)
save_plot("GLM ODP residuals.png", plot(odp, which = 4), dir = fig_dir)
save_plot("GLM ODP bootstrap reserves.png", plot(odp_boot, which = 3),
          dir = fig_dir, width = 1200, height = 700)

## RMSEP of the methods by accident period (log scale) against the bias of
## the CL reserves
unit <- format(scale, big.mark = ",", scientific = FALSE)
bias <- data.frame(label = "|CL reserve - true reserve|",
                   origin = 1:n,
                   bias = reserve - true_o)
ggsave("GLM ODP RMSEP by accident year.png",
       rmsep_plot(rmsep,
                  bias,
                  paste0("ODP GLM: RMSEP by accident year (units of ",
                         unit, ")")),
       path = fig_dir, width = 8, height = 6, dpi = 150)

## RMSEP relative to Paper C's parametric bootstrap with phi (5); every
## method has the same accident periods in the same order
ref <- rmsep$rmsep[rmsep$method == "Paper C, phi deviance"]
rel <- data.frame(method = factor(rmsep$method, levels = methods),
                  origin = rmsep$origin,
                  ratio = rmsep$rmsep / ref)
rel <- rel[rel$origin != "total", ]
rel$origin <- as.integer(rel$origin)
ggsave("GLM ODP RMSEP relative to Paper C.png",
       ggplot(rel, aes(x = origin, y = ratio, colour = method)) +
         geom_hline(yintercept = 1, linetype = "dotted") +
         geom_line() +
         geom_point(size = 0.8) +
         scale_x_continuous(breaks = 2:n) +
         guides(colour = guide_legend(ncol = 2)) +
         labs(x = "accident period",
              y = "RMSEP / RMSEP of Paper C, phi deviance",
              colour = NULL,
              title = "ODP GLM: RMSEP relative to Paper C Section 2.3") +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 8, height = 6, dpi = 150)

## bootstrap distributions of the estimated CL reserve
ggsave("GLM ODP bootstrap densities.png",
       boot_density_plot(boot_totals,
                         c("CL reserve" = sum(reserve),
                           "true reserve" = sum(true_o)),
                         paste0("Bootstrap CL reserves (units of ", unit,
                                ")")),
       path = fig_dir, width = 8, height = 5, dpi = 150)
