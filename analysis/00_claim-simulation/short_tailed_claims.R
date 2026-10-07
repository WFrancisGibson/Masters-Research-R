##########################################
#########  Short tailed claims simulation with SynthETIC
#########  Avanzi, Taylor, Wang & Wong (2021); environment 1 (simple, short
#########  tail) of Al-Mudafer, Avanzi, Taylor & Wong (2021),
#########  with 5 claim covariates
##########################################

source(here::here("analysis", "00_setup.R"))
library(SynthETIC)

##########################################
#########  settings
##########################################

seed <- cfg$seed            # 2026
time_unit <- 1              # 1 = annual (20 x 20), 1/4 = quarterly (40 x 40)
years <- 20                 # quarterly: time_unit <- 1/4 and years <- 10
delays <- "environment 1"   # delay means: "environment 1" or "claim size"
# superimposed_inflation = TRUE: SynthETIC's default superimposed inflation
superimposed_inflation <- FALSE

covariate_seed <- 100000L + seed
ref_claim <- 200000              # SynthETIC's claim size scale
sim_periods <- years / time_unit # number of accident (and development) periods
set_parameters(ref_claim = ref_claim, time_unit = time_unit)
set.seed(seed)

## output folder, e.g. data/raw/claim-simulation-annual
folder <- if (time_unit == 1) "claim-simulation-annual" else "claim-simulation"
if (delays == "claim size") folder <- paste0(folder, "-vignette")
if (superimposed_inflation) folder <- paste0(folder, "-SI")
out_dir <- file.path(paths$raw, folder)

##########################################
#########  SynthETIC modules
##########################################

## Module 2: claim size cdf, a normal cdf on the scale s^0.2 truncated at 30
sev_cdf <- function(s) {
  if (s < 30) return(0)
  (pnorm(s^0.2, 9.5, 3) - pnorm(30^0.2, 9.5, 3)) / (1 - pnorm(30^0.2, 9.5, 3))
}

## SynthETIC's default mean settlement delay (in periods); the formula counts
## the occurrence in quarters, so a period is mapped to the quarter at its
## midpoint
setldel_default <- function(claim_size, occurrence_period) {
  q <- (occurrence_period - 0.5) * 4 * time_unit + 0.5
  if (claim_size < 0.1 * ref_claim && q >= 21) {
    a <- min(0.85,
             0.65 + 0.02 * (q - 21)) # small claims occurring after quarter 20
  } else {
    a <- max(0.85,
             1 - 0.0075 * q)        # from ~1 to 0.85 over the first 20 quarters
  }
  a * min(25,
          max(1,
              6 + 4 * log(claim_size / (0.1 * ref_claim)))) / 4 / time_unit
}

## Module 3 and 4: mean notification and settlement delays (in periods) and
## their cvs
if (delays == "environment 1") {
  # environment 1: constant means, given in quarters
  notidel_mean <- function(claim_size, occurrence_period) {
    0.49305517 / 4 / time_unit
  }
  setldel_mean <- function(claim_size, occurrence_period) {
    6.575582 / 4 / time_unit
  }
  notidel_cv <- 1.919494
  setldel_cv <- 1.02259
} else {
  # SynthETIC's default delays: notification 1 to 3 quarters (shorter for
  # larger claims), settlement growing with the claim size
  notidel_mean <- function(claim_size, occurrence_period) {
    min(3, max(1, 2 - log(claim_size / (0.5 * ref_claim)) / 3)) / 4 / time_unit
  }
  setldel_mean <- setldel_default
  notidel_cv <- 0.7
  setldel_cv <- 0.6
}

## Weibull delays; the covariate multiplier scales the Weibull scale,
## i.e. the mean
notidel_param <- function(claim_size, occurrence_period, cov_mult) {
  p <- get_Weibull_parameters(
    target_mean = notidel_mean(claim_size, occurrence_period),
    target_cv = notidel_cv
  )
  c(shape = p[1], scale = p[2] * cov_mult)
}
setldel_param <- function(claim_size, occurrence_period, cov_mult) {
  p <- get_Weibull_parameters(
    target_mean = setldel_mean(claim_size, occurrence_period),
    target_cv = setldel_cv
  )
  c(shape = p[1], scale = p[2] * cov_mult)
}

## Module 5: number of payments by claim size band (SynthETIC vignette)
rmixed_payment_no <- function(n, claim_size) {
  b1 <- 0.0375 * ref_claim
  b2 <- 0.075 * ref_claim
  no_pmt <- sample(c(1, 2), size = n, replace = TRUE, prob = c(1 / 2, 1 / 2))
  mid <- which(b1 < claim_size & claim_size <= b2)
  no_pmt[mid] <- sample(c(2, 3), size = length(mid), replace = TRUE,
                        prob = c(1 / 3, 2 / 3))
  large <- which(claim_size > b2)
  prob <- 1 / (pmin(8, 4 + log(claim_size[large] / b2)) - 3)
  no_pmt[large] <- rgeom(length(large), prob = prob) + 4
  no_pmt
}

## Module 7: payment delays, SynthETIC's default written out
## (claim_payment_delay uses our paramfun only together with an rfun):
## Weibull gaps, the last one about a quarter when there are 4 or more
## payments, rescaled to add up to the settlement delay
r_pmntdel <- function(n, claim_size, setldel, setldel_mean) {
  p <- get_Weibull_parameters(target_mean = setldel_mean / n, target_cv = 0.35)
  if (n >= 4) {
    p_last <- get_Weibull_parameters(target_mean = 1 / 4 / time_unit,
                                     target_cv = 0.20)
    d_last <- rweibull(1, shape = p_last[1], scale = p_last[2])
    d <- c(rweibull(n - 1, shape = p[1], scale = p[2]), d_last)
  } else {
    d <- rweibull(n, shape = p[1], scale = p[2])
  }
  d[-n] <- setldel / sum(d) * d[-n]
  d[n] <- setldel - sum(d[-n])
  d
}
## the covariate multiplier also scales the mean settlement delay of the
## payment delays
param_pmntdel <- function(claim_size, setldel, occurrence_period, cov_mult) {
  c(claim_size = claim_size, setldel = setldel,
    setldel_mean = setldel_default(claim_size, occurrence_period) * cov_mult)
}

## Module 8: 2% p.a. base inflation; SynthETIC reads this vector by quarter
## whatever the time_unit, one entry per quarter over twice the simulated years
base_inflation <- rep((1 + 0.02)^(1 / 4) - 1, 2 * 4 * years)

## superimposed inflation: none, or SynthETIC's default (small claims occurring
## after quarter 20 cost up to 40% less, payments of small claims grow up to
## 30% p.a.)
if (superimposed_inflation) {
  si_occurrence <- function(occurrence_time, claim_size) {
    if (occurrence_time <= 20 / 4 / time_unit) return(1)
    1 - 0.4 * max(0, 1 - claim_size / (0.25 * ref_claim))
  }
  si_payment <- function(payment_time, claim_size) {
    rate <- ((1 + 0.30)^time_unit - 1) * max(0, 1 - claim_size / ref_claim)
    (1 + rate)^payment_time
  }
} else {
  si_occurrence <- function(occurrence_time, claim_size) 1
  si_payment <- function(payment_time, claim_size) 1
}

##########################################
#########  claim covariates
##########################################

## part A: Legal Representation x Injury Severity x Age of Claimant
## (SynthETIC vignette)
cov_a <- test_covariates_obj

## part B: Vehicle type x Business use, relativities in the row order of the
## template
factors_b <- list("Vehicle type" = c("Passenger", "Light Commerical",
                                     "Medium goods", "Heavy goods"),
                  "Business use" = c("Y", "N"))
freq_b <- relativity_template(factors_b)
freq_b$relativity <- c(5, 1.5, 0.35, 0.25,     # vehicle types
                       1, 4,                   # passenger x business use Y, N
                       1, 0.6,                 # light commercial x business use
                       0.35, 0.01,             # medium goods x business use
                       0.25, 0,                # heavy goods x business use
                       2.5, 5)                 # business use Y, N
sev_b <- relativity_template(factors_b)
sev_b$relativity <- c(0.25, 0.75, 1, 3,
                      1, 1,
                      1, 1,
                      1, 1,
                      1, 1,
                      1.3, 1)

## the 5 factors; the pairs across parts A and B get relativity 1
factors5 <- c(cov_a$factors, factors_b)
relativity5 <- function(rel_a, rel_b) {
  key <- function(d) {
    paste(d$factor_i, d$factor_j, d$level_ik, d$level_jl, sep = "|")
  }
  rel <- relativity_template(factors5)
  m <- match(key(rel), c(key(rel_a), key(rel_b)))
  rel$relativity <- ifelse(is.na(m), 1,
                           c(rel_a$relativity, rel_b$relativity)[m])
  rel
}
freq5 <- relativity5(cov_a$relativity_freq, freq_b)
sev5 <- relativity5(cov_a$relativity_sev, sev_b)
cov5 <- covariates(factors5)
cov5 <- set.covariates_relativity(cov5, freq5, "freq")
cov5 <- set.covariates_relativity(cov5, sev5, "sev")

## multipliers of the mean notification and settlement delays
## (1 = reference level)
delay_mult <- rbind(
  data.frame(factor = "Legal Representation", level = c("Y", "N"),
             notidel_mult = c(1.00, 0.80), setldel_mult = c(1.00, 0.60),
             rationale = c("reference (97% of claims)",
                           paste("unrepresented claimants deal with the",
                                 "insurer directly: reported and settled",
                                 "faster"))),
  data.frame(factor = "Injury Severity", level = as.character(1:6),
             notidel_mult = c(1.10, 1.00, 0.95, 0.90, 0.85, 0.70),
             setldel_mult = c(0.85, 1.00, 1.20, 1.45, 1.75, 0.80),
             rationale = c(paste("minor / soft tissue: reported late,",
                                 "settled quickly"),
                           "reference",
                           paste("moderate: hospital contact speeds reporting;",
                                 "prognosis takes longer"),
                           paste("serious: reported fast; settlement waits for",
                                 "stabilisation"),
                           "severe: reported fast; longest settlement",
                           paste("fatal: reported immediately; settlement",
                                 "comparatively quick"))),
  data.frame(factor = "Age of Claimant",
             level = c("0-15", "15-30", "30-50", "50-65", "over 65"),
             notidel_mult = c(1.10, 1.00, 1.00, 1.00, 1.00),
             setldel_mult = c(1.30, 1.00, 1.00, 0.95, 0.90),
             rationale = c(paste("minors: lodged by guardians; settlement",
                                 "deferred until prognosis stable"),
                           "reference", "reference",
                           "smaller economic-loss head",
                           "no earnings-loss head to quantify")),
  data.frame(factor = "Vehicle type", level = factors_b[["Vehicle type"]],
             notidel_mult = c(1.00, 0.95, 0.90, 0.90),
             setldel_mult = c(1.00, 1.00, 1.05, 1.10),
             rationale = c("reference (93% of claims)", "fleet reporting",
                           paste("fleet reporting; more multi-party",
                                 "liability questions"),
                           paste("fleet reporting; more often disputed /",
                                 "multi-party"))),
  data.frame(factor = "Business use", level = c("Y", "N"),
             notidel_mult = c(0.85, 1.00), setldel_mult = c(1.05, 1.00),
             rationale = c(paste("formal incident reporting; liability",
                                 "slightly more contested"),
                           "reference (86% of claims)"))
)

##########################################
#########  simulate the claims
##########################################

## Module 1: claim numbers (200000 exposure x 0.1 = 20000 a year) and
## occurrence times
n_vector <- claim_frequency(I = sim_periods, E = 200000, freq = 0.1)
occurrence_times <- claim_occurrence(n_vector)
n_claims <- sum(n_vector)
occ_period <- rep(1:sim_periods, times = n_vector)

## Module 2: claim sizes before the covariates
claim_sizes_raw <- claim_size(n_vector, sev_cdf, type = "p",
                              range = c(0, 1e24))

## covariates: every claim gets one of the 2 x 6 x 5 x 4 x 2 = 480 level
## combinations (probability proportional to its frequency relativities);
## the claim sizes are multiplied by the severity relativities and rescaled
## to the same total claim cost
adj <- claim_size_adj(cov5, claim_sizes_raw, random_seed = covariate_seed)
claim_sizes <- adj$claim_size_adj
cov_levels <- as.data.frame(adj$covariates_data$data, check.names = FALSE)
cost_ratio <- sum(unlist(claim_sizes)) / sum(unlist(claim_sizes_raw))
stopifnot(abs(cost_ratio - 1) < 1e-6)

## delay multipliers of every claim: product over the 5 factors
notidel_mult <- rep(1, n_claims)
setldel_mult <- rep(1, n_claims)
for (fct in unique(delay_mult$factor)) {
  tab <- delay_mult[which(delay_mult$factor == fct), ]
  idx <- match(as.character(cov_levels[[fct]]), tab$level)
  notidel_mult <- notidel_mult * tab$notidel_mult[idx]
  setldel_mult <- setldel_mult * tab$setldel_mult[idx]
}

## Module 3 and 4: notification and settlement delays
notidel <- claim_notification(n_vector, claim_sizes, paramfun = notidel_param,
                              cov_mult = notidel_mult)
setldel <- claim_closure(n_vector, claim_sizes, paramfun = setldel_param,
                         cov_mult = setldel_mult)

## Module 5 and 6: number and sizes of the payments (sizes: SynthETIC's
## default, which is the vignette's rmixed_payment_size)
no_payments <- claim_payment_no(n_vector, claim_sizes,
                                rfun = rmixed_payment_no)
payment_sizes <- claim_payment_size(n_vector, claim_sizes, no_payments)

## Module 7: payment delays and payment times
payment_delays <- claim_payment_delay(n_vector, claim_sizes, no_payments,
                                      setldel,
                                      rfun = r_pmntdel,
                                      paramfun = param_pmntdel,
                                      occurrence_period = occ_period,
                                      cov_mult = setldel_mult)
payment_times <- claim_payment_time(n_vector, occurrence_times, notidel,
                                    payment_delays)

## Module 8: inflated payments
payment_inflated <- claim_payment_inflation(n_vector, payment_sizes,
                                            payment_times, occurrence_times,
                                            claim_sizes, base_inflation,
                                            si_occurrence, si_payment)

##########################################
#########  claim and transaction data
##########################################

transactions <- generate_transaction_dataset(
  claims(frequency_vector = n_vector,
         occurrence_list = occurrence_times,
         claim_size_list = claim_sizes,
         notification_list = notidel,
         settlement_list = setldel,
         no_payments_list = no_payments,
         payment_size_list = payment_sizes,
         payment_delay_list = payment_delays,
         payment_time_list = payment_times,
         payment_inflated_list = payment_inflated),
  adjust = FALSE
)
setDT(transactions)

claims <- generate_claim_dataset(
  frequency_vector = n_vector,
  occurrence_list = occurrence_times,
  claim_size_list = claim_sizes,
  notification_list = notidel,
  settlement_list = setldel,
  no_payments_list = no_payments
)
claims$claim_size_raw <- unlist(claim_sizes_raw)
claims$sev_relativity <- claims$claim_size / claims$claim_size_raw
claims$notidel_mult <- notidel_mult
claims$setldel_mult <- setldel_mult
claims <- cbind(claims, cov_levels)
setDT(claims)

## mean payment size and last development period with a payment, per claim
pay_claim <- transactions[, .(
  mean_payment_size = mean(payment_inflated),
  last_payment_dev = max(payment_period - occurrence_period + 1L)
), by = claim_no]
claims <- merge(claims, pay_claim, by = "claim_no", all.x = TRUE)

## incremental n x n triangle, the payments after the last period in the
## last column
tri <- claims_triangle(transactions, sim_periods, tail = TRUE)

##########################################
#########  summary tables
##########################################

## impact of the covariate levels
factor_names <- names(cov5$factors)
impact_by_level <- rbindlist(lapply(factor_names, function(fct) {
  claims[, .(
    factor = fct,
    n = .N,
    share = .N / nrow(claims),
    mean_size_raw = mean(claim_size_raw),     # before the covariates
    mean_size_adj = mean(claim_size),         # after the covariates
    mean_sev_relativity = mean(sev_relativity),
    mean_notidel = mean(notidel),
    mean_notidel_mult = mean(notidel_mult),
    mean_setldel = mean(setldel),
    mean_setldel_mult = mean(setldel_mult),
    mean_no_payment = mean(no_payment),
    mean_payment_size = mean(mean_payment_size),
    share_settled_by_2yrs = mean(last_payment_dev <= 2 / time_unit)
  ), by = .(level = as.character(get(fct)))][order(level)]
}))
setcolorder(impact_by_level, c("factor", "level"))

## development pattern by level: cumulative share of the level's total paid
## amount by development period (all accident periods together)
dev_by_level <- NULL
for (fct in factor_names) {
  lev <- as.character(claims[[fct]])[match(transactions$claim_no,
                                           claims$claim_no)]
  for (l in sort(unique(lev))) {
    tri_l <- claims_triangle(transactions[which(lev == l)], sim_periods,
                             tail = TRUE)
    cum <- cumsum(colSums(tri_l)) / sum(tri_l)
    dev_by_level <- rbind(
      dev_by_level,
      data.frame(factor = fct, level = l, total_paid = sum(tri_l),
                 as.list(setNames(round(cum, 4),
                                  paste0("dev", 1:sim_periods))))
    )
  }
}

## portfolio summary; the delays and their target means (before the
## covariates) in periods
observed <- row(tri) + col(tri) <= sim_periods + 1
notified <- claims$occurrence_time + claims$notidel   # notification times
portfolio <- data.frame(
  n_claims = n_claims,
  n_payments = nrow(transactions),
  total_claim_size_raw = sum(claims$claim_size_raw),
  total_claim_size_adj = sum(claims$claim_size),
  median_size_raw = median(claims$claim_size_raw),
  median_size_adj = median(claims$claim_size),
  mean_notidel = mean(claims$notidel),
  env1_target_notidel = mean(mapply(notidel_mean, unlist(claim_sizes),
                                    occ_period)),
  mean_setldel = mean(claims$setldel),
  env1_target_setldel = mean(mapply(setldel_mean, unlist(claim_sizes),
                                    occ_period)),
  mean_no_payment = mean(claims$no_payment),
  triangle_total = sum(tri),
  pct_of_triangle_observed = sum(tri[observed]) / sum(tri),
  # claims notified and settled in the same period (never seen open)
  share_no_observation = mean(floor(notified) ==
                                floor(notified + claims$setldel))
)
# the claim size delays have claim specific target means
if (delays == "claim size") {
  names(portfolio) <- sub("env1_target", "target_mean", names(portfolio))
}

t(portfolio)
cbind(impact_by_level[, 1:2], round(impact_by_level[, -(1:2)], 3))

##########################################
#########  write the outputs
##########################################

dir.create(out_dir, showWarnings = FALSE)
fwrite(claims, file.path(out_dir, "claims.csv"))
fwrite(transactions, file.path(out_dir, "transactions.csv"))
fwrite(data.frame(AY = 1:sim_periods, tri, check.names = FALSE),
       file.path(out_dir, "triangle.csv"))
fwrite(impact_by_level, file.path(out_dir, "impact_by_level.csv"))
fwrite(dev_by_level, file.path(out_dir, "development_by_level.csv"))
fwrite(portfolio, file.path(out_dir, "summary.csv"))
fwrite(freq5, file.path(out_dir, "covariates_freq_relativities.csv"))
fwrite(sev5, file.path(out_dir, "covariates_sev_relativities.csv"))
fwrite(delay_mult, file.path(out_dir, "delay_multipliers.csv"))
saveRDS(cov5, file.path(out_dir, "covariates_5factor.rds"))
