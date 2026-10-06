##########################################
#########  Description of a simulated claims portfolio and its covariates
#########  SynthETIC: Avanzi, Taylor, Wang & Wong (2021); description after
#########  Gabrielli & Wuthrich (2018), Risks 6(2):29, Section 3
##########################################

## claims and payments of analysis/00_claim-simulation/short_tailed_claims.R
## at the valuation date (end of year n); per claim: ultimate = all its
## payments (nominal), paid = those up to year n, outstanding = those after,
## lag_paid = sum of payment x years since the occurrence, rep_delay = years
## to the notification (0 = accident year) and the status at the valuation
## date; per payment: dev = development year 1, 2, ...
synthetic_portfolio <- function(dir, n) {
  claims <- fread(file.path(dir, "claims.csv"))
  trans <- fread(file.path(dir, "transactions.csv"),
                 select = c("claim_no", "occurrence_period", "occurrence_time",
                            "payment_time", "payment_period", "payment_size",
                            "payment_inflated"))
  # levels in the order of the design (Injury Severity is read as a number)
  factors <- readRDS(file.path(dir, "covariates_5factor.rds"))$factors
  for (v in names(factors)) {
    claims[[v]] <- factor(claims[[v]], levels = factors[[v]])
  }
  trans$dev <- trans$payment_period - trans$occurrence_period + 1
  trans$paid <- ifelse(trans$payment_period <= n, trans$payment_inflated, 0)
  trans$lag_paid <- trans$payment_inflated *
    (trans$payment_time - trans$occurrence_time)
  pay <- trans[, .(ultimate = sum(payment_inflated),
                   paid = sum(paid),
                   lag_paid = sum(lag_paid)),
               keyby = claim_no]
  claims <- merge(claims, pay, by = "claim_no")
  claims$outstanding <- claims$ultimate - claims$paid
  noti <- claims$occurrence_time + claims$notidel
  claims$rep_delay <- ceiling(noti) - claims$occurrence_period
  claims$status <- factor(ifelse(noti > n,
                                 "unreported",
                                 ifelse(noti + claims$setldel > n,
                                        "open",
                                        "closed")),
                          levels = c("closed", "open", "unreported"))
  list(claims = claims, trans = trans, features = names(factors))
}

## SynthETIC's relativity of a level combination (covariates_relativity): the
## product of the relativities of all factor pairs i <= j, the pairs i = j
## being the levels' own relativities; combos: one column per factor;
## rel: columns factor_i, factor_j, level_ik, level_jl, relativity
combo_relativity <- function(combos, rel) {
  out <- rep(1, nrow(combos))
  pairs <- unique(paste(rel$factor_i, rel$factor_j, sep = "|"))
  for (p in pairs) {
    r <- rel[which(paste(rel$factor_i, rel$factor_j, sep = "|") == p), ]
    key <- paste(combos[[r$factor_i[1]]], combos[[r$factor_j[1]]])
    out <- out * r$relativity[match(key, paste(r$level_ik, r$level_jl))]
  }
  out
}

## volume-weighted chain-ladder factors f_1, ..., f_{n-1} (Mack 1993) on the
## observed part (i + j <= n + 1) of a full cumulative n x n triangle
cl_factors <- function(cum) {
  n <- nrow(cum)
  sapply(1:(n - 1), function(j) {
    sum(cum[1:(n - j), j + 1]) / sum(cum[1:(n - j), j])
  })
}

## Cramer's V of two categorical variables: sqrt(chi2 / (N (min(r, c) - 1)))
## with Pearson's chi2 of their table of counts; 0 = independent, 1 = one
## determines the other
cramers_v <- function(a, b) {
  tab <- table(a, b)
  expected <- outer(rowSums(tab), colSums(tab)) / sum(tab)
  chi2 <- sum((tab - expected)^2 / expected)
  sqrt(chi2 / (sum(tab) * (min(dim(tab)) - 1)))
}

## Gini coefficient of the positive amounts x (0 = all equal)
gini <- function(x) {
  x <- sort(x)
  n <- length(x)
  2 * sum(seq_len(n) * x) / (n * sum(x)) - (n + 1) / n
}

## all-else-equal effect of every level against its reference level ref:
## exp(coefficient) and 95% interval of the linear model of log(y) on the
## factors of x; the simulator multiplies the effects of the factors, so
## this is its own structure (but for the designed interactions)
log_linear_effects <- function(y, x, ref) {
  d <- data.frame(lapply(seq_along(x), function(k) relevel(x[[k]], ref[k])))
  names(d) <- paste0("f", seq_along(x), "_")
  d$log_y <- log(y)
  coefs <- summary(lm(log_y ~ ., data = d))$coefficients
  rbindlist(lapply(seq_along(x), function(k) {
    lev <- levels(d[[k]])[-1]
    b <- coefs[paste0(names(d)[k], lev), , drop = FALSE]
    data.table(feature = names(x)[k],
               level = lev,
               estimate = exp(b[, 1]),
               lower = exp(b[, 1] - qnorm(0.975) * b[, 2]),
               upper = exp(b[, 1] + qnorm(0.975) * b[, 2]))
  }))
}

## share of the variance of y explained by the factors of x: per factor
## one-way (R2 of the factor alone) and drop-one (R2 of the additive model of
## all factors less R2 without the factor); additive = all factors,
## saturated = one mean per level combination
r2_features <- function(y, x) {
  x <- data.frame(x, check.names = FALSE)
  tss <- sum((y - mean(y))^2)
  r2 <- function(cols) {
    fit <- lm.fit(model.matrix(~ ., x[, cols, drop = FALSE]), y)
    1 - sum(fit$residuals^2) / tss
  }
  cols <- seq_along(x)
  additive <- r2(cols)
  combo <- interaction(x, drop = TRUE)
  data.frame(term = c(names(x), "additive", "saturated"),
             one_way = c(sapply(cols, r2), NA, NA),
             drop_one = c(sapply(cols, function(k) additive - r2(cols[-k])),
                          NA,
                          NA),
             r2 = c(rep(NA, length(cols)),
                    additive,
                    1 - sum((y - ave(y, combo))^2) / tss))
}
