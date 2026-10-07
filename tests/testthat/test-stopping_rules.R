##########################################
#########  checks of the stopping rules of the bCCNN grid (R/nn_models.R:
#########  stopping_steps(), fixed_steps(), rolling_origin_rules(),
#########  epoch_blocks()); no Keras: the network fits are replaced by a
#########  stand-in
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(ChainLadder)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

## f with the functions of 'stand_ins' in place of those of the same name it
## calls (as in test-functions.R)
with_stand_ins <- function(f, stand_ins) {
  environment(f) <- list2env(stand_ins, parent = environment(f))
  f
}

## the rules of config.yml bccnn$stopping with a short window and patience
stop_cfg <- function(window, patience) {
  list(rules = c("minimum", "fixed", "moving_average", "patience"),
       window = window,
       patience = patience)
}

## Keras's EarlyStopping (keras 3.15.1, callbacks/early_stopping.py: monitor
## a loss, min_delta 0, no baseline, restore_best_weights) step by step, its
## epochs the steps 0, 1, ... of the curve: the step whose weights it
## restores at the end of the training
keras_early_stopping <- function(vali, patience) {
  best <- NULL                                   # no best loss yet
  best_step <- 0
  wait <- 0
  for (step in seq_along(vali) - 1) {
    current <- vali[step + 1]
    wait <- wait + 1
    if (is.null(best) || isTRUE(current < best)) {
      best <- current                            # a new low: wait restarts
      best_step <- step
      wait <- 0
    } else if (wait >= patience && step > 0) {
      break                                      # model.stop_training
    }
  }
  best_step
}

## central moving average by hand: the mean of the losses of the steps
## e - (ceiling(w / 2) - 1), ..., e + floor(w / 2); NA at the ends
moving_average <- function(vali, w) {
  sapply(seq_along(vali) - 1, function(e) {
    steps <- (e - (ceiling(w / 2) - 1)):(e + floor(w / 2))
    if (min(steps) < 0 || max(steps) > length(vali) - 1) return(NA)
    mean(vali[steps + 1])
  })
}

test_that("the fixed steps are rounded to the nearest multiple", {
  # Paper C reads roughly 300 off its Figure 2; here the lowest validation
  # loss of the main fit to the nearest 100 (quick profile: 10), a half up
  expect_equal(fixed_steps(c(0, 49, 50, 149, 150, 165, 250, 349, 1000), 100),
               c(0, 0, 100, 100, 200, 200, 300, 300, 1000))
  expect_equal(fixed_steps(c(4, 5, 37, 100), 10), c(0, 10, 40, 100))
})

test_that("the stopping rules on a U-shaped validation curve", {
  vali <- (0:20 - 12)^2 + 5                      # lowest at step 12
  s <- stopping_steps(vali, stop_cfg(5, 3), 20, 7)
  expect_named(s, c("minimum", "fixed", "moving_average", "patience"))
  expect_equal(unname(s), c(12, 7, 12, 12))
  # the minimum looks at the first minimum_epochs steps only, the patience
  # and the moving average at the whole run
  expect_equal(stopping_steps(vali, stop_cfg(5, 3), 8, 7)[["minimum"]], 8)
  expect_equal(stopping_steps(vali, stop_cfg(5, 3), 99, 7)[["minimum"]], 12)
  # an even window: one step more after its centre than before, so the
  # windows of steps 11 (10..13) and 12 (11..14) tie and the first is taken
  expect_equal(stopping_steps(vali, stop_cfg(4, 3), 20, 7)[["moving_average"]],
               11)
  # only the rules of the configuration, in its order
  cfg_two <- list(rules = c("patience", "minimum"), window = 5, patience = 3)
  expect_equal(stopping_steps(vali, cfg_two, 8, 7),
               c(patience = 12, minimum = 8))
})

test_that("the moving average is central and leaves the ends out", {
  set.seed(1)
  vali <- 100 - 0.2 * 0:300 + 0.0004 * (0:300)^2 + rnorm(301, sd = 2)
  for (w in c(3, 10, 100)) {
    hand <- moving_average(vali, w)
    s <- stopping_steps(vali, stop_cfg(w, 5), 300, 0)[["moving_average"]]
    expect_equal(s, which.min(hand) - 1)
    # the first and the last step with a full window around them
    expect_equal(range(which(!is.na(hand)) - 1),
                 c(ceiling(w / 2) - 1, 300 - floor(w / 2)))
  }
  # window 100 of 3,000 steps (config.yml): steps 49 to 2,950 can be chosen
  expect_equal(stopping_steps(3000:0, stop_cfg(100, 300), 1000,
                              0)[["moving_average"]], 2950)
  expect_equal(stopping_steps(0:3000, stop_cfg(100, 300), 1000,
                              0)[["moving_average"]], 49)
  # Harkonen (2021) Table 2: at most 9,950 of 10,000 epochs with window 100
  expect_equal(which.min(moving_average(10000:1, 100)), 9950)
  # windows with the same sum of losses tie and the first is taken, also
  # where 1 / w is not exact and averages with the weights 1 / w differ in
  # the last bit (whole numbers: the sums are exact). Window 10 of 16
  # losses: the windows of steps 8 and 10 have the lowest sum
  vali <- c(56, 49, 46, 60, 44, 58, 46, 55, 51, 55, 58, 49, 48, 46, 45, 57)
  expect_equal(rowSums(embed(vali, 10)), c(520, 522, 522, 524, 510, 511, 510))
  expect_equal(stopping_steps(vali, stop_cfg(10, 5), 15, 0)[["moving_average"]],
               8)
  set.seed(3)
  for (k in 1:200) {
    w <- c(10, 11, 20, 100)[k %% 4 + 1]
    vali <- sample(40:60, 150, replace = TRUE)
    s <- stopping_steps(vali, stop_cfg(w, 5), 100, 0)[["moving_average"]]
    expect_equal(s, which.min(moving_average(vali, w)) - 1)
  }
})

test_that("the patience rule is Keras's early stopping from the start", {
  set.seed(2)
  for (k in 1:50) {
    vali <- 100 - 0.2 * 0:300 + 0.0004 * (0:300)^2 + rnorm(301, sd = 2)
    if (k > 40) vali[sample(2:301, 30)] <- NaN   # steps without a loss
    for (p in c(1, 2, 5, 30, 300)) {
      s <- stopping_steps(vali, stop_cfg(10, p), 100, 0)
      expect_equal(s[["patience"]], keras_early_stopping(vali, p))
      # the minimum on the same noisy curve: the rule of "bCCNN fit.R" on a
      # run of 100 steps
      expect_equal(s[["minimum"]], which.min(vali[1:101]) - 1)
    }
  }
  # stopped at the first low that no step of the next 3 beats; never
  # stopped: the lowest loss of the whole run
  vali <- c(9, 8, 7, 8, 8, 8, 6, 5, 9, 9, 9, 9, 4)
  expect_equal(stopping_steps(vali, stop_cfg(3, 3), 12, 0)[["patience"]], 2)
  expect_equal(stopping_steps(vali, stop_cfg(3, 4), 12, 0)[["patience"]], 7)
  expect_equal(stopping_steps(vali, stop_cfg(3, 5), 12, 0)[["patience"]], 12)
})

test_that("the stopping rules without an improvement, at the end and on ties", {
  # the validation loss rises from the start: the ccODP start (0 steps);
  # the moving average takes the first step it can choose
  up <- stopping_steps(10 + 0:20, stop_cfg(4, 3), 20, 7)
  expect_equal(unname(up), c(0, 7, 1, 0))
  # the lowest loss at the last step
  down <- stopping_steps(30 - 0:20, stop_cfg(4, 3), 20, 7)
  expect_equal(unname(down), c(20, 7, 18, 20))
  expect_equal(stopping_steps(30 - 0:20, stop_cfg(4, 3), 10, 7)[["minimum"]],
               10)
  # ties: the first of equal losses, a tie is no new low
  flat <- stopping_steps(rep(3, 21), stop_cfg(4, 3), 20, 7)
  expect_equal(unname(flat), c(0, 7, 1, 0))
  two <- stopping_steps(c(5, 3, 4, 3, 5, 6, 7), stop_cfg(3, 5), 6, 7)
  expect_equal(two[c("minimum", "patience")], c(minimum = 1, patience = 1))
})

test_that("a diverged network breaks no stopping rule", {
  # no finite loss after step 7 (NaN) or from step 3 on (Inf, then NaN): the
  # lowest finite loss, and the lowest average of a window of finite losses
  # (window 4: those of steps 3 and 4 tie); no such window: the start
  vali <- c(9, 8, 7, 6, 5, 6, 7, 8, rep(NaN, 13))
  expect_equal(unname(stopping_steps(vali, stop_cfg(4, 3), 20, 7)),
               c(4, 7, 3, 4))
  expect_equal(unname(stopping_steps(vali, stop_cfg(3, 3), 20, 7)),
               c(4, 7, 4, 4))
  vali <- c(9, 8, 7, Inf, rep(NaN, 17))
  expect_equal(unname(stopping_steps(vali, stop_cfg(3, 3), 20, 7)),
               c(2, 7, 1, 2))
  expect_equal(unname(stopping_steps(vali, stop_cfg(4, 3), 20, 7)),
               c(2, 7, 0, 2))
  # a loss that is not finite between finite ones is never a low
  vali <- c(9, 8, NaN, 7, Inf, 6, 5, 6, 7, 8, 9)
  expect_equal(unname(stopping_steps(vali, stop_cfg(3, 2), 10, 7)),
               c(6, 7, 6, 6))
  # nothing but the start
  vali <- c(9, rep(NaN, 20))
  expect_equal(unname(stopping_steps(vali, stop_cfg(4, 3), 20, 7)),
               c(0, 7, 0, 0))
})

test_that("the seconds per epoch are kept as means per block of epochs", {
  x <- rbind(data.frame(steps = 250, partition = "final", fit = "early_stop",
                        epoch = 0:250,
                        time = c(NA, rep(0.01, 100), rep(0.02, 100),
                                 rep(0.04, 50)),
                        time_predict = 0.002),
             data.frame(steps = 30, partition = "final", fit = "refit",
                        epoch = 0:30, time = c(NA, rep(0.0123456, 30)),
                        time_predict = c(0.5, rep(0.001, 30))))
  b <- epoch_blocks(x, 100)
  expect_named(b, c("partition", "fit", "steps", "block", "time",
                    "time_predict"))
  # block 0: the prediction of the start; the last block may be shorter
  expect_equal(b$fit, rep(c("early_stop", "refit"), c(4, 2)))
  expect_equal(b$block, c(0:3, 0:1))
  expect_equal(b$time, c(NA, 10, 20, 40, NA, 12.35))
  expect_equal(b$time_predict, c(2, 2, 2, 2, 500, 1))
})

## stand-in for bccnn_fit(): after e steps the "network" started in odp
## predicts its means times (1 + e / 100); its validation losses are the
## curve of param$vali for the valuation date (rows of the triangle), its
## test loss that of the predicted triangle; the Keras fit takes 0.4 s per
## step
calls <- NULL
stub <- function(odp, epochs, param, track) {
  calls <<- rbind(calls, data.frame(cells = sum(odp$cells), epochs = epochs))
  mu_path <- lapply(0:epochs, function(e) (1 + e / 100) * odp$mu)
  h <- data.frame(epoch = 0:epochs,
                  time = c(NA, rep(0.02, epochs)),
                  time_predict = 0.001)
  if (!is.null(track$vali)) {
    h$vali <- param$vali[[as.character(nrow(odp$y))]][0:epochs + 1]
  }
  if (!is.null(track$test)) {
    h$test <- sapply(mu_path, poisson_deviance, y = track$test)
    h$test_pred <- sapply(mu_path, function(mu) sum(mu[!is.na(track$test)]))
  }
  list(mu = mu_path[[epochs + 1]],
       history = h,
       mu_path = mu_path,
       time = c(build = 1, fit = 0.4 * epochs, total = 9))
}

## GenIns at the valuation years 7, 9 and 10 with a validation curve of 12
## steps each; rules: minimum within the first 6 steps, fixed 4 steps,
## moving average over 3 steps, patience 2:
##   year 7:  minimum 3, moving average 9, patience 3
##   year 9:  minimum 0, moving average 9, patience 0
##   year 10: minimum 6, moving average 11, patience 12 (never stopped)
y <- unclass(cum2incr(GenIns))
parts <- rolling_origin(y, c(3, 1), 1, 1)
param <- list(vali = list("7" = c(10, 9, 8, 7, 8, 9, 8.5, 6, 5, 4, 5.5, 7, 8),
                          "9" = c(5, 6, 7, 8, 9, 10, 11, 4, 3, 2, 3, 4, 5),
                          "10" = c(10, 9, 8, 7.5, 7.4, 7.3, 7.2, 7.1, 7, 6.9,
                                   6.8, 6.7, 6.6)))
grid_cfg <- c(stop_cfg(3, 2), list(max_epochs = 12))
rule_steps <- rbind("1" = c(3, 4, 9, 3),
                    "2" = c(0, 4, 9, 0),
                    "final" = c(6, 4, 11, 12))
n_obs <- sapply(parts, function(p) sum(!is.na(p$y)))
n_train <- sapply(parts, function(p) sum(p$train))
ro_rules <- with_stand_ins(rolling_origin_rules, list(bccnn_fit = stub))
ro_fit <- with_stand_ins(rolling_origin_fit, list(bccnn_fit = stub))
compared <- c("partition", "origin", "n_train", "n_vali", "n_test", "steps",
              "test_actual", "test_ccODP", "test_ccODP_train", "test_bCCNN",
              "test_loss_ccODP", "test_loss_ccODP_train", "test_loss_bCCNN",
              "time_build")

test_that("a grid run refits once per number of steps and not for 0 steps", {
  calls <<- NULL
  ro <- ro_rules(parts, NULL, param, grid_cfg, 6, 4, "refit")
  # per partition the validation run of 12 steps, then the chain ladder of
  # its valuation date trained for the distinct steps of the rules
  expect_equal(calls$epochs, c(12, 3, 4, 9, 12, 4, 9, 12, 6, 4, 11, 12))
  expect_equal(calls$cells, c(n_train[1], rep(n_obs[1], 3),
                              n_train[2], rep(n_obs[2], 2),
                              n_train[3], rep(n_obs[3], 4)))
  s <- ro$summary
  expect_equal(s$rule, rep(names(ro$mu), 3))
  expect_equal(s$partition, rep(c("1", "2", "final"), each = 4))
  expect_equal(s$steps, as.vector(t(rule_steps)))
  # the seconds of the refit a rule uses (shared by the rules with the same
  # steps; none for 0 steps) and of all Keras fits of the run
  expect_equal(s$time_refit, 0.4 * ifelse(s$steps == 0, NA, s$steps))
  expect_equal(ro$time_fit, 0.4 * sum(calls$epochs))
  expect_equal(s$time_early_stop, rep(0.4 * 12, 12))
  # per rule the test error of its network at each test partition and its
  # final network on the observed triangle
  for (r in names(ro$mu)) {
    k_rule <- match(r, names(ro$mu))
    for (k in 1:2) {
      cl <- ccodp_fit(parts[[k]]$y)
      mu <- (1 + rule_steps[k, k_rule] / 100) * cl$mu
      row <- s[s$rule == r & s$partition == k, ]
      expect_equal(ro$mu_test[[r]][[k]], mu)
      expect_equal(row$test_loss_bCCNN, poisson_deviance(parts[[k]]$test, mu))
      expect_equal(row$test_bCCNN, sum(mu[!is.na(parts[[k]]$test)]))
      expect_equal(row$test_loss_ccODP,
                   poisson_deviance(parts[[k]]$test, cl$mu))
    }
    expect_length(ro$mu_test[[r]], 2)
    expect_equal(ro$mu[[r]],
                 (1 + rule_steps[3, k_rule] / 100) * ccodp_fit(y)$mu)
  }
  expect_true(all(is.na(s$test_loss_bCCNN[s$partition == "final"])))
  # 0 steps: the chain ladder at the valuation date itself
  expect_identical(ro$mu_test$minimum[[2]], ccodp_fit(parts[[2]]$y)$mu)
  # the validation run of the final partition and the seconds per epoch of
  # every fit, named by its steps
  expect_equal(ro$history$vali, param$vali[["10"]])
  expect_named(ro$epoch_time, c("steps", "partition", "fit", "epoch", "time",
                                "time_predict"))
  expect_equal(nrow(ro$epoch_time), sum(calls$epochs + 1))
  expect_equal(unique(ro$epoch_time[c("partition", "fit", "steps")])$steps,
               calls$epochs)
})

test_that("the minimum rule of a grid run is the single-rule path", {
  for (final_fit in c("refit", "partition")) {
    ro <- ro_rules(parts, NULL, param, grid_cfg, 6, 4, final_fit)
    # the committed path of a grid run: rolling_origin_fit() over the first
    # 6 steps, then the final network of "bCCNN grid fit.R"
    calls <<- NULL
    old <- ro_fit(parts, NULL, param, 6, final_fit)
    old_mu <- if (final_fit == "refit") {
      stub(ccodp_fit(y), old$final$best_epoch, param, track = list())$mu
    } else {
      old$final$mu_path[[old$final$best_epoch + 1]]
    }
    s <- ro$summary[ro$summary$rule == "minimum", compared]
    rownames(s) <- NULL
    s_old <- old$summary
    names(s_old)[names(s_old) == "best_epoch"] <- "steps"
    expect_equal(s$steps, c(3, 0, 6))
    expect_equal(s, s_old[compared])
    expect_equal(ro$mu_test$minimum, old$mu_test)
    expect_equal(ro$mu$minimum, old_mu)
  }
  # partition: the networks of the validation runs, no refit
  calls <<- NULL
  ro <- ro_rules(parts, NULL, param, grid_cfg, 6, 4, "partition")
  expect_equal(calls$epochs, c(12, 12, 12))
  expect_true(all(is.na(ro$summary$time_refit)))
  expect_equal(ro$time_fit, 0.4 * 36)
  train_mu <- ccodp_fit(parts[[3]]$y, parts[[3]]$train)$mu
  expect_equal(ro$mu$patience, 1.12 * train_mu)
  expect_equal(ro$mu_test$moving_average[[1]],
               1.09 * ccodp_fit(parts[[1]]$y, parts[[1]]$train)$mu)
  # the test partitions only: no final network
  ro <- ro_rules(parts[1:2], NULL, param, grid_cfg, 6, 4, "refit")
  expect_length(ro$mu, 0)
  expect_null(ro$history)
  expect_equal(ro$summary$steps, as.vector(t(rule_steps[1:2, ])))
})
