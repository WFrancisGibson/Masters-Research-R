##########################################
#########  Reserves, back-test against the true reserves and
#########  prediction uncertainty (RMSEP)
##########################################

## reserves by accident period
## true = true outstanding payments (simulated data)
reserves_table <- function(latest, ibnr, se, true) {
  ultimate <- latest + ibnr
  data.frame(origin = seq_along(latest),
             latest = latest,
             dev_to_date = latest / ultimate,
             ultimate = ultimate,
             ibnr = ibnr,
             se = se,
             cv = ifelse(ibnr > 0, se / ibnr, NA),
             true = true,
             bias = ibnr - true)
}

## total over the accident periods
## the total standard error comes from the model and
## tail = the payments after the last development period
## (in no triangle and no model)
reserves_total <- function(res, ibnr, se, tail) {
  latest <- sum(res$latest)
  true <- sum(res$true)
  c(latest = latest,
    ultimate = latest + ibnr,
    ibnr = ibnr,
    se = se,
    cv = se / ibnr,
    true = true,
    bias = ibnr - true,
    tail = tail)
}

## write both tables to output/tables
save_reserves <- function(res, total, name) {
  fwrite(res, file.path(paths$tables, paste0(name, "_by_origin.csv")))
  fwrite(as.list(total), file.path(paths$tables, paste0(name, "_total.csv")))
}

## RMSEP (Paper C eqs. (6), (15)-(16); England & Verrall 1999 Section 4):
## process variance phi * reserve plus 'factor' times the variance of the
## bootstrap reserves boot (nsim x n), by accident period with a reserve and
## in total (row sums); mc_se: Monte Carlo standard error of the RMSEP
rmsep_table <- function(method, phi, reserve, boot, factor = 1) {
  keep <- reserve > 0
  boot <- unname(cbind(boot[, keep], rowSums(boot)))
  reserve <- unname(c(reserve[keep], sum(reserve)))
  est_var <- factor * apply(boot, 2, var)
  # standard error of the sample variance, by the delta method to the RMSEP
  dev <- sweep(boot, 2, colMeans(boot))
  var_se <- factor * sqrt((colMeans(dev^4) - colMeans(dev^2)^2) / nrow(boot))
  rmsep <- sqrt(phi * reserve + est_var)
  data.frame(method = method,
             origin = c(which(unname(keep)), "total"),
             phi = phi,
             reserve = reserve,
             boot_mean = colMeans(boot),
             process_sd = sqrt(phi * reserve),
             estimation_sd = sqrt(est_var),
             rmsep = rmsep,
             mc_se = var_se / (2 * rmsep))
}
