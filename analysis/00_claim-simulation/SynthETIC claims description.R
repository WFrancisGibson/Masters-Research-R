##########################################
#########  The SynthETIC claims portfolio: description
#########  Avanzi, Taylor, Wang & Wong (2021); tables and figures after
#########  Gabrielli & Wuthrich (2018), Risks 6(2):29, Tables 3, 5, 6, 7 and
#########  Figures A2-A3
##########################################

source(here::here("analysis", "00_setup.R"))
stopifnot(cfg$data$generator == "synthetic")
tab_dir <- file.path(paths$tables, "00_claim-simulation/data-description")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

n <- cfg$data$n_dev          # 20 accident years; valuation: end of year n
units <- cfg$data$scale      # amounts in millions
ref_claim <- 200000          # SynthETIC's claim size scale (simulation script)

##########################################
#########  load data
##########################################

## claims and payments of "SynthETIC claims simulation.R"; 'true' quantities
## come from the full simulation and are not known at the valuation date
port <- synthetic_portfolio(file.path(paths$raw, cfg$data$dir), n)
claims <- port$claims
trans <- port$trans
claims$AY <- claims$occurrence_period

## incremental and cumulative n x n triangles of the nominal payments, as in
## the Mack script: the payments after development year n (sets$tail) are in
## no triangle
sets <- triangle_sets(trans, n)
tri <- sets$full
cum <- t(apply(tri, 1, cumsum))
stopifnot(abs(sum(sets$upper, na.rm = TRUE) / sum(claims$paid) - 1) < 1e-10)

##########################################
#########  tables: portfolio, accident years, claim sizes and delays
##########################################

## portfolio at the valuation date; the true outstanding = the lower triangle
## (the true reserves of the model scripts) + the payments after development
## year n
portfolio <- c(
  "claims" = nrow(claims),
  "payments" = nrow(trans),
  "claim cost in constant values (millions)" = sum(claims$claim_size) / units,
  "nominal ultimate (millions)" = sum(claims$ultimate) / units,
  "paid to the valuation date (millions)" = sum(claims$paid) / units,
  "paid to the valuation date (% of the ultimate)" =
    100 * sum(claims$paid) / sum(claims$ultimate),
  "true outstanding (millions)" = sum(claims$outstanding) / units,
  setNames(c(sum(sets$test, na.rm = TRUE), sum(sets$tail)) / units,
           paste("true outstanding,",
                 c("development years 1 to", "after development year"),
                 n,
                 "(millions)")),
  "claims closed" = sum(claims$status == "closed"),
  "claims open" = sum(claims$status == "open"),
  "claims not yet reported" = sum(claims$status == "unreported"),
  "payments to the valuation date" = sum(trans$payment_period <= n),
  "payments after the valuation date" = sum(trans$payment_period > n),
  "mean claim size (constant values)" = mean(claims$claim_size),
  "median claim size (constant values)" = median(claims$claim_size),
  "mean notification delay (years)" = mean(claims$notidel),
  "mean settlement delay (years)" = mean(claims$setldel),
  "mean number of payments" = mean(claims$no_payment),
  "amount-weighted mean payment lag (years)" =
    sum(claims$lag_paid) / sum(claims$ultimate)
)
portfolio <- data.frame(quantity = names(portfolio),
                        value = unname(portfolio))
data.frame(quantity = portfolio$quantity, value = round(portfolio$value, 3))

## accident years (true): claims, claim cost in constant values, nominal
## ultimate and its paid and outstanding parts; amounts in millions
by_ay <- rollup(claims,
                j = .(claims = .N,
                      claim_cost = sum(claim_size) / units,
                      mean_size = mean(claim_size),
                      median_size = median(claim_size),
                      max_size = max(claim_size) / units,
                      ultimate = sum(ultimate) / units,
                      paid = sum(paid) / units,
                      outstanding = sum(outstanding) / units),
                by = "AY")
by_ay$paid_pct <- 100 * by_ay$paid / by_ay$ultimate
by_ay$nominal_to_constant <- by_ay$ultimate / by_ay$claim_cost
by_ay$AY <- ifelse(is.na(by_ay$AY), "total", by_ay$AY)
cbind(by_ay[, 1:2], round(by_ay[, -(1:2)], 1))

## claim sizes (true): before the covariates (raw), after them, and the
## nominal ultimate of the claim
sizes <- list(raw = claims$claim_size_raw,
              adjusted = claims$claim_size,
              nominal = claims$ultimate)
probs <- c(0, 0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99, 0.999, 1)
size_dist <- data.frame(
  statistic = c("minimum", "1%", "5%", "25%", "median", "75%", "95%", "99%",
                "99.9%", "maximum", "mean", "coefficient of variation"),
  sapply(sizes, function(x) {
    unname(c(quantile(x, probs), mean(x), sd(x) / mean(x)))
  })
)
cbind(statistic = size_dist$statistic, round(size_dist[, -1], 2))

## concentration: share of the cost in the largest claims, Gini coefficient
top <- c(0.001, 0.01, 0.05, 0.1, 0.5)
concentration <- data.frame(
  statistic = c(paste0("largest ", 100 * top, "% of claims (% of cost)"),
                "Gini coefficient"),
  sapply(sizes[1:2], function(x) {
    x <- sort(x, decreasing = TRUE)
    c(100 * cumsum(x)[ceiling(top * length(x))] / sum(x), gini(x))
  })
)
cbind(statistic = concentration$statistic, round(concentration[, -1], 3))

## the ten largest claims; raw_rank: rank of the size before the covariates
claims$raw_rank <- rank(-claims$claim_size_raw)
largest <- claims[order(-claim_size)][1:10,
                                      c("claim_no", "AY", "claim_size",
                                        "ultimate", "claim_size_raw",
                                        "raw_rank", "sev_relativity",
                                        "setldel", "no_payment",
                                        port$features, "status"),
                                      with = FALSE]
largest

## delays in years (true): notification from the occurrence, settlement from
## the notification, and their sum
delays <- list(notification = claims$notidel,
               settlement = claims$setldel,
               occurrence_to_settlement = claims$notidel + claims$setldel)
probs <- c(0.01, 0.25, 0.5, 0.75, 0.9, 0.99, 1)
delay_dist <- data.frame(
  statistic = c("mean", "coefficient of variation", "1%", "25%", "median",
                "75%", "90%", "99%", "maximum", "% over 1 year",
                "% over 5 years"),
  sapply(delays, function(x) {
    unname(c(mean(x), sd(x) / mean(x), quantile(x, probs),
             100 * mean(x > 1), 100 * mean(x > 5)))
  })
)
cbind(statistic = delay_dist$statistic, round(delay_dist[, -1], 4))

##########################################
#########  tables: reporting and claim status (Risks Tables 3 and 6)
##########################################

## Table 3: reported claims by accident year and reporting delay T (years);
## observed at the valuation date: AY + T <= n. The last column, T = n,
## holds the claims reported n years or more after the accident year (data
## set long_reporting): not reported at the valuation date in any year
n_rep <- claims[, .N, keyby = .(AY, rep_delay = pmin(rep_delay, n))]
tri_n <- matrix(0, n, n + 1, dimnames = list(AY = 1:n, T = 0:n))
tri_n[cbind(n_rep$AY, n_rep$rep_delay + 1)] <- n_rep$N
t_max <- max(n_rep$rep_delay)
reported <- data.frame(AY = 1:n,
                       upper_triangle(tri_n)[, 1:(t_max + 1)],
                       reported = rowSums(upper_triangle(tri_n), na.rm = TRUE),
                       unreported = rowSums(lower_triangle(tri_n),
                                            na.rm = TRUE),
                       check.names = FALSE)
names(reported)[2:(t_max + 2)] <- paste0("T", 0:t_max)
reported

## Table 6: chain-ladder predicted IBNYR claim counts and Mack's sqrt(msep)
## against the true counts (the factors after T = 7 are 1: Mack warns), on
## the n x n triangle: the claims of the column T = n are in no triangle, as
## the payments after development year n
mack_n <- suppressWarnings(nncl_mack(t(apply(tri_n[, 1:n], 1, cumsum))))
ibnyr <- data.frame(AY = as.character(1:n),
                    reported = mack_n$by_origin$latest,
                    CL_IBNYR = mack_n$by_origin$ibnr,
                    msep_sqrt = mack_n$by_origin$se,
                    true_IBNYR = mack_n$by_origin$true)
ibnyr <- rbind(ibnyr,
               data.frame(AY = "total",
                          reported = sum(ibnyr$reported),
                          CL_IBNYR = sum(ibnyr$CL_IBNYR),
                          msep_sqrt = mack_n$total_se,
                          true_IBNYR = sum(ibnyr$true_IBNYR)))
cbind(ibnyr[, 1:2], round(ibnyr[, 3:4], 2), true_IBNYR = ibnyr$true_IBNYR)

## status at the valuation date: closed (settled), open (reported, not
## settled) and not yet reported, and the true outstanding of the last two
status_ay <- rollup(claims,
                    j = .(claims = .N,
                          closed = sum(status == "closed"),
                          open = sum(status == "open"),
                          unreported = sum(status == "unreported"),
                          open_no_payment = sum(status == "open" & paid == 0),
                          os_open = sum(outstanding[status == "open"]) / units,
                          os_unreported =
                            sum(outstanding[status == "unreported"]) / units),
                    by = "AY")
status_ay$AY <- ifelse(is.na(status_ay$AY), "total", status_ay$AY)
cbind(status_ay[, 1:6], round(status_ay[, 7:8], 1))

## what the valuation date hides: the closed claims are the small and fast
## ones (true means by status; all accident years and the latest one)
status_cols <- quote(.(claims = .N,
                       mean_size = mean(claim_size),
                       mean_ultimate = mean(ultimate),
                       mean_notidel = mean(notidel),
                       mean_setldel = mean(setldel),
                       mean_no_payment = mean(no_payment)))
censoring <- rbind(
  cbind(accident_years = "all", claims[, eval(status_cols), keyby = status]),
  cbind(accident_years = as.character(n),
        claims[AY == n, eval(status_cols), keyby = status])
)
cbind(censoring[, 1:3], round(censoring[, 4:8], 3))

##########################################
#########  tables: reporting delay, number of payments and claim size
##########################################

## by reporting delay T and by number of payments (Risks Figs. A2-A3 as
## numbers); 15 = 15 or more payments
by_delay <- claims[, .(claims = .N,
                       mean_size = mean(claim_size),
                       median_size = median(claim_size),
                       mean_no_payment = mean(no_payment),
                       mean_setldel = mean(setldel)),
                   keyby = rep_delay]
round(by_delay, 2)
by_payments <- claims[, .(claims = .N,
                          mean_size = mean(claim_size),
                          median_size = median(claim_size),
                          mean_setldel = mean(setldel),
                          cost_pct = 100 * sum(claim_size) /
                            sum(claims$claim_size)),
                      keyby = .(no_payment = pmin(no_payment, 15))]
round(by_payments, 2)

## by claim size band; the first two bands are those of SynthETIC's number
## of payments (0.0375 and 0.075 times the claim size scale)
size_breaks <- c(0, 0.0375, 0.075, 0.25, 0.75, 2.5, 10, Inf) * ref_claim
size_labels <- c("up to 7,500", "7,500 to 15,000", "15,000 to 50,000",
                 "50,000 to 150,000", "150,000 to 500,000",
                 "500,000 to 2 million", "over 2 million")
claims$size_band <- cut(claims$claim_size, size_breaks, labels = size_labels)
by_size <- claims[, .(claims = .N,
                      claims_pct = 100 * .N / nrow(claims),
                      cost_pct = 100 * sum(claim_size) /
                        sum(claims$claim_size),
                      mean_notidel = mean(notidel),
                      mean_setldel = mean(setldel),
                      mean_no_payment = mean(no_payment),
                      outstanding_pct = 100 * sum(outstanding) /
                        sum(claims$outstanding),
                      paid_pct = 100 * sum(paid) / sum(ultimate)),
                  keyby = size_band]
cbind(by_size[, 1:2], round(by_size[, 3:9], 2))

##########################################
#########  tables: triangles and development (Risks Tables 5 and 7)
##########################################

## observed incremental and cumulative payments (Table 5), in millions; the
## last column of the cumulative table: the true ultimate at development
## year n
round(upper_triangle(tri) / units, 1)
tri_cum <- data.frame(AY = 1:n,
                      upper_triangle(cum) / units,
                      ultimate = cum[, n] / units,
                      check.names = FALSE)
round(tri_cum, 1)

## development: chain-ladder factors f_j from development year j to j + 1 on
## the observed triangle and on the full simulation (true), the range of the
## observed individual factors C_{i,j+1} / C_{i,j}, and the % paid by
## development year j: of the chain-ladder ultimate at development year n
## (100 in year n) and of the true nominal ultimate (the rest to 100 in year
## n is paid later)
f_obs <- cl_factors(cum)
link <- cum[, -1] / cum[, -n]
link[row(link) + col(link) > n] <- NA          # the observed ones only
development <- data.frame(
  dev = 1:n,
  cl_factor = c(f_obs, NA),
  cl_factor_true = c(colSums(cum[, -1]) / colSums(cum[, -n]), NA),
  link_min = c(apply(link, 2, min, na.rm = TRUE), NA),
  link_max = c(apply(link, 2, max, na.rm = TRUE), NA),
  paid_pct_cl = 100 / rev(cumprod(rev(c(f_obs, 1)))),
  paid_pct_true = 100 * cumsum(colSums(tri)) / sum(claims$ultimate)
)
development$incr_pct_true <- diff(c(0, development$paid_pct_true))
round(development, 4)

## payments by calendar year: nominal, in constant values and the inflation
## index they carry (2% a year from time 0; SynthETIC inflates a payment
## after development year n only to the end of that year); after year n: the
## run-off of the true outstanding; the years after n + 10 together
last <- n + 11
calendar <- trans[, .(payments = .N,
                      nominal = sum(payment_inflated) / units,
                      constant = sum(payment_size) / units),
                  keyby = .(calendar_year = pmin(payment_period, last))]
calendar$index <- calendar$nominal / calendar$constant
calendar$outstanding_pct <- ifelse(calendar$calendar_year > n,
                                   100 * calendar$nominal * units /
                                     sum(claims$outstanding),
                                   NA)
calendar$calendar_year <- ifelse(calendar$calendar_year == last,
                                 paste0(last, "+"),
                                 calendar$calendar_year)
cbind(calendar[, 1:2], round(calendar[, 3:6], 3))

## payments after development year n (in no triangle and no model)
late <- trans[dev > n,
              .(claims = uniqueN(claim_no),
                payments = .N,
                amount = sum(payment_inflated) / units),
              keyby = .(AY = occurrence_period)]
late$ultimate_pct <- 100 * late$amount / by_ay$ultimate[late$AY]
round(late, 3)

## Table 7: chain-ladder reserves and Mack's sqrt(msep) against the true
## outstanding payments of the triangle (as output/tables/01_Mack), millions
mack <- nncl_mack(cum)
reserves <- data.frame(AY = as.character(1:n),
                       paid = mack$by_origin$latest,
                       CL_reserves = mack$by_origin$ibnr,
                       msep_sqrt = mack$by_origin$se,
                       true_reserves = mack$by_origin$true)
reserves <- rbind(reserves,
                  data.frame(AY = "total",
                             paid = sum(reserves$paid),
                             CL_reserves = sum(reserves$CL_reserves),
                             msep_sqrt = mack$total_se,
                             true_reserves = sum(reserves$true_reserves)))
reserves[, -1] <- reserves[, -1] / units
reserves$error <- reserves$CL_reserves - reserves$true_reserves
cbind(AY = reserves$AY, round(reserves[, -1], 1))

fwrite(portfolio, file.path(tab_dir, "synthetic_data_t01_portfolio.csv"))
fwrite(by_ay, file.path(tab_dir, "synthetic_data_t02_accident_years.csv"))
fwrite(size_dist, file.path(tab_dir, "synthetic_data_t03_claim_sizes.csv"))
fwrite(concentration,
       file.path(tab_dir, "synthetic_data_t04_concentration.csv"))
fwrite(largest, file.path(tab_dir, "synthetic_data_t05_largest_claims.csv"))
fwrite(delay_dist, file.path(tab_dir, "synthetic_data_t06_delays.csv"))
fwrite(reported, file.path(tab_dir, "synthetic_data_t07_reported_claims.csv"))
fwrite(ibnyr, file.path(tab_dir, "synthetic_data_t08_ibnyr_counts.csv"))
fwrite(status_ay, file.path(tab_dir, "synthetic_data_t09_claim_status.csv"))
fwrite(censoring, file.path(tab_dir, "synthetic_data_t10_censoring.csv"))
fwrite(by_delay,
       file.path(tab_dir, "synthetic_data_t11_by_reporting_delay.csv"))
fwrite(by_payments,
       file.path(tab_dir, "synthetic_data_t12_by_number_of_payments.csv"))
fwrite(by_size, file.path(tab_dir, "synthetic_data_t13_by_claim_size.csv"))
fwrite(data.frame(AY = 1:n, upper_triangle(tri) / units, check.names = FALSE),
       file.path(tab_dir, "synthetic_data_t14_incremental_payments.csv"))
fwrite(tri_cum,
       file.path(tab_dir, "synthetic_data_t15_cumulative_payments.csv"))
fwrite(development, file.path(tab_dir, "synthetic_data_t16_development.csv"))
fwrite(calendar, file.path(tab_dir, "synthetic_data_t17_calendar_years.csv"))
fwrite(late, file.path(tab_dir, "synthetic_data_t18_late_payments.csv"))
fwrite(reserves, file.path(tab_dir, "synthetic_data_t19_cl_reserves.csv"))

##########################################
#########  figures
##########################################

fig_dir <- file.path(paths$figures, "00_claim-simulation/data-description")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

## Fig. 1: claims, claim cost and claim size by accident year (true)
ay <- by_ay[1:n]
ay_fig <- data.frame(
  panel = rep(c("(a) number of claims",
                "(b) claim cost (millions)",
                "(c) claim size (constant values)"),
              times = c(n, 2 * n, 2 * n)),
  series = rep(c("claims", "nominal ultimate", "constant values", "mean",
                 "median"),
               each = n),
  x = rep(1:n, 5),
  value = c(ay$claims, ay$ultimate, ay$claim_cost, ay$mean_size,
            ay$median_size)
)
save_figure("SynthETIC data Fig 01 accident years.png",
            series_plot(ay_fig, "accident year", end_labels = TRUE),
            fig_dir,
            height = 14)

## Fig. 2: claim size before and after the covariates (density of the log)
size_fig <- data.frame(
  series = factor(rep(c("before the features", "after the features"),
                      each = nrow(claims)),
                  levels = c("before the features", "after the features")),
  size = c(claims$claim_size_raw, claims$claim_size)
)
save_figure("SynthETIC data Fig 02 claim size distribution.png",
            ggplot(size_fig, aes(x = size, linetype = series)) +
              geom_line(stat = "density") +
              scale_x_log10(labels = scales::label_comma()) +
              labs(x = "claim size (log scale)", y = "density") +
              description_theme(),
            fig_dir,
            height = 8,
            width = 12)

## Fig. 3: Lorenz curves: share of the cost in the smallest claims
lorenz <- rbindlist(lapply(names(sizes)[1:2], function(s) {
  x <- sort(sizes[[s]])
  k <- round(seq(0, length(x), length.out = 501))
  data.frame(series = s,
             claims = k / length(x),
             cost = c(0, cumsum(x))[k + 1] / sum(x))
}))
lorenz$series <- factor(lorenz$series,
                        levels = c("raw", "adjusted"),
                        labels = levels(size_fig$series))
save_figure("SynthETIC data Fig 03 Lorenz curves.png",
            ggplot(lorenz, aes(x = claims, y = cost, linetype = series)) +
              geom_abline(colour = "grey60") +
              geom_line() +
              coord_fixed() +
              labs(x = "share of the claims, smallest first",
                   y = "share of the claim cost") +
              description_theme(),
            fig_dir,
            height = 11,
            width = 12)

## Fig. 4: distribution functions of the two delays
p_grid <- seq(0.001, 0.999, by = 0.002)
delay_fig <- rbind(
  data.frame(series = "notification delay",
             delay = quantile(claims$notidel, p_grid),
             p = p_grid),
  data.frame(series = "settlement delay",
             delay = quantile(claims$setldel, p_grid),
             p = p_grid)
)
save_figure("SynthETIC data Fig 04 delays.png",
            ggplot(delay_fig, aes(x = delay, y = p, linetype = series)) +
              geom_line() +
              scale_x_log10(breaks = 10^(-4:1),
                            labels = c("0.0001", "0.001", "0.01", "0.1", "1",
                                       "10")) +
              labs(x = "delay in years (log scale)", y = "share of claims") +
              description_theme(),
            fig_dir,
            height = 8,
            width = 12)

## Fig. 5: cumulative payments in % of the true nominal ultimate by accident
## year: after the valuation date (grey) and, drawn on top, observed
## (black); points: the chain-ladder pattern
ult_ay <- ay$ultimate * units
dev_fig <- data.frame(AY = as.vector(row(cum)),
                      dev = as.vector(col(cum)),
                      value = as.vector(100 * cum / ult_ay))
series <- c("observed", "after the valuation date (true)")
dev_fig <- rbind(
  data.frame(dev_fig[dev_fig$AY + dev_fig$dev <= n + 1, ], series = series[1]),
  data.frame(dev_fig[dev_fig$AY + dev_fig$dev >= n + 1, ], series = series[2])
)
dev_fig$series <- factor(dev_fig$series, levels = series)
save_figure("SynthETIC data Fig 05 development by accident year.png",
            ggplot(dev_fig, aes(x = dev, y = value)) +
              geom_line(data = dev_fig[dev_fig$series == series[2], ],
                        aes(group = AY, colour = series),
                        linewidth = 0.3) +
              geom_line(data = dev_fig[dev_fig$series == series[1], ],
                        aes(group = AY, colour = series),
                        linewidth = 0.3) +
              geom_point(data = development,
                         aes(y = paid_pct_cl, shape = "chain-ladder pattern"),
                         size = 1.2) +
              scale_colour_manual(values = setNames(c("black", "grey65"),
                                                    series),
                                  breaks = series) +
              scale_x_continuous(breaks = seq(1, n, by = 2)) +
              labs(x = "development year",
                   y = "cumulative payments (% of the true ultimate)") +
              description_theme(),
            fig_dir,
            height = 9)

## Fig. 6: the triangle: incremental payments in % of the true nominal
## ultimate of the accident year; the staircase is the valuation date
tri_fig <- data.frame(AY = as.vector(row(tri)),
                      dev = as.vector(col(tri)),
                      value = as.vector(100 * tri / ult_ay))
stair <- data.frame(x = rep(n + 1.5 - 1:n, each = 2),
                    y = as.vector(rbind(1:n - 0.5, 1:n + 0.5)))
save_figure("SynthETIC data Fig 06 triangle.png",
            ggplot(tri_fig, aes(x = dev, y = AY, fill = value)) +
              geom_tile() +
              geom_path(data = stair,
                        aes(x = x, y = y),
                        inherit.aes = FALSE,
                        linewidth = 0.5) +
              scale_fill_gradient(low = "white",
                                  high = "black",
                                  transform = "sqrt",
                                  breaks = c(0.1, 1, 5, 15, 30),
                                  labels = c("0.1", "1", "5", "15", "30"),
                                  name = "% of the ultimate (root scale)") +
              scale_x_continuous(breaks = 1:n, expand = c(0, 0)) +
              scale_y_reverse(breaks = 1:n, expand = c(0, 0)) +
              coord_fixed() +
              labs(x = "development year", y = "accident year") +
              description_theme() +
              theme(panel.grid = element_blank(),
                    legend.title = element_text(),
                    legend.key.width = grid::unit(1.2, "cm")),
            fig_dir,
            height = 13.5,
            width = 12)

## Fig. 7: observed individual development factors by accident year against
## the chain-ladder factor (dashed), development years 1 to 6
steps <- paste("development year", 1:6, "to", 2:7)
link_fig <- data.frame(AY = as.vector(row(link)),
                       panel = steps[as.vector(col(link))],
                       value = as.vector(link))
link_fig <- link_fig[which(col(link) <= 6 & !is.na(link)), ]
save_figure("SynthETIC data Fig 07 development factors.png",
            ggplot(link_fig, aes(x = AY, y = value)) +
              geom_hline(data = data.frame(panel = steps, value = f_obs[1:6]),
                         aes(yintercept = value),
                         linetype = "dashed") +
              geom_point(size = 0.9) +
              facet_wrap(~panel, scales = "free_y") +
              labs(x = "accident year", y = "development factor") +
              description_theme(),
            fig_dir,
            height = 10)

## Fig. 8: payments by calendar year, nominal and in constant values; the
## vertical line is the valuation date
cal <- trans[, .(nominal = sum(payment_inflated) / units,
                 constant = sum(payment_size) / units),
             keyby = payment_period]
cal_fig <- data.frame(panel = "",
                      series = rep(c("nominal", "constant values"),
                                   each = nrow(cal)),
                      x = rep(cal$payment_period, 2),
                      value = c(cal$nominal, cal$constant))
save_figure("SynthETIC data Fig 08 calendar years.png",
            series_plot(cal_fig, "calendar year", "payments (millions)") +
              geom_vline(xintercept = n + 0.5, colour = "grey60") +
              theme(strip.background = element_blank(),
                    strip.text = element_blank()),
            fig_dir,
            height = 8,
            width = 12)

## Fig. 9: the claims not closed at the valuation date and their true
## outstanding, the latest 10 accident years (11 to 20)
groups <- c("open, payments made", "open, no payment yet", "not yet reported")
claims$open_group <- factor(ifelse(claims$status == "unreported",
                                   groups[3],
                                   ifelse(claims$paid == 0,
                                          groups[2],
                                          groups[1])),
                            levels = groups)
open_ay <- claims[status != "closed" & AY > n - 10,
                  .(claims = .N, outstanding = sum(outstanding) / units),
                  keyby = .(AY, open_group)]
open_fig <- data.frame(
  panel = rep(c("(a) number of claims", "(b) true outstanding (millions)"),
              each = nrow(open_ay)),
  AY = factor(rep(open_ay$AY, 2)),
  group = rep(open_ay$open_group, 2),
  value = c(open_ay$claims, open_ay$outstanding)
)
save_figure("SynthETIC data Fig 09 open and unreported claims.png",
            ggplot(open_fig, aes(x = AY, y = value, fill = group)) +
              geom_col(colour = "black", linewidth = 0.15) +
              facet_wrap(~panel, scales = "free_y") +
              scale_fill_manual(values = c("grey88", "grey55", "grey10")) +
              scale_y_continuous(labels = scales::label_comma()) +
              labs(x = "accident year", y = NULL) +
              description_theme(),
            fig_dir,
            height = 9)

## Fig. 10: true outstanding (bars) and chain-ladder reserves with two
## standard errors (Mack) by accident year, in millions; the latest 6
## accident years (15 to 20) have their own panel and scale
split_ay <- n - 5
panels <- paste("accident years", c(2, split_ay), "to", c(split_ay - 1, n))
res_fig <- data.frame(reserves[2:n, ],
                      panel = factor(ifelse(2:n < split_ay,
                                            panels[1],
                                            panels[2]),
                                     levels = panels))
res_fig$AY <- factor(res_fig$AY, levels = 2:n)
save_figure("SynthETIC data Fig 10 chain-ladder reserves.png",
            ggplot(res_fig, aes(x = AY)) +
              geom_col(aes(y = true_reserves, fill = "true outstanding")) +
              geom_pointrange(aes(y = CL_reserves,
                                  ymin = CL_reserves - 2 * msep_sqrt,
                                  ymax = CL_reserves + 2 * msep_sqrt,
                                  shape = "chain ladder +/- 2 sqrt(msep)"),
                              size = 0.25) +
              facet_wrap(~panel, scales = "free") +
              scale_fill_manual(values = "grey75") +
              scale_y_continuous(labels = scales::label_comma()) +
              labs(x = "accident year", y = "millions") +
              description_theme(),
            fig_dir,
            height = 9)

## Fig. 11: by reporting delay T (Risks Fig. A2); dashed: portfolio average
panels <- c("(a) log number of claims",
            "(b) average claim size",
            "(c) average number of payments")
delay_bars <- data.frame(panel = rep(panels, each = nrow(by_delay)),
                         label = rep(by_delay$rep_delay, 3),
                         value = c(log(by_delay$claims),
                                   by_delay$mean_size,
                                   by_delay$mean_no_payment))
save_figure("SynthETIC data Fig 11 by reporting delay.png",
            panel_bar_plot(delay_bars,
                           "reporting delay T (years)",
                           data.frame(panel = panels[2:3],
                                      value = c(mean(claims$claim_size),
                                                mean(claims$no_payment)))),
            fig_dir,
            height = 7)

## Fig. 12: by number of payments (Risks Fig. A3; 15 = 15 or more)
panels <- c("(a) log number of claims",
            "(b) average claim size",
            "(c) average settlement delay (years)")
payment_bars <- data.frame(panel = rep(panels, each = nrow(by_payments)),
                           label = rep(by_payments$no_payment, 3),
                           value = c(log(by_payments$claims),
                                     by_payments$mean_size,
                                     by_payments$mean_setldel))
save_figure("SynthETIC data Fig 12 by number of payments.png",
            panel_bar_plot(payment_bars,
                           "number of payments",
                           data.frame(panel = panels[2:3],
                                      value = c(mean(claims$claim_size),
                                                mean(claims$setldel)))),
            fig_dir,
            height = 7)
