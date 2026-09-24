# Short tailed (Simple, short tail) Claims Simulation environment
# Load the 00_setup
source(here::here("analysis", "00_setup.R"))
#Load packages

suppressPackageStartupMessages({
  library(tidyverse)
  library(dplyr)
  library(ChainLadder)
  library(ggplot2)
  library(SynthETIC)
  library(data.table)
  library(stats)
})


# Global parameters
set.seed(2026)

seed <- 2026
covariate_seed <- 100000L + seed
runoff_1 <- 1L

# Define the scale of the claim size
ref_claim <- 200000

#40 Quater simulations
time_unit <- 1 / 4

# Total years
years <- 10

# Number of periods to simulate
sim_periods <- years / time_unit

# Effective annual exposure rates
exposure <- c(rep(ref_claim, sim_periods))

# Claim frequency rate per unit of exposure
claim_freq <- c(rep(0.1, sim_periods))

#SyntETIC parameters setting
set_parameters(ref_claim = ref_claim, time_unit = time_unit)

#Define delay target variables
# based on the environment 1
notidel_target_mean <- 0.49305517
notidel_target_cv <- 1.919494
setldel_target_mean <- 6.575582
setldel_target_cv <- 1.02259


###############################################################
# SynthETIC claims simulation functions
################################################################

# Module 2: Claim severity distribution function
sev_df <- function(s) {
  if (s < 30) {
    0
  } else {
    p_trun <- pnorm(s^0.2, 9.5, 3) - pnorm(30^0.2, 9.5, 3)
    p_rescaled <- p_trun / (1 - pnorm(30^0.2, 9.5, 3))
    p_rescaled
  }
}

# Module 3: Notification delay
notidel_param <- function(claim_size, occurrence_period) {
  target_mean <- 0.49305517
  target_cv <- 1.919494
  params <- get_Weibull_parameters(target_mean = target_mean,
                                   target_cv = target_cv)
  c(shape = params[1], scale = params[2])
}

# Module 4: settlement delay
setldel_param <- function(claim_size, occurrence_period) {
  target_mean <- 6.575582
  target_cv <- 1.02259
  params <- get_Weibull_parameters(target_mean = target_mean,
                                   target_cv = target_cv)
  c(shape = params[1], scale = params[2])
}

# Module 5 number of paymentsL banded on claim size.

benchmark_1 <- 0.0375 * ref_claim
benchmark_2 <- 0.075 * ref_claim

rmixed_payment_no <- function(n, claim_size, claim_size_benchmark_1,
                              claim_size_benchmark_2) {
  test_1 <- claim_size_benchmark_1 < claim_size &
    claim_size <= claim_size_benchmark_2
  test_2 <- claim_size > claim_size_benchmark_2
  no_pmnt <- sample(c(1, 2), size = n, replace = TRUE, prob = c(1 / 2, 1 / 2))
  no_pmnt[test_1] <- sample(c(2, 3), size = sum(test_1),
                            replace = TRUE, prob = c(1 / 3, 2 / 3))
  no_pmnt_mean <- pmin(8, 4 + log(claim_size / claim_size_benchmark_2))
  prob <- 1 / (no_pmnt_mean - 3)
  no_pmnt[test_2] <- stats::rgeom(sum(test_2), prob = prob[test_2]) + 4
  no_pmnt
}

# Module 6 payment size sum
rmixed_payment_size <- function(n, claim_size) {
  if (n >= 4) {
    p_mean <- 1 - min(0.95, 0.75 + 0.04 * log(claim_size / (0.1 * ref_claim)))
    p_cv <- 0.20
    p_parameters <- get_Beta_parameters(target_mean = p_mean, target_cv = p_cv)

    last_two_pmnts_complement <- stats::rbeta(1,
                                              shape1 = p_parameters[1],
                                              shape2 = p_parameters[2])

    last_two_pmnts <- 1 - last_two_pmnts_complement

    q_mean <- 0.9
    q_cv <- 0.03
    q_parameters <- get_Beta_parameters(target_mean = q_mean, target_cv = q_cv)
    q <- stats::rbeta(1, shape1 = q_parameters[1], shape2 = q_parameters[2])

    p_second_last <- q * last_two_pmnts
    p_last <- (1 - q) * last_two_pmnts
    p_unnorm_mean <- last_two_pmnts_complement / (n - 2)
    p_unnorm_cv <- 0.10

    p_unnorm_parameters <- get_Beta_parameters(target_mean = p_unnorm_mean,
                                               target_cv = p_unnorm_cv)

    amnt <- stats::rbeta(n - 2,
                         shape1 = p_unnorm_parameters[1],
                         shape2 = p_unnorm_parameters[2])

    amnt <- last_two_pmnts_complement * (amnt / sum(amnt))
    amnt <- append(amnt, c(p_second_last, p_last))
    amnt <- claim_size * amnt
  } else if (n == 2 || n == 3) {
    p_unnorm_mean <- 1 / n
    p_unnorm_cv <- 0.10
    p_unnorm_parameters <- get_Beta_parameters(target_mean = p_unnorm_mean,
                                               target_cv = p_unnorm_cv)

    amnt <- stats::rbeta(n,
                         shape1 = p_unnorm_parameters[1],
                         shape2 = p_unnorm_parameters[2])

    amnt <- claim_size * amnt / sum(amnt)

  } else {
    amnt <- claim_size
  }
  amnt
}



# Module 7 payment delays
r_pmntdel <- function(n, claim_size, setldel, setldel_mean) {
  result <- rep(NA_real_, n)
  if (n >= 4) {
    unnorm_d_mean <- (1 / 4) / time_unit
    unnorm_d_cv <- 0.20
    parameters <- get_Weibull_parameters(target_mean = unnorm_d_mean,
                                         target_cv = unnorm_d_cv)
    result[n] <- stats::rweibull(1, shape = parameters[1],
                                 scale = parameters[2])
    for (i in 1:(n - 1)) {
      unnorm_d_mean <- setldel_mean / n
      unnorm_d_cv <- 0.35
      parameters <- get_Weibull_parameters(target_mean = unnorm_d_mean,
                                           target_cv = unnorm_d_cv)
      result[i] <- stats::rweibull(1, shape = parameters[1],
                                   scale = parameters[2])
    }
  } else {
    for (i in 1:n) {
      unnorm_d_mean <- setldel_mean / n
      unnorm_d_cv <- 0.35
      parameters <- get_Weibull_parameters(target_mean = unnorm_d_mean,
                                           target_cv = unnorm_d_cv)
      result[i] <- stats::rweibull(1, shape = parameters[1],
                                   scale = parameters[2])
    }
  }
  first <- seq_len(n - 1)
  result[first] <- (setldel / sum(result)) * result[first]
  result[n] <- setldel - sum(result[first])
  result
}

param_pmntdel <- function(claim_size, setldel, occurrence_period) {
  if (claim_size < (0.1 * ref_claim) && occurrence_period >= 21) {
    a <- min(0.85, 0.65 + 0.02 * (occurrence_period - 21))
  } else {
    a <- max(0.85, 1 - 0.0075 * occurrence_period)
  }
  mean_quarter <- a * min(25,
                          max(1, 6 + 4 * log(claim_size / (0.1 * ref_claim))))
  target_mean <- mean_quarter / 4 / time_unit
  c(claim_size = claim_size,
    setldel = setldel,
    setldel_mean = target_mean)
}

# Module 8 Inflation: Simple 2% p.a., no superimposed inflation
base_rate <- (1 + 0.02) ^ (1 / 4) - 1
base_inflation_past <- rep(base_rate, times = sim_periods)
base_inflation_future <- rep(base_rate, times = sim_periods)
base_inflation_vector <- c(base_inflation_past, base_inflation_future)

si_occurrence <- function(occurrence_time, claim_size) {
  { # nolint
    1
  }
}

si_payment <- function(payment_time, claim_size) {
  period_rate <- (1 + 0)^(time_unit) - 1
  beta <- period_rate
  (1 + beta)^payment_time
}

#################################################################
# Covariate Simulation
#################################################################
# part A using covariates in vignette of SynthETIC
# Covariates included in part A:
# Legal Representation x Injury Severity x Age of Claimant
bundled <- SynthETIC::test_covariates_obj


# part B: vhicle object from the vignette

factors_tmp <- list(
  "Vehicle type" = c("Passenger", "Light Commerical",
                     "Medium goods", "Heavy goods"),
  "Business use" = c("Y", "N")
)

relativity_freq_tmp <- relativity_template(factors_tmp)
relativity_sev_tmp <- relativity_template(factors_tmp)

relativity_freq_tmp$relativity <- c(
  5, 1.5, 0.35, 0.25,
  1, 4,
  1, 0.6,
  0.35, 0.01,
  0.25, 0,
  2.5, 5
)

relativity_sev_tmp$relativity <- c(
  0.25, 0.75, 1, 3,
  1, 1,
  1, 1,
  1, 1,
  1, 1,
  1.3, 1
)

vehicle <- covariates(factors_tmp)

vehicle <- set.covariates_relativity(covariates = vehicle,
                                     relativity = relativity_freq_tmp,
                                     freq_sev = "freq")


vehicle <- set.covariates_relativity(covariates = vehicle,
                                     relativity = relativity_sev_tmp,
                                     freq_sev = "sev")

# Combining the part  A and part B covariates to an appropriate level.



factors5 <- c(bundled$factors, vehicle$factors)
template5 <- relativity_template(factors5)
row_key <- function(d) {
  paste(d$factor_i,
        d$factor_j,
        d$level_ik,
        d$level_jl,
        sep = "|")
}
fill_from_sources <- function(tmpl, sources) {
  tmpl$relativity <- 1
  for (src in sources) {
    m <- match(row_key(tmpl), row_key(src))
    tmpl$relativity[!is.na(m)] <- src$relativity[m[!is.na(m)]]
  }
  tmpl
}

freq5 <- fill_from_sources(template5,
                           list(bundled$relativity_freq,
                                vehicle$relativity_freq))

sev5  <- fill_from_sources(template5,
                           list(bundled$relativity_sev,
                                vehicle$relativity_sev))

cov5 <- covariates(factors5)
cov5 <- set.covariates_relativity(cov5, freq5, "freq")
cov5 <- set.covariates_relativity(cov5, sev5,  "sev")

delay_mult <- bind_rows(
  tibble(factor = "Legal Representation",
         level = c("Y", "N"),
         notidel_mult = c(1.00, 0.80),
         setldel_mult = c(1.00, 0.60),
         rationale = c("reference (97% of claims)",
                       "unrepresented claimants deal with the insurer directly:
                       reported and settled faster")),
  tibble(factor = "Injury Severity",
         level = as.character(1:6),
         notidel_mult = c(1.10, 1.00, 0.95, 0.90, 0.85, 0.70),
         setldel_mult = c(0.85, 1.00, 1.20, 1.45, 1.75, 0.80),
         rationale = c("minor / soft tissue: reported late, settled quickly",
                       "reference", "moderate: 
                        hospital contact speeds reporting;
                       prognosis takes longer",
                       "serious: reported fast;
                       settlement waits for stabilisation",
                       "severe: reported fast; longest settlement",
                       "fatal: reported immediately;
                        settlement comparatively quick")),
  tibble(factor = "Age of Claimant",
         level = c("0-15", "15-30", "30-50", "50-65", "over 65"),
         notidel_mult = c(1.10, 1.00, 1.00, 1.00, 1.00),
         setldel_mult = c(1.30, 1.00, 1.00, 0.95, 0.90),
         rationale = c("minors: lodged by guardians;
                        settlement deferred until prognosis stable",
                       "reference", "reference",
                       "smaller economic-loss head",
                       "no earnings-loss head to quantify")),
  tibble(factor = "Vehicle type",
         level = c("Passenger", "Light Commerical",
                   "Medium goods", "Heavy goods"),
         notidel_mult = c(1.00, 0.95, 0.90, 0.90),
         setldel_mult = c(1.00, 1.00, 1.05, 1.10),
         rationale = c("reference (93% of claims)", "fleet reporting",
                       "fleet reporting; more multi-party liability questions",
                       "fleet reporting; more often disputed / multi-party")),
  tibble(factor = "Business use", level = c("Y", "N"),
         notidel_mult = c(0.85, 1.00), setldel_mult = c(1.05, 1.00),
         rationale = c("formal incident reporting;
                       liability slightly more contested",
                       "reference (86% of claims)"))
)




# Simulation of the claims portfolio


# Module 1 Claim counts & occurrence times

n_vector <- claim_frequency(sim_periods, exposure, claim_freq)
occurrence_times <- claim_occurrence(n_vector)
n_claims <- sum(n_vector)

# Module 2a Claim size (before covariate changes)

claim_sizes_raw <- claim_size(n_vector, sev_df, type = "p", range = c(0, 1e24))


# Module 2b Covariates
# The following two assumptions are
# made to ensure a consistent comparison between
# draw one of the sets of 2 x 6 x 5 x 4 x 2 = 480
# level combinations for every claim, with probability
# proportional to the product of Frequency relativities
# multiplies each claim size by the product
# of its severity relativities then rescale all sizes
# by sum(raw) / sum(raw x rel), so the portfolios total claim cost is unchanged
# The covariates only redistribute the claim severities
# according to the relativities.

# claim_size_adj() -> randomly assigns each claim a combo of covariate levels
# then adjust each raw claim severity according to assigned covariate
adj <- claim_size_adj(cov5, claim_sizes_raw, random_seed = covariate_seed)
claim_sizes <- adj$claim_size_adj
cov_levels <- as.data.frame(adj$covariates_data$data, check.names = FALSE)

stopifnot(nrow(cov_levels) == n_claims,
          abs(sum(unlist(claim_sizes)) - sum(unlist(claim_sizes_raw))) <
            1e-6 * sum(unlist(claim_sizes_raw)))
cat("Module 2b: covariates drawn; total claim cost preserved:",
    format(round(sum(unlist(claim_sizes))), big.mark = ","), "\n")

# Module 2c per-claim delay multipliers allowing for product over the 5 factors
notidel_mult <- rep(1, n_claims)
setldel_mult <- rep(1, n_claims)

for (fct in unique(delay_mult$factor)) {
  tab <- delay_mult[delay_mult$factor == fct, ]
  idx <- match(as.character(cov_levels[[fct]]), tab$level)
  notidel_mult <- notidel_mult * tab$notidel_mult[idx]
  setldel_mult <- setldel_mult * tab$setldel_mult[idx]
}

# Module 3, 4 and 7 need multipliers applied
# within SynthETIC's parameter functions

notidel_param_cov <- function(claim_size, occurrence_period, cov_mult) {
  p <- notidel_param(claim_size, occurrence_period)
  c(shape = p[[1]],
    scale = p[[2]] * cov_mult)
}
setldel_param_cov <- function(claim_size, occurrence_period, cov_mult) {
  p <- setldel_param(claim_size, occurrence_period)
  c(shape = p[[1]],
    scale = p[[2]] * cov_mult)
}
param_pmntdel_cov <- function(claim_size,
                              setldel,
                              occurrence_period,
                              cov_mult) {
  p <- param_pmntdel(claim_size, setldel, occurrence_period)
  c(claim_size   = p[["claim_size"]],
    setldel      = p[["setldel"]],
    setldel_mean = p[["setldel_mean"]] * cov_mult)
}

# Module 3 Notification delay

notidel <- claim_notification(n_vector,
                              claim_sizes,
                              paramfun = notidel_param_cov,
                              cov_mult = notidel_mult)

# Module 4 Settlement delay

setldel <- claim_closure(n_vector,
                         claim_sizes,
                         paramfun = setldel_param_cov,
                         cov_mult = setldel_mult)

# Module 5 Number of payments

no_payments <- claim_payment_no(n_vector,
                                claim_sizes,
                                rfun = rmixed_payment_no,
                                claim_size_benchmark_1 = 0.0375 * ref_claim,
                                claim_size_benchmark_2 = 0.075 * ref_claim)

# Module 6 Payment sizes

payment_sizes <- claim_payment_size(n_vector,
                                    claim_sizes,
                                    no_payments,
                                    rfun = rmixed_payment_size)

# Module 7 Payment delays

payment_delays <- claim_payment_delay(n_vector,
                                      claim_sizes,
                                      no_payments,
                                      setldel,
                                      rfun = r_pmntdel,
                                      paramfun = param_pmntdel_cov,
                                      occurrence_period = rep(1:sim_periods,
                                                              times = n_vector),
                                      cov_mult = setldel_mult)

payment_times <- claim_payment_time(n_vector,
                                    occurrence_times,
                                    notidel,
                                    payment_delays)

# Module 8 Inflation

payment_inflated <- claim_payment_inflation(n_vector,
                                            payment_sizes,
                                            payment_times,
                                            occurrence_times,
                                            claim_sizes,
                                            base_inflation_vector,
                                            si_occurrence,
                                            si_payment)


# Generate claim level datasets
claims <- generate_claim_dataset(frequency_vector = n_vector,
                                 occurrence_list = occurrence_times,
                                 claim_size_list = claim_sizes,
                                 notification_list = notidel,
                                 settlement_list = setldel,
                                 no_payments_list = no_payments)

claims$claim_size_raw <- unlist(claim_sizes_raw)

claims$sev_relativity <- claims$claim_size / claims$claim_size_raw
claims$notidel_mult <- notidel_mult
claims$setldel_mult <- setldel_mult
claims <- cbind(claims, cov_levels)



# Transaction level dataset

transactions <- generate_transaction_dataset(
                SynthETIC::claims(frequency_vector = n_vector, # nolint
                                  occurrence_list = occurrence_times,
                                  claim_size_list = claim_sizes,
                                  notification_list = notidel,
                                  settlement_list = setldel,
                                  no_payments_list = no_payments,
                                  payment_size_list = payment_sizes,
                                  payment_delay_list = payment_delays,
                                  payment_time_list = payment_times,
                                  payment_inflated_list = payment_inflated),
                                             adjust = FALSE)

setDT(claims)
setDT(transactions)


# Make triangle for visualisation



triangle_vis <- make_triangle_vis(transactions)



pay_per_claim <- transactions[, .(mean_payment_size = mean(payment_inflated),
                                  last_payment_dev = max(payment_period -
                                                           occurrence_period +
                                                           1L)),
                              by = claim_no]
claims <- merge(claims, pay_per_claim, by = "claim_no", all.x = TRUE)

factor_names <- names(cov5$factors)
impact_by_level <- rbindlist(lapply(factor_names, function(fct) {
  g <- claims[[fct]]
  claims[, .(factor = fct,
             n = .N,
             share = .N / nrow(claims),
             mean_size_raw = mean(claim_size_raw),         # before covariates
             mean_size_adj = mean(claim_size),             # after covariates
             mean_sev_relativity = mean(sev_relativity),
             mean_notidel = mean(notidel),
             mean_notidel_mult = mean(notidel_mult),
             mean_setldel = mean(setldel),
             mean_setldel_mult = mean(setldel_mult),
             mean_no_payment = mean(no_payment),
             mean_payment_size = mean(mean_payment_size),
             share_settled_by_dev8 = mean(last_payment_dev <= 8)),
         by = .(level = as.character(get(fct)))][order(level)]
}))
setcolorder(impact_by_level, c("factor", "level"))

## Development pattern by level: cumulative share of a level's own total paid
## by development quarter (money-weighted, all 40 accident quarters together).
dev_by_level <- rbindlist(lapply(factor_names, function(fct) {
  lev <- as.character(claims[[fct]])[match(transactions$claim_no,
                                           claims$claim_no)]
  rbindlist(lapply(sort(unique(lev)), function(l) {
    m <- as.matrix(make_triangle_vis(transactions[lev == l, ])[, -1])
    cum <- cumsum(colSums(m)) / sum(m)
    data.table(factor = fct, level = l, total_paid = sum(m),
               as.list(setNames(round(cum, 4),
                                paste0("dev", seq_len(sim_periods)))))
  }))
}))

## == Portfolio summary ========================================================
m <- as.matrix(triangle_vis[, -1])
observed <- row(m) + col(m) <= sim_periods + 1
summary_tbl <- data.frame(
  n_claims = n_claims,
  n_payments = nrow(transactions),
  total_claim_size_raw = sum(claims$claim_size_raw),
  total_claim_size_adj = sum(claims$claim_size),
  median_size_raw = median(claims$claim_size_raw),
  median_size_adj = median(claims$claim_size),
  mean_notidel = mean(claims$notidel), env1_target_notidel = 0.4930517,
  mean_setldel = mean(claims$setldel), env1_target_setldel = 6.575582,
  mean_no_payment = mean(claims$no_payment),
  triangle_total = sum(m),
  pct_of_triangle_observed = sum(m[observed]) / sum(m)
)
cat("\n==== Portfolio summary ====\n")
print(t(summary_tbl))
cat("\n==== Impact by covariate level ====\n")
print(impact_by_level[, .(factor, level, share = round(share, 3),
                          size_raw = round(mean_size_raw),
                          size_adj = round(mean_size_adj),
                          notidel = round(mean_notidel, 3),
                          setldel = round(mean_setldel, 2),
                          n_pay = round(mean_no_payment, 2),
                          pay_size = round(mean_payment_size),
                          settled_by_dev8 = round(share_settled_by_dev8, 3))])


## ===== Part 6: write outputs =================================================
output_dir <- here::here(paths$raw, "claim-simulation")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
fwrite(claims,          file.path(output_dir, "claims.csv"))
fwrite(transactions,    file.path(output_dir, "transactions.csv"))
fwrite(triangle_vis,        file.path(output_dir, "triangle.csv"))
fwrite(impact_by_level, file.path(output_dir, "impact_by_level.csv"))
fwrite(dev_by_level,    file.path(output_dir, "development_by_level.csv"))
fwrite(summary_tbl,     file.path(output_dir, "summary.csv"))
fwrite(freq5,           file.path(output_dir, "cov_freq_relativities.csv"))
fwrite(sev5,            file.path(output_dir, "cov_sev_relativities.csv"))
fwrite(delay_mult,      file.path(output_dir, "delay_multipliers.csv"))
saveRDS(cov5,           file.path(output_dir, "covariates_5factor.rds"))
