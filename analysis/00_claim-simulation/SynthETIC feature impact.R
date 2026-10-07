##########################################
#########  The SynthETIC claims portfolio: the covariates and their impact
#########  covariates of SynthETIC (Avanzi, Taylor, Wang & Wong 2021) as
#########  designed in "SynthETIC claims simulation.R";
#########  figures after Wuthrich (2018), EAJ 8:407-436, Figures 5-6
##########################################

source(here::here("analysis", "00_setup.R"))
stopifnot(cfg$data$generator == "synthetic")
tab_dir <- file.path(paths$tables, "00_claim-simulation/feature-impact")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

n <- cfg$data$n_dev          # 20 accident years; valuation: end of year n
units <- cfg$data$scale      # amounts in millions
ref_claim <- 200000          # SynthETIC's claim size scale (simulation script)
## reference level of every feature (delay multipliers 1)
ref <- c("Y", "2", "30-50", "Passenger", "N")

##########################################
#########  load data
##########################################

## claims and payments of "SynthETIC claims simulation.R" and the design of
## the covariates; all effects are measured on the full simulation ('true'),
## not on the claims known at the valuation date
data_dir <- file.path(paths$raw, cfg$data$dir)
port <- synthetic_portfolio(data_dir, n)
claims <- port$claims
trans <- port$trans
features <- port$features
names(ref) <- features
claims$AY <- claims$occurrence_period
freq_rel <- fread(file.path(data_dir, "covariates_freq_relativities.csv"))
sev_rel <- fread(file.path(data_dir, "covariates_sev_relativities.csv"))
delay_mult <- fread(file.path(data_dir, "delay_multipliers.csv"))
delay_mult$rationale <- gsub("\\s+", " ", delay_mult$rationale)
x <- claims[, features, with = FALSE]          # the five features

## designed mean number of payments given the claim size (simulation script,
## Module 5): 1 or 2, 2 or 3, and 4 + geometric above 0.075 ref_claim
bands <- c(0.0375, 0.075) * ref_claim
claims$np_design <- ifelse(claims$claim_size <= bands[1],
                           1.5,
                           ifelse(claims$claim_size <= bands[2],
                                  8 / 3,
                                  pmin(8, 4 + log(claims$claim_size /
                                                    bands[2]))))
claims$lag <- claims$lag_paid / claims$ultimate  # amount-weighted, in years

##########################################
#########  the design
##########################################

## the 480 level combinations: SynthETIC draws the combination of a claim
## with probability p proportional to the product of the frequency
## relativities and multiplies its size by the product r of the severity
## relativities, rescaled to the same total claim cost
grid <- expand.grid(lapply(x, levels))
grid$p <- combo_relativity(grid, freq_rel)
grid$p <- grid$p / sum(grid$p)
grid$sev <- combo_relativity(grid, sev_rel)
claims$sev_design <- combo_relativity(claims, sev_rel)
rescale <- sum(claims$claim_size_raw) /
  sum(claims$claim_size_raw * claims$sev_design)
stopifnot(max(abs(claims$claim_size / (claims$claim_size_raw *
                                         claims$sev_design * rescale) -
                    1)) < 1e-9)
round(c("rescaling constant" = rescale,
        "combinations with p > 0" = sum(grid$p > 0)), 4)

## design by level: probability (summed over the combinations), the level's
## own frequency and severity relativity, the severity relative to the
## reference level, and the delay multipliers
design <- rbindlist(lapply(features, function(v) {
  own_freq <- freq_rel[factor_i == v & factor_j == v]
  own_sev <- sev_rel[factor_i == v & factor_j == v]
  lev <- levels(x[[v]])
  data.table(feature = v,
             level = lev,
             design_prob = as.vector(tapply(grid$p, grid[[v]], sum)),
             freq_relativity = own_freq$relativity[match(lev,
                                                         own_freq$level_ik)],
             sev_relativity = own_sev$relativity[match(lev,
                                                       own_sev$level_ik)])
}))
design$reference <- design$level == ref[design$feature]
design$sev_vs_reference <- design$sev_relativity /
  design$sev_relativity[design$reference][match(design$feature, features)]
m <- match(paste(design$feature, design$level),
           paste(delay_mult$factor, delay_mult$level))
design$notidel_mult <- delay_mult$notidel_mult[m]
design$setldel_mult <- delay_mult$setldel_mult[m]
design$rationale <- delay_mult$rationale[m]
design[, !"rationale"]

## the relativities between two features that are not 1: frequency (Legal
## Representation N only with Injury Severity 1; Vehicle type with Business
## use) and severity (Injury Severity with Age of Claimant)
interactions <- rbind(
  cbind(relativity_of = "frequency",
        freq_rel[factor_i != factor_j & relativity != 1]),
  cbind(relativity_of = "severity",
        sev_rel[factor_i != factor_j & relativity != 1])
)
interactions

##########################################
#########  summaries by level
##########################################

## all one-way (marginal) summaries by level; a level's summary also holds
## the effects of the levels of the other features it occurs with; long: the
## claims once per feature, with the name of the feature and the claim's
## level (levels in the order of the design, as the rows of 'design')
cols <- c("AY", "claim_size", "notidel", "setldel", "notidel_mult",
          "setldel_mult", "no_payment", "np_design", "ultimate", "paid",
          "outstanding", "lag_paid", "lag", "rep_delay", "status")
long <- rbindlist(lapply(features, function(v) {
  data.table(feature = v,
             level = as.character(claims[[v]]),
             claims[, cols, with = FALSE])
}))
long$feature <- factor(long$feature, levels = features)
long$level <- factor(long$level, levels = unique(unlist(lapply(x, levels))))
q99 <- quantile(claims$claim_size, 0.99)
lev <- long[, .(n = .N,
                cost = sum(claim_size),
                mean_size = mean(claim_size),
                median_size = median(claim_size),
                geo_mean_size = exp(mean(log(claim_size))),
                q25_size = quantile(claim_size, 0.25),
                q75_size = quantile(claim_size, 0.75),
                q95_size = quantile(claim_size, 0.95),
                q99_size = quantile(claim_size, 0.99),
                cv_size = sd(claim_size) / mean(claim_size),
                top_1pct = sum(claim_size > q99),
                over_1m_pct = 100 * mean(claim_size > 1e6),
                mean_notidel = mean(notidel),
                median_notidel = median(notidel),
                mean_notidel_mult = mean(notidel_mult),
                same_year_pct = 100 * mean(rep_delay == 0),
                mean_setldel = mean(setldel),
                median_setldel = median(setldel),
                q90_setldel = quantile(setldel, 0.9),
                mean_setldel_mult = mean(setldel_mult),
                over_5y_pct = 100 * mean(setldel > 5),
                mean_no_payment = mean(no_payment),
                mean_np_design = mean(np_design),
                small_pct = 100 * mean(claim_size <= bands[1]),
                middle_pct = 100 * mean(claim_size > bands[1] &
                                          claim_size <= bands[2]),
                cap_pct = 100 * mean(np_design == 8),
                ultimate = sum(ultimate),
                paid = sum(paid),
                outstanding = sum(outstanding),
                lag = sum(lag_paid) / sum(ultimate),
                median_lag = median(lag),
                open = sum(status == "open"),
                unreported = sum(status == "unreported"),
                os_open = sum(outstanding[status == "open"]),
                os_unreported = sum(outstanding[status == "unreported"])),
            keyby = .(feature, level)]
key <- lev[, .(feature, level)]
## row of the reference level of each row's feature; the other levels (the
## rows of log_linear_effects() are in their order)
is_ref <- lev$level == ref[as.character(lev$feature)]
ref_row <- which(is_ref)[as.integer(lev$feature)]

##########################################
#########  tables: the portfolio mix
##########################################

## simulated against designed share of the claims; z: standardised
## difference
n_claims <- nrow(claims)
mix <- data.frame(key,
                  n = lev$n,
                  share_pct = 100 * lev$n / n_claims,
                  design_pct = 100 * design$design_prob,
                  z = (lev$n - n_claims * design$design_prob) /
                    sqrt(n_claims * design$design_prob *
                           (1 - design$design_prob)))
cbind(mix[, 1:3], round(mix[, 4:6], 3))

## the two pairs of dependent features: claims, simulated and designed joint
## share, and the share within the level of the first feature
pairs <- list(features[c(2, 1)], features[c(4, 5)])
dependent <- rbindlist(lapply(pairs, function(v) {
  obs <- claims[, .N, keyby = v]
  out <- merge(as.data.table(grid)[, .(design_prob = sum(p)), keyby = v],
               obs,
               all.x = TRUE)
  out$N[is.na(out$N)] <- 0
  data.table(pair = paste(v, collapse = " x "),
             level_1 = as.character(out[[1]]),
             level_2 = as.character(out[[2]]),
             n = out$N,
             share_pct = 100 * out$N / n_claims,
             design_pct = 100 * out$design_prob,
             within_level_1_pct = 100 * out$N / ave(out$N, out[[1]], FUN = sum))
}))
cbind(dependent[, 1:4], round(dependent[, 5:7], 3))

## association of the features with each other and with the accident year
vars <- c(features, "AY")
cramer <- sapply(vars, function(a) {
  sapply(vars, function(b) cramers_v(claims[[a]], claims[[b]]))
})
round(cramer, 4)

## the level combinations: how many are possible and occur, the fit of
## their numbers of claims to the design (chi-square on the possible ones),
## their concentration, the cells accident year x combination of the NN
## chain ladder, and the rescaling constant of the claim sizes
combos <- merge(as.data.table(grid),
                claims[, .(n = .N,
                           cost = sum(claim_size),
                           median_size = median(claim_size)),
                       by = features],
                by = features,
                all.x = TRUE)
combos$n[is.na(combos$n)] <- 0
combos$cost[is.na(combos$cost)] <- 0
possible <- combos$p > 0
expected <- n_claims * combos$p[possible]
chi2 <- sum((combos$n[possible] - expected)^2 / expected)
holding <- function(v, share) {
  sum(cumsum(sort(v, decreasing = TRUE)) < share * sum(v)) + 1
}
cells <- claims[, .N, by = c(features, "AY")]
coverage <- c(
  "level combinations" = nrow(grid),
  "with a positive designed probability" = sum(possible),
  "occurring" = sum(combos$n > 0),
  "possible but not occurring" = sum(possible & combos$n == 0),
  "largest expected number of claims of those not occurring" =
    max(n_claims * combos$p[possible & combos$n == 0]),
  "possible with an expected number of claims below 5" = sum(expected < 5),
  "chi-square of the simulated against the designed numbers" = chi2,
  "degrees of freedom" = sum(possible) - 1,
  "p-value (chi-square distribution)" =
    pchisq(chi2, sum(possible) - 1, lower.tail = FALSE),
  "occurring with fewer than 5 claims" = sum(combos$n > 0 & combos$n < 5),
  "occurring with fewer than 30 claims" = sum(combos$n > 0 & combos$n < 30),
  "occurring with fewer than 100 claims" =
    sum(combos$n > 0 & combos$n < 100),
  "combinations holding 50% of the claims" = holding(combos$n, 0.5),
  "combinations holding 90% of the claims" = holding(combos$n, 0.9),
  "combinations holding 99% of the claims" = holding(combos$n, 0.99),
  "combinations holding 50% of the claim cost" = holding(combos$cost, 0.5),
  "combinations holding 90% of the claim cost" = holding(combos$cost, 0.9),
  "combinations holding 99% of the claim cost" = holding(combos$cost, 0.99),
  "cells accident year x combination with claims" = nrow(cells),
  "median number of claims per cell" = median(cells$N),
  "cells with one claim" = sum(cells$N == 1),
  "rescaling constant of the severity relativities" = rescale
)
coverage <- data.frame(quantity = names(coverage), value = unname(coverage))
data.frame(quantity = coverage$quantity, value = round(coverage$value, 4))

## the ten combinations with the largest claim cost; the designed severity
## relative to the combination of the reference levels
ref_sev <- grid$sev[which(rowSums(sapply(features, function(v) {
  grid[[v]] == ref[v]
})) == length(features))]
top_combos <- combos[order(-cost)][1:10]
top_combos <- data.frame(top_combos[, features, with = FALSE],
                         n = top_combos$n,
                         claims_pct = 100 * top_combos$n / n_claims,
                         cost_pct = 100 * top_combos$cost / sum(combos$cost),
                         cum_cost_pct = 100 * cumsum(top_combos$cost) /
                           sum(combos$cost),
                         sev_vs_reference = top_combos$sev / ref_sev,
                         median_size = top_combos$median_size,
                         check.names = FALSE)
cbind(top_combos[, 1:6], round(top_combos[, 7:11], 2))

## mix by accident year: range of the level's share of the claims and of the
## nominal ultimate over the accident years; p-value of the chi-square test
## of level x accident year
by_ay <- long[, .(n = .N, ultimate = sum(ultimate)),
              keyby = .(feature, level, AY)]
by_ay$claims_pct <- 100 * by_ay$n /
  ave(by_ay$n, by_ay$feature, by_ay$AY, FUN = sum)
by_ay$ultimate_pct <- 100 * by_ay$ultimate /
  ave(by_ay$ultimate, by_ay$feature, by_ay$AY, FUN = sum)
stability <- by_ay[, .(min_n = min(n),
                       claims_pct_min = min(claims_pct),
                       claims_pct_mean = mean(claims_pct),
                       claims_pct_max = max(claims_pct),
                       ultimate_pct_min = min(ultimate_pct),
                       ultimate_pct_mean = mean(ultimate_pct),
                       ultimate_pct_max = max(ultimate_pct)),
                   keyby = .(feature, level)]
stability$chi2_p_value <- sapply(features, function(v) {
  chisq.test(table(claims[[v]], claims$AY))$p.value
})[as.integer(stability$feature)]
cbind(stability[, 1:3], round(stability[, 4:10], 3))

##########################################
#########  tables: claim size
##########################################

## claim size by level (one-way); cost_to_claims: share of the cost over
## share of the claims; se_mean_pct: standard error of the mean in %
size_level <- data.frame(key,
                         n = lev$n,
                         claims_pct = 100 * lev$n / n_claims,
                         cost_pct = 100 * lev$cost / sum(claims$claim_size),
                         cost_to_claims = lev$mean_size /
                           mean(claims$claim_size),
                         lev[, .(mean_size, median_size, geo_mean_size,
                                 q25_size, q75_size, q95_size, q99_size,
                                 cv_size)],
                         se_mean_pct = 100 * lev$cv_size / sqrt(lev$n))
cbind(size_level[, 1:3], round(size_level[, 4:15], 2))

## severity relativities against the reference level: designed, one-way
## (ratio of the means and of the geometric means) and all else equal
## (log-linear model on the five features, 95% interval)
sev_fit <- log_linear_effects(claims$claim_size, x, ref)
mean_ratio <- lev$mean_size / lev$mean_size[ref_row]
geo_ratio <- lev$geo_mean_size / lev$geo_mean_size[ref_row]
sev_effects <- data.frame(key[!is_ref],
                          design = design$sev_vs_reference[!is_ref],
                          ratio_of_means = mean_ratio[!is_ref],
                          ratio_of_geo_means = geo_ratio[!is_ref],
                          sev_fit[, .(estimate, lower, upper)])
cbind(sev_effects[, 1:2], round(sev_effects[, 3:8], 3))

## Injury Severity x Age of Claimant: claims and median claim size; the
## geometric mean of the cell over the fit of the two main effects, the same
## for the designed relativities of its claims (what the ratio would be
## without noise: the fit takes up part of the interaction), and the designed
## interaction
cell <- claims[, .(n = .N,
                   median_size = median(claim_size),
                   mean_log = mean(log(claim_size)),
                   mean_log_design = mean(log(sev_design))),
               keyby = .(injury = get(features[2]), age = get(features[3]))]
main_effects_ratio <- function(v) {
  exp(v - fitted(lm(v ~ injury + age, data = cell, weights = n)))
}
cell$ratio_to_main_effects <- main_effects_ratio(cell$mean_log)
cell$design_ratio <- main_effects_ratio(cell$mean_log_design)
inter <- sev_rel[factor_i == features[2] & factor_j == features[3]]
cell$design <- inter$relativity[match(paste(cell$injury, cell$age),
                                      paste(inter$level_ik, inter$level_jl))]
cell$mean_log <- NULL
cell$mean_log_design <- NULL
cbind(cell[, 1:3], round(cell[, 4:7], 3))

## who is in the tail: the level's share of all claims and of the largest 1%
## of the claims, their ratio, and the share of its claims over 1 million
tail_level <- data.frame(key,
                         claims_pct = 100 * lev$n / n_claims,
                         top_1pct_pct = 100 * lev$top_1pct /
                           sum(claims$claim_size > q99),
                         over_1m_pct = lev$over_1m_pct)
tail_level$lift <- tail_level$top_1pct_pct / tail_level$claims_pct
cbind(tail_level[, 1:2], round(tail_level[, 3:6], 2))

##########################################
#########  tables: delays and number of payments
##########################################

## notification and settlement delay by level (one-way), in years; base:
## mean delay over the mean multiplier of the level's claims (the means
## before the covariates are 0.1233 and 1.6439 years)
delay_level <- data.frame(key,
                          lev[, .(mean_notidel, median_notidel,
                                  mean_notidel_mult, same_year_pct)],
                          base_notidel = lev$mean_notidel /
                            lev$mean_notidel_mult,
                          lev[, .(mean_setldel, median_setldel, q90_setldel,
                                  mean_setldel_mult, over_5y_pct)],
                          base_setldel = lev$mean_setldel /
                            lev$mean_setldel_mult)
cbind(delay_level[, 1:2], round(delay_level[, 3:13], 3))

## delay multipliers against the reference level: designed, one-way (ratio
## of the means) and all else equal (log-linear model, 95% interval)
delay_effects <- rbind(
  data.frame(delay = "notification",
             key[!is_ref],
             design = design$notidel_mult[!is_ref],
             ratio_of_means = (lev$mean_notidel /
                                 lev$mean_notidel[ref_row])[!is_ref],
             log_linear_effects(claims$notidel, x, ref)[, 3:5]),
  data.frame(delay = "settlement",
             key[!is_ref],
             design = design$setldel_mult[!is_ref],
             ratio_of_means = (lev$mean_setldel /
                                 lev$mean_setldel[ref_row])[!is_ref],
             log_linear_effects(claims$setldel, x, ref)[, 3:5])
)
cbind(delay_effects[, 1:3], round(delay_effects[, 4:8], 3))

## the valuation date truncates the settlement delays: the multipliers of
## the log-linear model on all claims, on the claims closed at the valuation
## date and on those of the last five accident years
closed <- claims$status == "closed"
recent <- closed & claims$AY > n - 5
truncation <- data.frame(
  key[!is_ref],
  design = design$setldel_mult[!is_ref],
  all_claims = log_linear_effects(claims$setldel, x, ref)$estimate,
  closed = log_linear_effects(claims$setldel[closed], x[closed], ref)$estimate,
  closed_last_5_years =
    log_linear_effects(claims$setldel[recent], x[recent], ref)$estimate
)
cbind(truncation[, 1:2], round(truncation[, 3:6], 3))

## number of payments: SynthETIC draws it from the claim size only (three
## bands), so the features act through the size
claims$band <- cut(claims$claim_size,
                   c(0, bands, Inf),
                   labels = c("up to 7,500", "7,500 to 15,000", "over 15,000"))
payments_band <- claims[, .(claims = .N,
                            claims_pct = 100 * .N / n_claims,
                            mean_no_payment = mean(no_payment),
                            design_mean = mean(np_design)),
                        keyby = band]
cbind(payments_band[, 1:2], round(payments_band[, 3:5], 3))
payments_level <- data.frame(key,
                             lev[, .(small_pct, middle_pct, cap_pct,
                                     mean_no_payment, mean_np_design)])
cbind(payments_level[, 1:2], round(payments_level[, 3:7], 3))

##########################################
#########  tables: variance explained
##########################################

## share of the variance explained by the features, by outcome; the claim
## size before the covariates is the check (no effect by design)
outcomes <- list("log claim size" = log(claims$claim_size),
                 "log notification delay" = log(claims$notidel),
                 "log settlement delay" = log(claims$setldel),
                 "number of payments" = claims$no_payment,
                 "log payment lag" = log(claims$lag),
                 "log claim size before the features" =
                   log(claims$claim_size_raw))
variance <- rbindlist(lapply(names(outcomes), function(o) {
  data.table(outcome = o, r2_features(outcomes[[o]], x))
}))
cbind(variance[, 1:2], round(variance[, 3:5], 4))

## number of payments: R2 of the features, of the designed mean given the
## claim size, and of both
tss <- sum((claims$no_payment - mean(claims$no_payment))^2)
fit <- lm.fit(cbind(model.matrix(~ ., x), claims$np_design),
              claims$no_payment)
payments_r2 <- data.frame(
  model = c("features", "designed mean given the claim size", "both"),
  r2 = c(variance$r2[variance$outcome == "number of payments" &
                       variance$term == "additive"],
         1 - sum((claims$no_payment - claims$np_design)^2) / tss,
         1 - sum(fit$residuals^2) / tss)
)
data.frame(model = payments_r2$model, r2 = round(payments_r2$r2, 4))

##########################################
#########  tables: payment pattern, outstanding and chain ladder by level
##########################################

## payments by feature combination, accident year and calendar year, and the
## incremental triangle of every level (development years 1 to n)
idx <- match(trans$claim_no, claims$claim_no)
pay <- data.table(x[idx],
                  occurrence_period = trans$occurrence_period,
                  payment_period = trans$payment_period,
                  payment_inflated = trans$payment_inflated)
pay <- pay[, .(payment_inflated = sum(payment_inflated)),
           by = c(features, "occurrence_period", "payment_period")]
tri <- claims_triangle(pay, n)
tris <- lapply(seq_len(nrow(lev)), function(k) {
  v <- as.character(lev$feature[k])
  claims_triangle(pay[which(pay[[v]] == as.character(lev$level[k])), ], n)
})
cums <- lapply(tris, function(y) t(apply(y, 1, cumsum)))

## payment pattern: cumulative % of the level's nominal ultimate paid by
## development year (true, all accident years; the rest to 100% in year n is
## paid after development year n)
pattern <- t(sapply(seq_along(tris), function(k) {
  100 * cumsum(colSums(tris[[k]])) / lev$ultimate[k]
}))
pattern_all <- 100 * cumsum(colSums(tri)) / sum(claims$ultimate)
pattern <- rbind(pattern, pattern_all)
colnames(pattern) <- paste0("dev_", 1:n)
key_all <- rbind(key, data.frame(feature = "portfolio", level = "all"))
pattern <- data.frame(key_all, pattern)
cbind(pattern[, 1:2], round(pattern[, 2 + c(1, 2, 3, 5, 10, n)], 2))

## payment timing by level: share of the ultimate, amount-weighted mean
## payment lag (years since the occurrence), median lag of a claim
timing <- data.frame(key,
                     ultimate_pct = 100 * lev$ultimate / sum(claims$ultimate),
                     lag = lev$lag,
                     median_claim_lag = lev$median_lag,
                     pattern[seq_len(nrow(lev)), 2 + c(1, 2, 3, 5, 10)])
cbind(timing[, 1:2], round(timing[, 3:10], 2))

## exposure at the valuation date: the level's share of the claims, of the
## claim cost (constant values), of the nominal ultimate and of the true
## outstanding; os_to_claims: share of the outstanding over share of claims
exposure <- data.frame(key,
                       n = lev$n,
                       claims_pct = 100 * lev$n / n_claims,
                       cost_pct = 100 * lev$cost / sum(claims$claim_size),
                       ultimate_pct = 100 * lev$ultimate /
                         sum(claims$ultimate),
                       outstanding_pct = 100 * lev$outstanding /
                         sum(claims$outstanding),
                       paid_pct = 100 * lev$paid / lev$ultimate,
                       mean_ultimate = lev$ultimate / lev$n)
exposure$os_to_claims <- exposure$outstanding_pct / exposure$claims_pct
cbind(exposure[, 1:3], round(exposure[, 4:10], 2))

## open and not yet reported claims by level and their true outstanding
## (millions)
open_level <- data.frame(key,
                         open = lev$open,
                         open_pct = 100 * lev$open / lev$n,
                         unreported = lev$unreported,
                         os_open = lev$os_open / units,
                         os_unreported = lev$os_unreported / units,
                         os_unreported_pct = 100 * lev$os_unreported /
                           lev$outstanding,
                         os_per_open_claim = lev$os_open / lev$open)
cbind(open_level[, 1:2], round(open_level[, 3:9], 2))

## true outstanding (millions) by accident year and Injury Severity; the
## first n - 10 accident years together
os_injury <- claims[, .(outstanding = sum(outstanding) / units),
                    keyby = .(AY = pmax(AY, n - 10),
                              injury = get(features[2]))]
os_injury <- dcast(os_injury, AY ~ injury, value.var = "outstanding")
os_injury$total <- rowSums(os_injury[, -1])
os_injury <- rbind(os_injury, as.list(colSums(os_injury)))
os_injury$AY <- c(paste0("1-", n - 10), (n - 9):n, "total")
cbind(AY = os_injury$AY, round(os_injury[, -1], 1))

## chain-ladder factors f_1, ..., f_8 of each level's own observed triangle,
## the % paid in development year 1 they imply, the standard deviation of
## the individual factors of development year 1, and how thin the triangle
## is (smallest number of claims of an accident year, observed cells with no
## payment)
cl_level <- function(cm) {
  f <- cl_factors(cm)
  c(f[1:8],
    100 / prod(f),
    sd(cm[1:(n - 1), 2] / cm[1:(n - 1), 1]))
}
factors_level <- rbind(t(sapply(cums, cl_level)),
                       cl_level(t(apply(tri, 1, cumsum))))
colnames(factors_level) <- c(paste0("f_", 1:8), "paid_pct_dev_1", "sd_f_1")
factors_level <- data.frame(
  key_all,
  factors_level,
  min_claims = c(stability$min_n, min(table(claims$AY))),
  zero_cells = c(sapply(tris, function(y) {
    sum(upper_triangle(y) == 0, na.rm = TRUE)
  }), sum(upper_triangle(tri) == 0, na.rm = TRUE))
)
cbind(factors_level[, 1:2], round(factors_level[, 3:14], 4))

## chain-ladder reserve of each level's own triangle (Mack 1993) against the
## true outstanding of the level in the triangle (development years 1 to n),
## in millions; one simulation: an error is a single draw, not a bias (thin
## triangles: Mack warns); portfolio_factors: the reserve of the level when
## the factors of the whole triangle are applied to its latest diagonal
## (no feature in the development)
mack <- suppressWarnings(lapply(cums, nncl_mack))
f_all <- cl_factors(t(apply(tri, 1, cumsum)))
to_ultimate <- cumprod(c(1, rev(f_all)))       # of accident year 1, ..., n
cl_reserves_level <- data.frame(
  key,
  paid = sapply(mack, function(m) sum(m$by_origin$latest)) / units,
  CL_reserves = sapply(mack, function(m) sum(m$by_origin$ibnr)) / units,
  msep_sqrt = sapply(mack, function(m) m$total_se) / units,
  true_reserves = sapply(mack, function(m) sum(m$by_origin$true)) / units
)
cl_reserves_level$error <- cl_reserves_level$CL_reserves -
  cl_reserves_level$true_reserves
cl_reserves_level$error_pct <- 100 * cl_reserves_level$error /
  cl_reserves_level$true_reserves
cl_reserves_level$error_to_msep_sqrt <- cl_reserves_level$error /
  cl_reserves_level$msep_sqrt
cl_reserves_level$portfolio_factors <- sapply(mack, function(m) {
  sum(m$by_origin$latest * (to_ultimate - 1))
}) / units
cl_reserves_level$portfolio_factors_error_pct <-
  100 * cl_reserves_level$portfolio_factors / cl_reserves_level$true_reserves -
  100
cbind(cl_reserves_level[, 1:2], round(cl_reserves_level[, 3:11], 2))

## does a split by one feature bring the total closer to the truth? sum of
## the level reserves against the chain ladder of the whole triangle; and
## the sum of the absolute errors of the level reserves, with the level's
## own factors and with the factors of the whole triangle (their reserves
## add up to the reserve of the whole triangle)
mack_all <- nncl_mack(t(apply(tri, 1, cumsum)))
cl_all <- sum(mack_all$by_origin$ibnr) / units
true_all <- sum(mack_all$by_origin$true) / units
split <- as.data.table(cl_reserves_level)
split <- split[, .(segments = .N,
                   CL_reserves = sum(CL_reserves),
                   sum_abs_errors = sum(abs(error)),
                   sum_abs_errors_portfolio_factors =
                     sum(abs(portfolio_factors - true_reserves))),
               keyby = feature]
cl_split <- rbind(data.frame(split = "none (whole triangle)",
                             segments = 1,
                             CL_reserves = cl_all,
                             sum_abs_errors = abs(cl_all - true_all),
                             sum_abs_errors_portfolio_factors =
                               abs(cl_all - true_all)),
                  data.frame(split = paste("by", split$feature),
                             split[, -1]))
cl_split$true_reserves <- true_all
cl_split$error <- cl_split$CL_reserves - true_all
cl_split$error_pct <- 100 * cl_split$error / true_all
cl_split$msep_sqrt_whole_triangle <- mack_all$total_se / units
cbind(cl_split[, 1:2], round(cl_split[, 3:9], 2))

fwrite(design, file.path(tab_dir, "synthetic_features_t01_design.csv"))
fwrite(interactions,
       file.path(tab_dir, "synthetic_features_t02_interactions.csv"))
fwrite(mix, file.path(tab_dir, "synthetic_features_t03_mix.csv"))
fwrite(dependent,
       file.path(tab_dir, "synthetic_features_t04_dependent_pairs.csv"))
fwrite(data.frame(feature = vars, cramer, check.names = FALSE),
       file.path(tab_dir, "synthetic_features_t05_cramers_v.csv"))
fwrite(coverage, file.path(tab_dir, "synthetic_features_t06_combinations.csv"))
fwrite(top_combos,
       file.path(tab_dir, "synthetic_features_t07_top_combinations.csv"))
fwrite(stability,
       file.path(tab_dir, "synthetic_features_t08_mix_by_accident_year.csv"))
fwrite(size_level, file.path(tab_dir, "synthetic_features_t09_claim_size.csv"))
fwrite(sev_effects,
       file.path(tab_dir, "synthetic_features_t10_severity_relativities.csv"))
fwrite(cell, file.path(tab_dir, "synthetic_features_t11_injury_by_age.csv"))
fwrite(tail_level, file.path(tab_dir, "synthetic_features_t12_tail.csv"))
fwrite(delay_level, file.path(tab_dir, "synthetic_features_t13_delays.csv"))
fwrite(delay_effects,
       file.path(tab_dir, "synthetic_features_t14_delay_multipliers.csv"))
fwrite(truncation, file.path(tab_dir, "synthetic_features_t15_truncation.csv"))
fwrite(payments_band,
       file.path(tab_dir, "synthetic_features_t16_payments_by_size.csv"))
fwrite(payments_level,
       file.path(tab_dir, "synthetic_features_t17_payments_by_level.csv"))
fwrite(variance, file.path(tab_dir, "synthetic_features_t18_variance.csv"))
fwrite(payments_r2,
       file.path(tab_dir, "synthetic_features_t19_payments_r2.csv"))
fwrite(pattern,
       file.path(tab_dir, "synthetic_features_t20_payment_pattern.csv"))
fwrite(timing, file.path(tab_dir, "synthetic_features_t21_payment_timing.csv"))
fwrite(exposure, file.path(tab_dir, "synthetic_features_t22_exposure.csv"))
fwrite(open_level, file.path(tab_dir, "synthetic_features_t23_open_claims.csv"))
fwrite(os_injury,
       file.path(tab_dir, "synthetic_features_t24_outstanding_by_injury.csv"))
fwrite(factors_level,
       file.path(tab_dir, "synthetic_features_t25_cl_factors.csv"))
fwrite(cl_reserves_level,
       file.path(tab_dir, "synthetic_features_t26_cl_reserves.csv"))
fwrite(cl_split, file.path(tab_dir, "synthetic_features_t27_cl_split.csv"))

##########################################
#########  figures
##########################################

fig_dir <- file.path(paths$figures, "00_claim-simulation/feature-impact")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
pct_sqrt <- "% (square-root scale)"

## Fig. 1: share of the claims by level (EAJ Fig. 5)
save_figure("SynthETIC features Fig 01 portfolio mix.png",
            level_plot(data.frame(key, value = mix$share_pct),
                       paste("share of the claims in", pct_sqrt),
                       transform = "sqrt",
                       bars = TRUE),
            fig_dir,
            height = 11,
            width = 12)

## Fig. 2: the two pairs of dependent features (EAJ Fig. 6): number of
## claims; white: not possible by design
pair_fig <- data.frame(panel = dependent$pair,
                       x = dependent$level_1,
                       y = dependent$level_2,
                       value = ifelse(dependent$design_pct > 0,
                                      dependent$share_pct,
                                      NA),
                       label = ifelse(dependent$design_pct > 0,
                                      format(dependent$n,
                                             big.mark = ",",
                                             trim = TRUE),
                                      "not possible"))
save_figure("SynthETIC features Fig 02 dependent features.png",
            tile_plot(pair_fig,
                      NULL,
                      NULL,
                      "% of the claims (log scale)",
                      "log10"),
            fig_dir,
            height = 11,
            width = 12)

## Fig. 3: share of the claims, of the nominal ultimate and of the true
## outstanding by level
series <- c("claims", "nominal ultimate", "true outstanding")
share_fig <- data.frame(key,
                        series = rep(series, each = nrow(key)),
                        value = c(exposure$claims_pct, exposure$ultimate_pct,
                                  exposure$outstanding_pct))
save_figure("SynthETIC features Fig 03 shares by level.png",
            level_plot(share_fig,
                       paste("share of the portfolio in", pct_sqrt),
                       transform = "sqrt"),
            fig_dir,
            height = 12,
            width = 12)

## Fig. 4: claim size by level: median with the quartiles, and the mean
series <- c("mean", "median and quartiles")
size_fig <- data.frame(key,
                       series = rep(series, each = nrow(key)),
                       value = c(lev$mean_size, lev$median_size),
                       lower = c(rep(NA, nrow(key)), lev$q25_size),
                       upper = c(rep(NA, nrow(key)), lev$q75_size))
save_figure("SynthETIC features Fig 04 claim size by level.png",
            level_plot(size_fig,
                       "claim size (log scale)",
                       ref = median(claims$claim_size),
                       transform = "log10"),
            fig_dir,
            height = 12,
            width = 12)

## Fig. 5: severity relativities against the reference level
series <- c("designed", "one-way (ratio of means)", "all else equal")
sev_fig <- data.frame(key[!is_ref],
                      series = rep(series, each = sum(!is_ref)),
                      value = c(sev_effects$design, sev_effects$ratio_of_means,
                                sev_effects$estimate),
                      lower = c(rep(NA, 2 * sum(!is_ref)), sev_effects$lower),
                      upper = c(rep(NA, 2 * sum(!is_ref)), sev_effects$upper))
save_figure("SynthETIC features Fig 05 severity relativities.png",
            level_plot(sev_fig,
                       "claim size relative to the reference level (log scale)",
                       ref = 1,
                       transform = "log10",
                       breaks = c(0.2, 0.5, 1, 2, 5, 10, 20)),
            fig_dir,
            height = 11,
            width = 12)

## Fig. 6: delay multipliers against the reference level
k <- nrow(delay_effects)
delay_fig <- data.frame(feature = delay_effects$feature,
                        level = delay_effects$level,
                        panel = paste(delay_effects$delay, "delay"),
                        series = rep(series, each = k),
                        value = c(delay_effects$design,
                                  delay_effects$ratio_of_means,
                                  delay_effects$estimate),
                        lower = c(rep(NA, 2 * k), delay_effects$lower),
                        upper = c(rep(NA, 2 * k), delay_effects$upper))
save_figure("SynthETIC features Fig 06 delay multipliers.png",
            level_plot(delay_fig,
                       "delay relative to the reference level (log scale)",
                       ref = 1,
                       transform = "log10",
                       breaks = c(0.5, 0.7, 1, 1.4, 2)),
            fig_dir,
            height = 11)

## Fig. 7: variance explained by each feature, by outcome: drop-one (bars)
## and one-way (circles); every panel has its own scale
r2_fig <- variance[term %in% features &
                     outcome != "log claim size before the features"]
r2_fig$outcome <- factor(r2_fig$outcome, levels = unique(r2_fig$outcome))
r2_fig$term <- factor(r2_fig$term, levels = rev(features))
save_figure("SynthETIC features Fig 07 variance explained.png",
            ggplot(r2_fig, aes(y = term)) +
              geom_col(aes(x = 100 * drop_one), fill = "grey40", width = 0.7) +
              geom_point(aes(x = 100 * one_way), shape = 1) +
              facet_wrap(~outcome, scales = "free_x", nrow = 1) +
              scale_x_continuous(n.breaks = 4) +
              labs(x = "variance explained (%)", y = NULL) +
              description_theme() +
              theme(strip.text = element_text(size = 7),
                    panel.spacing.x = grid::unit(0.9, "lines")),
            fig_dir,
            height = 6)

## Fig. 8: median claim size (thousands) and number of claims by Injury
## Severity and Age of Claimant
cell_fig <- data.frame(x = cell$age,
                       y = cell$injury,
                       value = cell$median_size / 1000,
                       label = paste0(round(cell$median_size / 1000), "\n(",
                                      format(cell$n, big.mark = ",",
                                             trim = TRUE),
                                      ")"))
save_figure("SynthETIC features Fig 08 injury by age.png",
            tile_plot(cell_fig,
                      features[3],
                      features[2],
                      "median claim size in thousands (log scale)",
                      "log10"),
            fig_dir,
            height = 11,
            width = 12)

## Figs. 9-10: payment pattern and chain-ladder factors of each level
## (black) against the portfolio's (grey)
short <- c("Legal", "Injury", "Age", "Vehicle", "Business")
panel <- paste0(short[as.integer(lev$feature)], ": ", lev$level)
dev_max <- 10
pattern_fig <- data.frame(panel = rep(panel, dev_max),
                          x = rep(1:dev_max, each = nrow(lev)),
                          value = unlist(pattern[seq_len(nrow(lev)),
                                                 2 + 1:dev_max]))
save_figure("SynthETIC features Fig 09 payment pattern.png",
            level_curve_plot(pattern_fig,
                             data.frame(x = 1:dev_max,
                                        value = pattern_all[1:dev_max]),
                             "development year",
                             "cumulative payments (% of the ultimate)") +
              scale_x_continuous(breaks = seq(2, dev_max, by = 2)),
            fig_dir,
            height = 14)
factor_fig <- data.frame(panel = rep(panel, 8),
                         x = rep(1:8, each = nrow(lev)),
                         value = unlist(factors_level[seq_len(nrow(lev)),
                                                      2 + 1:8]) - 1)
factor_all <- unlist(factors_level[nrow(lev) + 1, 2 + 1:8]) - 1
save_figure("SynthETIC features Fig 10 chain-ladder factors.png",
            level_curve_plot(factor_fig[factor_fig$value > 0, ],
                             data.frame(x = 1:8, value = factor_all),
                             "development year j",
                             "chain-ladder factor minus 1 (log scale)",
                             transform = "log10") +
              scale_x_continuous(breaks = seq(2, 8, by = 2)),
            fig_dir,
            height = 14)

## Fig. 11: number of payments against the claim size by Injury Severity and
## the designed mean; bins of the claim size by factors of 2 from the upper
## band limit (the two band limits are bin limits), with 50 claims or more,
## drawn at the centre of the bin
claims$size_bin <- floor(log2(claims$claim_size / bands[2]))
np_fig <- claims[, .(n = .N, value = mean(no_payment)),
                 keyby = .(injury = get(features[2]), size_bin)]
np_fig <- np_fig[n >= 50]
np_fig$size <- bands[2] * 2^(np_fig$size_bin + 0.5)
size_grid <- 10^seq(2, 7, by = 0.02)
np_curve <- data.frame(
  size = size_grid,
  value = ifelse(size_grid <= bands[1],
                 1.5,
                 ifelse(size_grid <= bands[2],
                        8 / 3,
                        pmin(8, 4 + log(size_grid / bands[2]))))
)
save_figure("SynthETIC features Fig 11 number of payments.png",
            ggplot(np_fig, aes(x = size, y = value)) +
              geom_line(data = np_curve,
                        aes(x = size),
                        colour = "grey60",
                        linewidth = 0.9) +
              geom_point(aes(shape = injury), size = 1.2) +
              scale_shape_manual(values = c(16, 1, 17, 2, 15, 0)) +
              scale_x_log10(labels = scales::label_comma()) +
              labs(x = "claim size (log scale)",
                   y = "mean number of payments") +
              description_theme() +
              theme(legend.title = element_text()) +
              guides(shape = guide_legend(title = features[2], nrow = 1)),
            fig_dir,
            height = 8,
            width = 12)

## Fig. 12: error of the chain-ladder reserve of each level in % of its true
## outstanding, with one sqrt(msep) (Mack) to each side
error_fig <- data.frame(key,
                        value = cl_reserves_level$error_pct,
                        lower = 100 * (cl_reserves_level$error -
                                         cl_reserves_level$msep_sqrt) /
                          cl_reserves_level$true_reserves,
                        upper = 100 * (cl_reserves_level$error +
                                         cl_reserves_level$msep_sqrt) /
                          cl_reserves_level$true_reserves)
save_figure("SynthETIC features Fig 12 chain-ladder reserves by level.png",
            level_plot(error_fig,
                       "chain-ladder reserve - true outstanding (% of true)",
                       ref = 0),
            fig_dir,
            height = 11,
            width = 12)

## Fig. 13: mix over the accident years: mean and range of the level's
## share of the claims and of the nominal ultimate
panels <- c("share of the claims (%)", "share of the nominal ultimate (%)")
mix_fig <- data.frame(key,
                      panel = rep(panels, each = nrow(key)),
                      value = c(stability$claims_pct_mean,
                                stability$ultimate_pct_mean),
                      lower = c(stability$claims_pct_min,
                                stability$ultimate_pct_min),
                      upper = c(stability$claims_pct_max,
                                stability$ultimate_pct_max))
save_figure("SynthETIC features Fig 13 mix by accident year.png",
            level_plot(mix_fig, pct_sqrt, transform = "sqrt"),
            fig_dir,
            height = 11)
