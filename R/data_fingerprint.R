##########################################
#########  Fingerprint of the simulated claims of a data set
#########  own design, not in the papers: analysis/00_claim-simulation/
#########  data fingerprint.R
##########################################

## rows of a fingerprint: table, key, type and the value as text with 15
## significant digits; type count: compared exactly, value: compared to a
## tolerance, info: not compared (the md5 sums of the files)
fingerprint_rows <- function(table, key, value, type = "value") {
  data.frame(table = table,
             key = as.character(key),
             type = type,
             value = if (is.numeric(value)) sprintf("%.15g", value) else value)
}

## the rows of the fingerprints new and old that differ: a key in one of them
## only, a count that is not the same, a value further apart than tolerance
## (relative difference; absolute for values below 1). No rows: the data are
## the same
fingerprint_diff <- function(new, old, tolerance = 1e-9) {
  both <- merge(new[new$type != "info", ],
                old[old$type != "info", ],
                by = c("table", "key", "type"),
                all = TRUE,
                suffixes = c("_new", "_old"),
                sort = FALSE)
  x <- as.numeric(both$value_new)
  y <- as.numeric(both$value_old)
  limit <- ifelse(both$type == "count", 0, tolerance * pmax(abs(y), 1))
  both[which(is.na(x) | is.na(y) | abs(x - y) > limit), ]
}
