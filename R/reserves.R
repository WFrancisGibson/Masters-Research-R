##########################################
#########  Reserves and back-test against the true reserves
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
