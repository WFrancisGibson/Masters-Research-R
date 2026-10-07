##########################################
#########  checks of the NN chain ladder functions (R/nn_chain_ladder.R)
#########  Wuthrich (2018), EAJ 8:407-436
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(data.table)
library(ChainLadder)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

## toy portfolio: one LoB, I = 4 accident years, development years 0..3;
## cells (accident year, feature) with cumulative payments, NA = not observed
toy <- function(cum, ay) {
  cum[ay + col(cum) - 1 > 4] <- NA
  vol <- rowsum(cum, ay)                         # the LoB triangle
  list(cum = cum,
       ay = ay,
       vol = vol,
       c_diag = cum[cbind(seq_along(ay), 5 - ay)])  # C_{i,I-i}(x)
}

test_that("(5.1) with the CL factors gives the CL reserves (Prop. 2.2)", {
  set.seed(1)
  cum <- t(apply(matrix(runif(32, 1, 10), 8, 4), 1, cumsum))
  d <- toy(cum, ay = rep(1:4, 2))
  f <- sapply(1:3, function(j) {
    sum(d$vol[1:(4 - j), j + 1]) / sum(d$vol[1:(4 - j), j])
  })
  f_prod <- sapply(4 - d$ay, function(m) prod(f[seq_len(3 - m) + m]))
  # no zero claims features: every zero set is empty, part 2 = 0
  ult_zero <- matrix(c(0, sapply(2:4, function(i) {
    nncl_zero_claims_factors(d$cum, d$ay, d$vol, i)$ultimate
  })), nrow = 1)
  expect_equal(ult_zero, matrix(0, 1, 4))
  res <- nncl_reserves(rep(1, 8), d$ay, d$c_diag, f_prod, ult_zero)
  tri <- as.triangle(d$vol)
  cl <- predict(chainladder(tri))[, 4] - getLatestCumulative(tri)
  expect_equal(res$reserve, as.numeric(cl))
})

test_that("zero claims factors of Section 4.2 match a hand calculation", {
  cum <- rbind(c(5, 8, 9, 9),       # AY 1, x = a
               c(0, 0, 2, 3),       # AY 1, x = b: zero at development year 1
               c(4, 6, 7, 7),       # AY 2, x = a
               c(0, 0, 1, 1),       # AY 2, x = b: zero at development year 1
               c(3, 5, 6, 6),
               c(0, 0, 1, 1),
               c(2, 3, 4, 4),
               c(0, 1, 1, 1))
  d <- toy(cum, ay = rep(1:4, each = 2))
  # accident year i = 3, m = I - i = 1: g_1 = (2 + 1) / (8 + 6), g_2 = 3 / 2
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3)
  expect_equal(z$factors$g, c(3 / 14, 3 / 2))
  expect_equal(z$ultimate, 5 * 3 / 14 * 3 / 2)
  # no development of the zero set in accident year 1: g_2 = 0/0 = 1
  d$cum[2, ] <- 0
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3)
  expect_equal(z$factors$g, c(1 / 14, 1))
  # a first payment at development year 3: g_2 = 3/0 takes the pooled ratio
  d$cum[2, 4] <- 3
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3, g_pooled = c(NA, 2))
  expect_equal(z$factors$g, c(1 / 14, 2))
  expect_equal(z$factors$pooled, c(FALSE, TRUE))
  expect_equal(z$ultimate, 5 / 14 * 2)
})

## one portfolio (SynthETIC), I = 4: three cells in accident year 1 and two
## in the others; x = b pays first in development year 3, x = c in year 1
toy_one_lob <- function() {
  cum <- rbind(c(5, 8, 9, 9),       # AY 1, x = a
               c(0, 0, 0, 3),       # AY 1, x = b: zero up to year 2
               c(0, 2, 4, 6),       # AY 1, x = c: zero in year 0
               c(4, 6, 7, 7),       # AY 2, x = a
               c(0, 0, 1, 1),       # AY 2, x = b: zero up to year 1
               c(3, 5, 6, 6),
               c(0, 1, 1, 1),
               c(2, 3, 4, 4),
               c(0, 1, 1, 1))
  toy(cum, ay = c(1, 1, 1, 2, 2, 3, 3, 4, 4))
}

test_that("one LoB: a zero denominator is pooled over the accident years", {
  d <- toy_one_lob()
  # accident year i = 3 (m = 1): g_1 = (0 + 1) / (10 + 6), g_2 = 3 / 0;
  # i = 4 (m = 0): g_0 = 3 / 12, g_1 = 5 / 2, g_2 = (3 + 6) / (0 + 4);
  # i = 2 (m = 2): g_2 = 3 / 13, a first factor (total volume), not pooled
  z <- nncl_zero_claims_factors(d$cum, d$ay, d$vol, 3)
  expect_equal(z$factors$g, c(1 / 16, Inf))
  # g_2 pooled over the zero sets of i = 3 and 4: (3 + 9) / (0 + 4)
  z <- nncl_zero_claims(d$cum, d$ay, rep(1, 9))
  f <- z$factors
  expect_equal(f$g[f$i == 3], c(1 / 16, 3))
  expect_equal(f$g[f$i == 4], c(3 / 12, 5 / 2, 9 / 4))
  expect_equal(f$pooled_over,
               c(NA, NA, "accident years", NA, NA, NA))
  expect_equal(z$ult_zero,
               matrix(c(0, 8 * 3 / 13, 6 / 16 * 3, 2 * 3 / 12 * 5 / 2 * 9 / 4),
                      nrow = 1))
  # the reserves (5.1) are finite: part 1 = 0 with factor products of 1
  res <- nncl_reserves(rep(1, 6),
                       d$ay[-(1:3)],
                       d$c_diag[-(1:3)],
                       rep(1, 6),
                       z$ult_zero)
  expect_equal(res$reserve, z$ult_zero[1, 2:4])
})

test_that("several LoBs: a zero denominator is pooled over the LoBs", {
  d1 <- toy_one_lob()
  cum2 <- rbind(c(6, 9, 10, 10),
                c(0, 0, 2, 5),
                c(5, 7, 8, 8),
                c(0, 0, 1, 1),
                c(4, 6, 7, 7),
                c(0, 1, 1, 1),
                c(3, 4, 5, 5),
                c(0, 1, 1, 1))
  d2 <- toy(cum2, ay = rep(1:4, each = 2))
  z <- nncl_zero_claims(rbind(d1$cum, d2$cum),
                        c(d1$ay, d2$ay),
                        rep(1:2, c(9, 8)))
  f <- z$factors
  # LoB 2, i = 3: g_1 = (2 + 1) / (9 + 7), g_2 = 5 / 2; LoB 1 takes the
  # pooled g_2 = (3 + 5) / (0 + 2)
  expect_equal(f$g[f$LoB == 2 & f$i == 3], c(3 / 16, 5 / 2))
  expect_equal(f$g[f$LoB == 1 & f$i == 3], c(1 / 16, 4))
  # LoB 2, i = 4: g_0 = 1 / 15, g_1 = 3 / 0, g_2 = 5 / 2; it takes the
  # pooled g_1 = (5 + 3) / (2 + 0)
  expect_equal(f$g[f$LoB == 2 & f$i == 4], c(1 / 15, 4, 5 / 2))
  expect_equal(which(f$pooled), c(3, 11))
  expect_equal(f$pooled_over[c(3, 4, 11)], c("LoB", NA, "LoB"))
  expect_equal(z$ult_zero[, 3], c(6 / 16 * 4, 7 * 3 / 16 * 5 / 2))
  expect_equal(z$ult_zero[2, 4], 3 / 15 * 4 * 5 / 2)
})

test_that("a zero first factor gives the zero claims ultimate 0", {
  # a later factor with a zero denominator in the pool as well stays
  # infinite, harmless behind g_{I-i} = 0
  cum <- rbind(c(5, 8, 9, 9),
               c(0, 0, 0, 3),       # AY 1, x = b: first payment at year 3
               c(4, 6, 7, 7),
               c(0, 0, 0, 0),
               c(3, 5, 6, 6),
               c(0, 0, 1, 1),
               c(2, 3, 4, 4),
               c(0, 1, 1, 1))
  d <- toy(cum, ay = rep(1:4, each = 2))
  # accident year i = 3: g_1 = (0 + 0) / (8 + 6), g_2 = 3 / 0, and 3 / 0 in
  # the zero set of i = 4 too
  z <- nncl_zero_claims(d$cum, d$ay, rep(1, 8))
  f <- z$factors
  expect_equal(f$g[f$i == 3], c(0, Inf))
  expect_equal(f$pooled_over[f$i == 3], c(NA, "accident years"))
  expect_equal(z$ult_zero, matrix(c(0, 7 * 3 / 9, 0, 0), nrow = 1))
})

test_that("(5.1) stops on a zero claims factor with a zero denominator", {
  # a positive numerator over a zero denominator ('all denominators
  # positive', Section 4.2) that no pooled ratio replaces gives an infinite
  # reserve
  expect_error(nncl_reserves(1, 2, 0, 1, matrix(c(0, Inf), 1, 2)))
})

## the default settings of config.yml (nncl): the main runs, the random-start
## grid and the chain-ladder-start grid, whose keys replace those of grid
nncl_cfg_default <- list(
  model = list(q = c(5, 10, 20), q_main = 20, activation = "tanh"),
  training = list(epochs = 100, batch_size = 10000, validation_split = 0.1),
  sensitivity = list(learning_rate = 0.001, max_epochs = 500, patience = 20),
  runs = c("paper_q5", "paper_q10", "paper_q20", "s1_adam", "s2_early_stop",
           "s3_cl_start"),
  grid = list(hidden = list(20, c(20, 20, 15), c(20, 15, 10)),
              optimizers = c("sgd", "sgd_momentum", "sgd_nesterov", "adagrad",
                             "adadelta", "rmsprop", "adam", "adamw", "adamax",
                             "nadam"),
              learning_rate = list(sgd = 0.001,
                                   sgd_momentum = 0.001,
                                   sgd_nesterov = 0.001,
                                   adagrad = 0.01,
                                   adadelta = 1,
                                   rmsprop = 0.001,
                                   adam = 0.001,
                                   adamw = 0.001,
                                   adamax = 0.001,
                                   nadam = 0.001),
              momentum = 0.9,
              training = c("paper", "early_stop"),
              seeds = 20,
              nagging = 10),
  cl_grid = list(training = c("cl_paper", "cl_start"))
)

test_that("nncl_runs: 6 main runs and two grids of 1,200 runs", {
  nncl_cfg <- nncl_cfg_default
  runs <- nncl_runs(nncl_cfg, 2026)
  expect_length(runs, 6 + 2 * 3 * 10 * 2 * 20)
  expect_equal(anyDuplicated(names(runs)), 0)
  expect_equal(names(runs)[1:6], nncl_cfg$runs)
  # the main runs, the random-start grid, the chain-ladder-start grid
  part <- sapply(runs, `[[`, "part")
  expect_equal(unname(part),
               rep(c("main", "grid", "cl_grid"), c(6, 1200, 1200)))
  expect_true(all(grepl("^grid_", names(runs)[part == "grid"])))
  expect_true(all(grepl("^clgrid_", names(runs)[part == "cl_grid"])))
  expect_false(any(grepl("grid_", names(runs)[part == "main"])))
  # Listing 2 and S1-S3, each adding one change
  expect_equal(runs$paper_q5$q, 5)
  expect_equal(runs$paper_q5$param[c("optimizer", "epochs", "early_stop")],
               list(optimizer = "rmsprop", epochs = 100, early_stop = FALSE))
  expect_equal(runs$s1_adam$param,
               modifyList(runs$paper_q20$param, list(optimizer = "adam")))
  expect_equal(runs$s2_early_stop$param,
               modifyList(runs$s1_adam$param,
                          list(early_stop = TRUE, epochs = 500)))
  expect_equal(runs$s3_cl_start$param, runs$s2_early_stop$param)
  expect_equal(sapply(runs[1:6], `[[`, "cl_start"),
               setNames(rep(c(FALSE, TRUE), c(5, 1)), nncl_cfg$runs))
  # the grids: their first and last runs
  expect_equal(names(runs)[c(7, 1206, 1207, 2406)],
               c("grid_20_sgd_paper_s2026",
                 "grid_20-15-10_nadam_early_stop_s2045",
                 "clgrid_20_sgd_cl_paper_s2026",
                 "clgrid_20-15-10_nadam_cl_start_s2045"))
  # seed by seed: the 60 combinations of a seed before the next seed
  expect_equal(names(runs)[8:9],
               c("grid_20_sgd_early_stop_s2026",
                 "grid_20_sgd_momentum_paper_s2026"))
  expect_equal(sub(".*_s", "", names(runs)[-(1:6)]),
               rep(rep(as.character(2026:2045), each = 60), 2))
  run <- runs[["clgrid_20-20-15_adagrad_cl_start_s2045"]]
  expect_equal(run$q, c(20, 20, 15))
  expect_true(run$cl_start)
  expect_equal(run$param,
               modifyList(runs$s3_cl_start$param,
                          list(optimizer = "adagrad",
                               learning_rate = 0.01,
                               momentum = 0.9,
                               seed = 2045)))
  run <- runs[["grid_20_rmsprop_early_stop_s2027"]]
  expect_false(run$cl_start)
  expect_true(run$param$early_stop)
  run <- runs[["grid_20_rmsprop_paper_s2027"]]
  expect_equal(run$param[c("epochs", "early_stop", "seed")],
               list(epochs = 100, early_stop = FALSE, seed = 2027))
  # runs: the main runs to fit
  nncl_cfg$runs <- "s3_cl_start"
  nncl_cfg$grid$seeds <- 0
  expect_equal(names(nncl_runs(nncl_cfg, 1)), "s3_cl_start")
  # the quick profile of config.yml: one hidden layer as a plain number
  nncl_cfg$grid$hidden <- 20
  nncl_cfg$grid$optimizers <- c("rmsprop", "sgd")
  nncl_cfg$grid$seeds <- 2
  nncl_cfg$grid$nagging <- 2
  runs <- nncl_runs(nncl_cfg, 2026)
  expect_length(runs, 1 + 2 * 2 * 2 + 2 * 2 * 2)
  expect_equal(names(runs)[2:9],
               c("grid_20_rmsprop_paper_s2026",
                 "grid_20_rmsprop_early_stop_s2026",
                 "grid_20_sgd_paper_s2026",
                 "grid_20_sgd_early_stop_s2026",
                 "grid_20_rmsprop_paper_s2027",
                 "grid_20_rmsprop_early_stop_s2027",
                 "grid_20_sgd_paper_s2027",
                 "grid_20_sgd_early_stop_s2027"))
  expect_equal(names(runs)[10:17],
               sub("_paper_", "_cl_paper_",
                   sub("_early_stop_", "_cl_start_",
                       sub("^grid_", "clgrid_", names(runs)[2:9]))))
  expect_equal(runs[[17]]$q, 20)
  # a training that is none of the four is no run
  nncl_cfg$cl_grid$training <- "cl_early"
  expect_error(nncl_runs(nncl_cfg, 2026))
})

test_that("the two grids hold the 1,800 runs of the former single grid", {
  nncl_cfg <- nncl_cfg_default
  runs <- nncl_runs(nncl_cfg, 2026)
  # the former grid, grid_<hidden>_<optimizer>_<training>_s<seed>: the
  # trainings paper, early_stop and cl_start in one grid (its loops)
  param <- runs$paper_q20$param
  param_s2 <- runs$s2_early_stop$param
  former <- list()
  for (s in 2026 + seq_len(20) - 1) {
    for (h in nncl_cfg$grid$hidden) {
      for (o in nncl_cfg$grid$optimizers) {
        for (tr in c("paper", "early_stop", "cl_start")) {
          p <- modifyList(if (tr == "paper") param else param_s2,
                          list(optimizer = o,
                               learning_rate = nncl_cfg$grid$learning_rate[[o]],
                               momentum = 0.9,
                               seed = s))
          run_name <- paste0("grid_", paste(h, collapse = "-"), "_", o, "_",
                             tr, "_s", s)
          former[[run_name]] <- list(q = h,
                                     param = p,
                                     cl_start = tr == "cl_start")
        }
      }
    }
  }
  expect_length(former, 1800)
  # the same fits (hidden layers, param with the seed, start): the runs from
  # the random start under their names, those from the CL factor in the grid
  # of their own
  new_name <- ifelse(grepl("_cl_start_", names(former)),
                     sub("^grid_", "clgrid_", names(former)),
                     names(former))
  expect_equal(sum(new_name != names(former)), 600)
  expect_true(all(new_name %in% names(runs)))
  expect_identical(lapply(unname(runs[new_name]), `[`,
                          c("q", "param", "cl_start")),
                   unname(former))
  expect_equal(unname(sapply(runs[new_name], `[[`, "part")),
               ifelse(grepl("_cl_start_", names(former)), "cl_grid", "grid"))
  # the 600 runs that are new: Listing 2's training from the CL factor
  new <- setdiff(names(runs)[-(1:6)], new_name)
  expect_length(new, 600)
  expect_true(all(grepl("^clgrid_.*_cl_paper_s20[0-9]{2}$", new)))
})

test_that("cl_paper: Listing 2's training started in the CL factor as S3", {
  runs <- nncl_runs(nncl_cfg_default, 2026)
  # the param of the paper run of the same hidden layers, optimiser and seed
  cl_paper <- grep("_cl_paper_", names(runs), value = TRUE)
  paper <- sub("_cl_paper_", "_paper_", sub("^clgrid_", "grid_", cl_paper))
  expect_length(cl_paper, 600)
  expect_identical(lapply(unname(runs[cl_paper]), `[`, c("q", "param")),
                   lapply(unname(runs[paper]), `[`, c("q", "param")))
  expect_true(all(sapply(runs[cl_paper], `[[`, "cl_start")))
  expect_false(any(sapply(runs[paper], `[[`, "cl_start")))
  expect_equal(unique(sapply(runs[cl_paper], function(run) run$param$epochs)),
               100)
  expect_false(any(sapply(runs[cl_paper], function(run) run$param$early_stop)))
  # and cl_start that of the early_stop run
  cl_start <- grep("^clgrid_.*_cl_start_", names(runs), value = TRUE)
  early_stop <- sub("_cl_start_", "_early_stop_",
                    sub("^clgrid_", "grid_", cl_start))
  expect_identical(lapply(unname(runs[cl_start]), `[`, c("q", "param")),
                   lapply(unname(runs[early_stop]), `[`, c("q", "param")))
  # the networks of a run: the start and the training nncl_fit() is given
  cum <- cbind(c(4, 1, 9, 16, 25), c(8, 3, 9, 20, 30), c(10, 6, 12, 22, 33))
  seen <- NULL
  stub <- function(x, y, w, x_new, q, param, f_start) {
    seen <<- rbind(seen,
                   data.frame(f_start = if (is.null(f_start)) NA else f_start,
                              early_stop = param$early_stop,
                              epochs = param$epochs))
    list(loss = 0, loss_train = 0, loss_vali = 0, f_new = 1)
  }
  for (r in c("s3_cl_start", "clgrid_20_adam_cl_paper_s2026",
              "clgrid_20_adam_cl_start_s2026", "grid_20_adam_paper_s2026")) {
    nncl_run_fit(cum,
                 matrix(1:5, ncol = 1),
                 learn_rows = list(1:5, c(1, 3, 4)),
                 x_new = matrix(0, 2, 1),
                 runs[[r]],
                 units = 1,
                 fit = stub)
  }
  # CL factor of Keras's training rows (the first 90%): rows 1:4 and 1, 3
  f_cl <- c((8 + 3 + 9 + 20) / (4 + 1 + 9 + 16), (10 + 12) / (8 + 9))
  expect_equal(seen$f_start, c(rep(f_cl, 3), NA, NA))
  expect_equal(seen$early_stop, rep(c(TRUE, FALSE, TRUE, FALSE), each = 2))
  expect_equal(seen$epochs, rep(c(500, 100, 500, 100), each = 2))
})

test_that("anchored patterns tell the run files of the tasks apart", {
  runs <- nncl_runs(nncl_cfg_default, 2026)
  # the run files of a coding, <tag>_fit_<run>.rds: the runs of the fit
  # script, S4 (saved with S3) and the final fits of the three searches
  tuned <- paste0("tuned_",
                  rep(c("cl_start", "paper", "early_stop"), each = 10),
                  "_s",
                  2026:2035)
  run_names <- c(names(runs), "s4_balance", tuned)
  tags <- c("nncl_synthetic", "nncl_synthetic_age_numeric")
  files <- c(outer(run_names, tags, function(run, tag) {
    paste0(tag, "_fit_", run, ".rds")
  }))
  pattern <- c(main = "_fit_(paper_q[0-9]+|s[1-4]_[a-z_]+)[.]rds$",
               grid = "_fit_grid_.*[.]rds$",
               cl_grid = "_fit_clgrid_.*[.]rds$",
               tuned_cl_start = "_fit_tuned_cl_start_s[0-9]+[.]rds$",
               tuned_paper = "_fit_tuned_paper_s[0-9]+[.]rds$",
               tuned_early_stop = "_fit_tuned_early_stop_s[0-9]+[.]rds$")
  for (tag in tags) {
    hits <- sapply(paste0("^", tag, pattern), grepl, files)
    expect_equal(unname(colSums(hits)), c(7, 1200, 1200, 10, 10, 10))
    # a file of the coding is the file of one task, a file of the other
    # coding of none
    expect_equal(rowSums(hits),
                 as.numeric(startsWith(files, paste0(tag, "_fit_"))))
    # a run being fitted (lock) or saved (temporary file) is no run file
    expect_false(any(sapply(paste0("^", tag, pattern), grepl,
                            paste0(files, c(".lock", ".tmp")))))
  }
  # anchored: "grid_" alone is in the run names of both grids, and the tag of
  # the dummy coding starts the tag of the numeric coding
  expect_equal(sum(grepl("grid_", files)), 2 * 2400)
  expect_equal(sum(grepl("nncl_synthetic.*_fit_grid_", files)), 2 * 1200)
  expect_equal(sum(grepl("^nncl_synthetic_fit_grid_", files)), 1200)
  # the runs of a grid by its pattern
  part <- sapply(runs, `[[`, "part")
  expect_equal(grepl("^nncl_synthetic_fit_grid_.*[.]rds$", files[1:2406]),
               unname(part == "grid"))
  expect_equal(grepl("^nncl_synthetic_fit_clgrid_.*[.]rds$", files[1:2406]),
               unname(part == "cl_grid"))
  # the main runs the fit script loops over and claims: without S4, which is
  # saved with S3 (a queue of the final run counts the runs of its loop)
  claimed <- "^nncl_synthetic_fit_(paper_q[0-9]+|s[1-3]_[a-z_]+)[.]rds$"
  expect_equal(grepl(claimed, files), files %in% files[1:6])
})

test_that("nncl_grid_runs: the runs and the nagging blocks of each grid", {
  nncl_cfg <- nncl_cfg_default
  runs <- nncl_runs(nncl_cfg, 2026)
  grid <- nncl_grid_runs(nncl_cfg, 2026)
  expect_named(grid, c("part", "hidden", "optimizer", "training", "seed",
                       "learning_rate", "block", "run"))
  expect_equal(nrow(grid), 2400)
  expect_equal(grid$part, rep(c("grid", "cl_grid"), each = 1200))
  # the runs of nncl_runs(): names, hidden layers, param and start
  expect_setequal(grid$run, names(runs)[-(1:6)])
  fitted <- unname(runs[grid$run])
  expect_equal(grid$part, sapply(fitted, `[[`, "part"))
  expect_equal(grid$hidden,
               sapply(fitted, function(run) paste(run$q, collapse = "-")))
  expect_equal(grid$optimizer,
               sapply(fitted, function(run) run$param$optimizer))
  expect_equal(grid$seed, sapply(fitted, function(run) run$param$seed))
  expect_equal(grid$learning_rate,
               sapply(fitted, function(run) run$param$learning_rate))
  expect_equal(grid$training %in% c("early_stop", "cl_start"),
               sapply(fitted, function(run) run$param$early_stop))
  expect_equal(grid$training %in% c("cl_paper", "cl_start"),
               sapply(fitted, `[[`, "cl_start"))
  expect_equal(unique(grid$training[grid$part == "grid"]),
               c("paper", "early_stop"))
  expect_equal(unique(grid$training[grid$part == "cl_grid"]),
               c("cl_paper", "cl_start"))
  # nagging predictors: per combination the blocks of seeds 2026-2035 and
  # 2036-2045, 10 networks each, in both grids
  expect_equal(grid$block, ifelse(grid$seed <= 2035, 1, 2))
  predictor <- paste(grid$part, grid$hidden, grid$optimizer, grid$training,
                     grid$block)
  expect_length(unique(predictor), 2 * 3 * 10 * 2 * 2)
  expect_true(all(table(predictor) == 10))
  # a key of cl_grid replaces that of grid: 6 seeds in blocks of 3
  nncl_cfg$cl_grid$seeds <- 6
  nncl_cfg$cl_grid$nagging <- 3
  grid <- nncl_grid_runs(nncl_cfg, 2026)
  expect_equal(grid$part, rep(c("grid", "cl_grid"), c(1200, 360)))
  expect_setequal(grid$run, names(nncl_runs(nncl_cfg, 2026))[-(1:6)])
  cl <- grid$part == "cl_grid"
  expect_equal(grid$block[cl], ifelse(grid$seed[cl] <= 2028, 1, 2))
  expect_equal(grid$block[!cl], ifelse(grid$seed[!cl] <= 2035, 1, 2))
  # the quick profile of config.yml: 8 runs a grid, one block of 2 seeds
  nncl_cfg <- nncl_cfg_default
  nncl_cfg$grid[c("hidden", "seeds", "nagging")] <- list(20, 2, 2)
  nncl_cfg$grid$optimizers <- c("rmsprop", "sgd")
  grid <- nncl_grid_runs(nncl_cfg, 2026)
  expect_equal(grid$part, rep(c("grid", "cl_grid"), each = 8))
  expect_setequal(grid$run, names(nncl_runs(nncl_cfg, 2026))[-(1:6)])
  expect_equal(grid$run[c(1, 2, 9, 16)],
               c("grid_20_rmsprop_paper_s2026",
                 "grid_20_rmsprop_paper_s2027",
                 "clgrid_20_rmsprop_cl_paper_s2026",
                 "clgrid_20_sgd_cl_start_s2027"))
  expect_true(all(grid$block == 1))
})

test_that("nncl_run_fit: Listing 2's responses in units, CL start, losses", {
  cum <- cbind(c(4, 1, 9, 16, 25), c(8, 3, 9, 20, 30), c(10, 6, 12, 22, 33))
  x <- matrix(1:5, ncol = 1)
  seen <- list()
  # stub: no network, the homogeneous CL factor of its rows
  stub <- function(x, y, w, x_new, q, param, f_start) {
    seen[[length(seen) + 1]] <<- list(x = x, y = y, w = w, q = q,
                                      f_start = f_start)
    list(model = "network",
         epochs_used = 3,
         loss = 2,
         loss_train = 1.5,
         loss_vali = 0.5,
         f_new = rep(sum(y * w) / sum(w^2), nrow(x_new)))
  }
  run <- list(q = c(7, 3), param = list(validation_split = 0.4),
              cl_start = TRUE)
  fits <- nncl_run_fit(cum,
                       x,
                       learn_rows = list(1:5, c(1, 3, 4)),
                       x_new = matrix(0, 2, 1),
                       run,
                       units = 100,
                       fit = stub)
  expect_length(fits, 2)
  # network j = 1: C_1 / sqrt(C_0) and sqrt(C_0), payments in 100
  expect_equal(seen[[1]]$y, cum[, 2] / 100 / sqrt(cum[, 1] / 100))
  expect_equal(seen[[1]]$w, matrix(sqrt(cum[, 1] / 100), ncol = 1))
  expect_equal(seen[[1]]$x, x)
  expect_equal(seen[[1]]$q, c(7, 3))
  # CL start: the factor of Keras's training rows, the first 60%
  expect_equal(seen[[1]]$f_start, (8 + 3 + 9) / (4 + 1 + 9))
  expect_equal(seen[[2]]$x, x[c(1, 3, 4), , drop = FALSE])
  expect_equal(seen[[2]]$f_start, 10 / 8)
  # the factors do not depend on the unit, the losses are scaled back
  expect_equal(fits[[1]]$f_new, rep(sum(cum[, 2]) / sum(cum[, 1]), 2))
  expect_equal(fits[[2]]$f_new, rep((10 + 12 + 22) / (8 + 9 + 20), 2))
  expect_equal(unlist(fits[[1]][c("loss", "loss_train", "loss_vali")]),
               c(loss = 200, loss_train = 150, loss_vali = 50))
  expect_null(fits[[1]]$model)
  # random start
  run$cl_start <- FALSE
  nncl_run_fit(cum, x, list(1:5), matrix(0, 2, 1), run, 100, fit = stub)
  expect_null(seen[[3]]$f_start)
})

test_that("nncl_balance: S4 has the CL factor of the training rows", {
  cum <- cbind(c(4, 1, 9, 16, 25), c(8, 3, 9, 20, 30), c(10, 6, 12, 22, 33))
  x_id <- c(1, 2, 1, 2, 1)             # two feature values
  learn_rows <- list(1:5, c(1, 3, 4))
  s3 <- list(run = "s3_cl_start",
             param = list(validation_split = 0.4),
             f_x = cbind(c(1.5, 2), c(1.2, 1.1)),
             fits = list(list(epochs_used = 3, loss = 9),
                         list(epochs_used = 0, loss = 9)),
             info = "where it was fitted")
  s4 <- nncl_balance(s3, cum, x_id, learn_rows)
  expect_equal(s4$run, "s4_balance")
  expect_equal(s4[c("param", "info")], s3[c("param", "info")])
  # network j = 1, training rows 1:3: c_1 = (8 + 3 + 9) / (6 + 2 + 13.5);
  # j = 2, training row 1: c_2 = 10 / (1.2 * 8)
  balance <- c(20 / 21.5, 10 / 9.6)
  expect_equal(sapply(s4$fits, `[[`, "balance"), balance)
  expect_equal(s4$f_x, s3$f_x %*% diag(balance))
  expect_equal(sapply(s4$fits, `[[`, "epochs_used"), c(3, 0))
  # the average factor (3.9) of the training rows is their CL factor
  f_1 <- s4$f_x[x_id, 1]
  expect_equal(sum(f_1[1:3] * cum[1:3, 1]) / sum(cum[1:3, 1]), 20 / 14)
  # the losses L'_j (6.1) of the corrected factors, in the payments' unit
  res2 <- (cum[, 2] - f_1 * cum[, 1])^2 / cum[, 1]
  expect_equal(unlist(s4$fits[[1]][c("loss", "loss_train", "loss_vali")]),
               c(loss = sum(res2),
                 loss_train = sum(res2[1:3]),
                 loss_vali = sum(res2[4:5])))
  f_2 <- s4$f_x[c(1, 1, 2), 2]
  res2 <- (cum[c(1, 3, 4), 3] - f_2 * cum[c(1, 3, 4), 2])^2 / cum[c(1, 3, 4), 2]
  expect_equal(s4$fits[[2]]$loss, sum(res2))
  expect_equal(s4$fits[[2]]$loss_train, 0)
})

## the tests fit no network: f with the functions of 'stand_ins' in place of
## those of the same name it calls (as in test-functions.R)
with_stand_ins <- function(f, stand_ins) {
  environment(f) <- list2env(stand_ins, parent = environment(f))
  f
}

## stand-ins for nncl_model() and the Keras functions of nncl_fit(): the
## "network" has one CL factor for all feature values, param$f_path[e] after
## epoch e; fit() calls the function of the timing callback as Keras does
## and, with early stopping, restores the factor of the best epoch (of the
## first one if no validation loss is finite).
## python$held: the R functions Python holds, each for as long as R has not
## garbage collected the callback it was given to (as reticulate does)
python <- new.env()
python$held <- list()
release <- function(callback) {
  python$held <- Filter(function(f) !identical(f, callback$on_epoch_end),
                        python$held)
}
keras_stand_ins <- list(
  nncl_model = function(d, q, param, f_start) {
    net <- new.env()
    net$f <- if (is.null(f_start)) 1 else f_start
    net$f_path <- param$f_path
    net
  },
  get_weights = function(net) net$f,
  set_weights = function(net, f) net$f <- f,
  predict = function(net, xw, ...) net$f * xw[[2]],
  count_params = function(object) if (is.environment(object)) 322 else 1,
  get_layer = function(net, name) name,
  callback_lambda = function(on_epoch_end) {
    callback <- new.env()
    callback$on_epoch_end <- on_epoch_end
    python$held <- c(python$held, on_epoch_end)
    reg.finalizer(callback, release)
    callback
  },
  callback_early_stopping = function(...) "early stopping",
  fit = function(net, xw, y, epochs, validation_split, callbacks, ...) {
    train <- seq_len(floor(nrow(y) * (1 - validation_split)))
    loss <- val_loss <- NULL
    for (e in seq_len(epochs)) {
      net$f <- net$f_path[e]
      res2 <- (y - net$f * xw[[2]])^2
      loss[e] <- mean(res2[train])
      val_loss[e] <- mean(res2[-train])
      python$returned <- c(python$returned,
                           list(callbacks[[1]]$on_epoch_end(e - 1, list())))
    }
    if (length(callbacks) == 2) {
      net$f <- net$f_path[max(which.min(val_loss), 1)]
    }
    list(metrics = list(loss = loss, val_loss = val_loss))
  }
)

## five learning cells of network j = 1 with C_0 and C_1, Listing 2's
## responses and volumes; Keras's split: training rows 1:3, validation 4:5
toy_fit <- function(f_path, early_stop = FALSE, f_start = NULL) {
  c_prev <- c(4, 1, 9, 16, 25)
  param <- list(validation_split = 0.4,
                epochs = length(f_path),
                batch_size = 10,
                early_stop = early_stop,
                patience = 2,
                f_path = f_path)
  with_stand_ins(nncl_fit, keras_stand_ins)(matrix(1:5, ncol = 1),
                                            c(8, 3, 9, 20, 30) / sqrt(c_prev),
                                            matrix(sqrt(c_prev), ncol = 1),
                                            matrix(0, 2, 1),
                                            20,
                                            param,
                                            f_start)
}

test_that("nncl_fit: losses (6.1), factors and seconds of every epoch", {
  fit <- toy_fit(c(2, 1.5, 1.25))
  expect_equal(fit$history$epoch, 1:3)
  expect_equal(fit$history$val_loss, c(12.5, 1.625, 0.03125))
  expect_equal(fit[c("epochs_run", "epochs_used", "n_par")],
               list(epochs_run = 3L, epochs_used = 3L, n_par = 321))
  # f = 1.25: (8 - 5)^2 / 4 + (3 - 1.25)^2 + (9 - 11.25)^2 / 9 on the
  # training rows, (30 - 31.25)^2 / 25 on the validation rows
  expect_equal(unlist(fit[c("loss", "loss_train", "loss_vali")]),
               c(loss = 5.9375, loss_train = 5.875, loss_vali = 0.0625))
  expect_equal(fit$f_learn, rep(1.25, 5))
  expect_equal(fit$f_new, rep(1.25, 2))
  # wall-clock seconds: one per epoch, within those of the fit
  expect_length(fit$history$time, 3)
  expect_true(all(fit$history$time >= 0))
  expect_lte(sum(fit$history$time), fit$run_time)
  expect_true(all(unlist(fit[c("time_build", "time_predict")]) >= 0))
})

test_that("nncl_fit: early stopping and the CL start kept or left", {
  # the epoch with the lowest validation loss
  fit <- toy_fit(c(1.5, 1.2, 2), early_stop = TRUE)
  expect_equal(fit$history$val_loss, c(1.625, 0.02, 12.5))
  expect_equal(c(fit$epochs_run, fit$epochs_used), c(3, 2))
  expect_equal(fit$f_new, rep(1.2, 2))
  # CL start 1.25 (validation loss 0.03125): no epoch beats it, it is kept
  fit <- toy_fit(c(1.5, 2, 1), early_stop = TRUE, f_start = 1.25)
  expect_equal(c(fit$epochs_run, fit$epochs_used), c(3, 0))
  expect_equal(fit$f_new, rep(1.25, 2))
  expect_equal(fit$loss, 5.9375)
  # an epoch beats the CL start
  fit <- toy_fit(c(1.5, 1.2), early_stop = TRUE, f_start = 1.25)
  expect_equal(c(fit$epochs_run, fit$epochs_used), c(2, 2))
  expect_equal(fit$f_new, rep(1.2, 2))
  # a diverging optimiser (no finite loss): Keras keeps the first epoch
  fit <- toy_fit(c(NaN, NaN), early_stop = TRUE)
  expect_equal(fit$epochs_used, 1)
})

test_that("nncl_fit: the CL start without early stopping runs all epochs", {
  # cl_paper: no epoch beats the CL start 1.25 (validation loss 0.03125),
  # which early stopping would keep; Listing 2's training keeps the last
  # epoch
  fit <- toy_fit(c(1.5, 2, 1), f_start = 1.25)
  expect_equal(fit$history$val_loss, c(1.625, 12.5, 1))
  expect_equal(c(fit$epochs_run, fit$epochs_used), c(3, 3))
  expect_equal(fit$f_new, rep(1, 2))
  expect_equal(fit$f_learn, rep(1, 5))
  # the same epochs from the random start
  fit <- toy_fit(c(1.5, 2, 1))
  expect_equal(c(fit$epochs_run, fit$epochs_used), c(3, 3))
  expect_equal(fit$f_new, rep(1, 2))
})

test_that("nncl_fit: the timing callback does not keep the fit in memory", {
  python$held <- list()
  python$returned <- NULL
  fit <- toy_fit(c(2, 1.5, 1.25), early_stop = TRUE)
  # nothing is returned to Keras at the end of an epoch
  expect_equal(python$returned, rep(list(NULL), 3))
  # Python holds the function of the callback, and the function the call of
  # nncl_fit() with its data and network: freed only if that call does not
  # hold the callback any more
  gc()
  expect_length(python$held, 0)
})
