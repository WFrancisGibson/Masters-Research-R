##########################################
#########  bCCNN: refits of the parametric bootstrap
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Section 3.3.4,
#########  eqs. (15) and (16)
##########################################

## the network of "bCCNN fit.R" (run it first; the same variant
## <validation>_<final_fit>) refitted on bootstrap triangles; the RMSEP
## tables and figures are in "bCCNN bootstrap analysis.R"
source(here::here("analysis", "00_setup.R"))
library(keras3)

train_cfg <- cfg$bccnn$training
final_fit <- if (train_cfg$validation == "claims_split") "refit" else
  train_cfg$final_fit
variant <- paste(train_cfg$validation, final_fit, sep = "_")
nsim <- cfg$bccnn$bootstrap$nsim
n_chunks <- cfg$bccnn$bootstrap$chunks

## the final network: its means, the cells it was trained on, its steps and
## hyper-parameters, and its dispersion under the headline phi (config.yml
## odp$phi)
fit <- readRDS(file.path(paths$processed,
                         paste0("bccnn_fit_", variant, ".rds")))
phi_nn <- fit$phi_bccnn[[cfg$odp$phi]]

##########################################
#########  bootstrap triangles
##########################################

## triangles from Paper C eq. (1) with the bCCNN means and phi_bCCNN on the
## cells the final network was trained on; all drawn before the first refit:
## the refits clear the Keras session and set_random_seed() also resets R's
## seed
set.seed(cfg$seed)
y_boot <- replicate(nsim,
                    odp_sample(fit$mu_bccnn, phi_nn, fit$cells),
                    simplify = FALSE)

##########################################
#########  refits
##########################################

## each triangle refitted as the final network, refit k with the seed
## seed + k; the refits are saved in n_chunks files: a saved chunk is not
## refitted and several R sessions share the chunks (R/runs.R); key: the
## network and settings a chunk belongs to
key <- list(mu = fit$mu_bccnn,
            phi = phi_nn,
            epochs = fit$epochs,
            param = fit$param,
            nsim = nsim,
            chunks = n_chunks)
chunks <- split(seq_len(nsim), ceiling(n_chunks * seq_len(nsim) / nsim))
chunk_files <- file.path(paths$processed,
                         paste0("bccnn_bootstrap_", variant, "_c",
                                seq_along(chunks), ".rds"))

## saved chunks of another network or other settings (after "bCCNN fit.R"
## was refitted with other numbers) are kept: delete the files printed here
## to bootstrap this network
stale <- Filter(function(f) !identical(readRDS(f)$key, key),
                chunk_files[file.exists(chunk_files)])
basename(stale)
stopifnot("saved chunks of another network" = length(stale) == 0)

for (k in seq_along(chunks)) {
  if (!claim_run(chunk_files[k])) next
  boot <- bccnn_bootstrap(y_boot,
                          chunks[[k]],
                          fit$cells,
                          fit$epochs,
                          fit$param)
  # reserves by accident period (refits x n), in units of cfg$data$scale,
  # and the seconds of each refit: time by the clock (the first refit of an
  # R session also starts Python), time_fit of its Keras fit
  save_run(list(key = key,
                refits = chunks[[k]],
                reserves = boot$reserves,
                time = boot$time,
                time_fit = boot$time_fit,
                info = run_info()),
           chunk_files[k])
  cat(format(Sys.time(), "%H:%M"), "bCCNN bootstrap", variant, "chunk", k,
      "of", length(chunks), "\n")
}
