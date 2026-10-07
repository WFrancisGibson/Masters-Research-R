##########################################
#########  bCCNN: prediction uncertainty by the parametric bootstrap
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Sections 2.3 and
#########  3.3.4, eqs. (6), (15) and (16)
##########################################

## reads the network of "bCCNN fit.R" and all its refits of
## "bCCNN bootstrap fit.R" (the same variant <validation>_<final_fit>; no
## Keras needed)
source(here::here("analysis", "00_setup.R"))

n <- cfg$data$n_dev
scale <- cfg$data$scale            # tables in units of scale
phi_method <- cfg$odp$phi          # dispersion estimate: deviance or pearson
train_cfg <- cfg$bccnn$training
final_fit <- if (train_cfg$validation == "claims_split") "refit" else
  train_cfg$final_fit
variant <- paste(train_cfg$validation, final_fit, sep = "_")
tab_dir <- file.path(paths$tables, "03_bCCNN")
fig_dir <- file.path(paths$figures, "03_bCCNN", variant)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
nsim <- cfg$odp$nsim
nsim_nn <- cfg$bccnn$bootstrap$nsim
n_chunks <- cfg$bccnn$bootstrap$chunks

##########################################
#########  ccODP and bCCNN on the observed triangle
##########################################

## the ccODP as in "bCCNN fit.R", in units of scale; the bCCNN from its fit:
## reserves by accident period and dispersions (Paper C Section 3.3.2 for
## (5); for Pearson's phi by analogy)
sets <- readRDS(file.path(paths$interim, "triangles.rds"))
odp <- ccodp_fit(sets$upper / scale, phi_method = phi_method)
fit <- readRDS(file.path(paths$processed,
                         paste0("bccnn_fit_", variant, ".rds")))
by_origin <- fit$by_origin
tot <- colSums(by_origin[, -1])
phi_odp <- fit$phi_ccodp
phi_bccnn <- fit$phi_bccnn
phi_nn <- phi_bccnn[[phi_method]]

##########################################
#########  bootstrap reserves and RMSEP
##########################################

## ccODP (Section 2.3) under both dispersions: the Paper C rows of the ODP
## GLM script
rmsep <- NULL
boot_totals <- NULL
for (k in names(phi_odp)) {
  set.seed(cfg$seed)
  boot <- ccodp_bootstrap(odp, phi_odp[[k]], nsim)
  method <- paste("ccODP, phi", k)
  rmsep <- rbind(rmsep,
                 rmsep_table(method, phi_odp[[k]], odp$reserve_o, boot))
  boot_totals <- rbind(boot_totals,
                       data.frame(method = method, total = rowSums(boot)))
}

## bCCNN (Section 3.3.4) under the headline phi: the refits of all chunks,
## which belong to this network and these settings (key, as in "bCCNN
## bootstrap fit.R"); chunks of another network: delete them and run the
## bootstrap fit again
if (nsim_nn > 0) {
  key <- list(mu = fit$mu_bccnn,
              phi = phi_nn,
              epochs = fit$epochs,
              param = fit$param,
              nsim = nsim_nn,
              chunks = n_chunks)
  boot_nn <- lapply(seq_len(n_chunks), function(k) {
    readRDS(file.path(paths$processed,
                      paste0("bccnn_bootstrap_", variant, "_c", k, ".rds")))
  })
  stopifnot("chunks of another network or other settings" =
              sapply(boot_nn, function(x) identical(x$key, key)))
  reserves_nn <- do.call(rbind, lapply(boot_nn, `[[`, "reserves"))
  stopifnot(nrow(reserves_nn) == nsim_nn, all(is.finite(reserves_nn)))
  method <- paste("bCCNN, phi", phi_method)
  rmsep <- rbind(rmsep,
                 rmsep_table(method, phi_nn, by_origin$bCCNN, reserves_nn))
  boot_totals <- rbind(boot_totals,
                       data.frame(method = method,
                                  total = rowSums(reserves_nn)))
  ## seconds of the refits: by the clock (the first one of an R session also
  ## starts Python) and of their Keras fits
  time_nn <- unlist(lapply(boot_nn, `[[`, "time"))
  time_fit_nn <- unlist(lapply(boot_nn, `[[`, "time_fit"))
  print(round(c("refits" = nsim_nn,
                "seconds per refit (median)" = median(time_nn),
                "hours of all refits" = sum(time_nn) / 3600,
                "seconds per Keras fit (median)" = median(time_fit_nn),
                "hours of all Keras fits" = sum(time_fit_nn) / 3600), 2))
}
rownames(rmsep) <- NULL

## totals (Paper C Table 5): RMSEP and coefficient of variation of the
## ccODP (CL) and bCCNN reserves, and their bias against the true reserves
rmsep_total <- rmsep[rmsep$origin == "total", -2]
rmsep_total$cv <- rmsep_total$rmsep / rmsep_total$reserve
rmsep_total$true <- tot[["true"]]
rmsep_total$bias <- rmsep_total$reserve - rmsep_total$true
rownames(rmsep_total) <- NULL
cbind(rmsep_total[1], round(rmsep_total[-1], 3))

## dispersion of the ccODP and bCCNN by Pearson's statistic and by Paper C
## eq. (5), with the process error sqrt(phi * reserve) (16) and the
## bootstrap RMSEP (none for the bCCNN under the other phi)
dispersion <- data.frame(model = rep(c("ccODP", "bCCNN"), each = 2),
                         phi_estimate = names(c(phi_odp, phi_bccnn)),
                         phi = unname(c(phi_odp, phi_bccnn)),
                         reserve = rep(c(tot[["CL"]], tot[["bCCNN"]]),
                                       each = 2))
dispersion$process_sd <- sqrt(dispersion$phi * dispersion$reserve)
dispersion$rmsep <- rmsep_total$rmsep[match(paste0(dispersion$model,
                                                   ", phi ",
                                                   dispersion$phi_estimate),
                                            rmsep_total$method)]
dispersion

## write the tables to output/tables
tables <- list(rmsep_total = rmsep_total,
               rmsep_by_origin = rmsep,
               dispersion = dispersion,
               bootstrap_totals = boot_totals)
for (k in names(tables)) {
  fwrite(tables[[k]],
         file.path(tab_dir, paste0("bccnn_", variant, "_", k, ".csv")))
}

##########################################
#########  figures
##########################################

unit <- format(scale, big.mark = ",", scientific = FALSE)

## RMSEP by accident period (log scale) against the biases of the ccODP (CL)
## and bCCNN reserves
bias <- data.frame(label = rep(c("|CL reserve - true reserve|",
                                 "|bCCNN reserve - true reserve|"),
                               each = n),
                   origin = rep(1:n, 2),
                   bias = c(by_origin$bias_CL, by_origin$bias_bCCNN))
ggsave("bCCNN RMSEP by accident year.png",
       rmsep_plot(rmsep,
                  bias,
                  paste0("ccODP and bCCNN: bootstrap RMSEP by accident year ",
                         "(units of ", unit, ")")),
       path = fig_dir, width = 8, height = 6, dpi = 150)

## bootstrap distributions of the ccODP and bCCNN reserves (headline phi)
head_method <- paste(c("ccODP, phi", "bCCNN, phi"), phi_method)
ggsave("bCCNN bootstrap densities.png",
       boot_density_plot(boot_totals[boot_totals$method %in% head_method, ],
                         c("CL reserve" = tot[["CL"]],
                           "bCCNN reserve" = tot[["bCCNN"]],
                           "true reserve" = tot[["true"]]),
                         paste0("Bootstrap reserves (units of ", unit, ")")),
       path = fig_dir, width = 8, height = 5, dpi = 150)

## Pearson's phi against Paper C's (5): dispersion, process error and
## bootstrap RMSEP of both models
quantity <- c("dispersion phi",
              "process error sqrt(phi * reserve)",
              "RMSEP (bootstrap)")
phi_label <- c(pearson = "Pearson", deviance = "Paper C eq. (5)")
d <- data.frame(model = factor(rep(dispersion$model, 3),
                               levels = c("ccODP", "bCCNN")),
                phi_estimate = rep(phi_label[dispersion$phi_estimate], 3),
                quantity = factor(rep(quantity, each = 4), levels = quantity),
                value = c(dispersion$phi,
                          dispersion$process_sd,
                          dispersion$rmsep))
ggsave("bCCNN dispersion comparison.png",
       ggplot(d[!is.na(d$value), ],
              aes(x = model, y = value, colour = phi_estimate)) +
         geom_point(position = position_dodge(width = 0.4), size = 2) +
         facet_wrap(~quantity, scales = "free_y") +
         labs(x = NULL,
              y = NULL,
              colour = "phi estimate",
              title = paste0("Pearson's phi versus Paper C eq. (5) (units of ",
                             unit, ")")) +
         theme_bw() + theme(legend.position = "top"),
       path = fig_dir, width = 8, height = 4, dpi = 150)
