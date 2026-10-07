##########################################
#########  checks of the functions in R/
#########  from the project root: Rscript tests/testthat.R
##########################################

library(testthat)
library(ChainLadder)
for (f in list.files(here::here("R"), pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}

## the tests fit no network: f with the functions of 'stand_ins' in place of
## those of the same name it calls
with_stand_ins <- function(f, stand_ins) {
  environment(f) <- list2env(stand_ins, parent = environment(f))
  f
}

## stand-ins for bccnn_model() and the Keras functions of bccnn_fit(): the
## "network" predicts the ccODP means times (1 + steps / 100) and fit() takes
## the gradient descent steps, calling the callbacks as Keras does (epochs
## from 0, the loss of the epoch in logs)
keras_stand_ins <- list(
  bccnn_model = function(odp, param) {
    model <- new.env()
    model$steps <- 0
    model$predict_on_batch <- function(x) {
      (1 + model$steps / 100) * odp$mu[cbind(x[[1]] + 1, x[[2]] + 1)]
    }
    model
  },
  callback_lambda = function(on_epoch_begin, on_epoch_end) {
    list(on_epoch_begin = on_epoch_begin, on_epoch_end = on_epoch_end)
  },
  fit = function(model, x, y, epochs, callbacks, ...) {
    for (e in seq_len(epochs)) {
      callbacks[[1]]$on_epoch_begin(e - 1, list())
      model$steps <- model$steps + 1
      callbacks[[1]]$on_epoch_end(e - 1, list(loss = 1 / e))
    }
  }
)

test_that("the ccODP model gives the chain-ladder reserves", {
  y <- unclass(cum2incr(GenIns))        # incremental, NA in the lower triangle
  odp <- ccodp_fit(y)
  cl <- sum(predict(chainladder(GenIns))[, 10] - getLatestCumulative(GenIns))
  expect_equal(sum(odp$reserve_o), cl, tolerance = 1e-8)
  expect_equal(c(odp$alpha[1], odp$beta[1]), c(0, 0))
})

test_that("the Keras poisson loss converts to the Poisson deviance", {
  set.seed(1)
  y <- rpois(50, 3)
  mu <- runif(50, 1, 5)
  loss <- mean(mu - y * log(mu))                  # Keras 'poisson' loss
  expect_equal(keras_to_deviance(loss, y), poisson_deviance(y, mu))
})

test_that("the triangles add up", {
  trans <- data.frame(claim_no = c(1, 1, 2, 3, 3, 4),
                      occurrence_period = c(1, 1, 1, 2, 2, 3),
                      payment_period = c(1, 4, 2, 2, 3, 3),
                      payment_inflated = 1:6)
  sets <- triangle_sets(trans, 3)
  expect_equal(sum(sets$full) + sum(sets$tail), sum(trans$payment_inflated))
  expect_equal(sets$tail, c(2, 0, 0))   # claim 1 pays in development period 4
  expect_equal(sum(sets$upper, na.rm = TRUE) + sum(sets$test, na.rm = TRUE),
               sum(sets$full))
  expect_equal(sum(sets$train, na.rm = TRUE) + sum(sets$vali, na.rm = TRUE),
               sum(sets$upper, na.rm = TRUE))
  expect_equal(claims_triangle(trans, 3, tail = TRUE)[1, 3], 2)
})

test_that("the dispersion is Pearson's (glmReserve) or Paper C's eq. (5)", {
  y <- unclass(cum2incr(GenIns))
  odp <- ccodp_fit(y)
  m <- glmReserve(GenIns)$model
  # glmReserve's glm stops at epsilon 1e-8, ccodp_fit at 1e-12
  expect_equal(odp$phi_pearson,
               with(m, sum(weights * residuals^2) / df.residual),
               tolerance = 1e-4)
  expect_equal(odp$phi_deviance, deviance(m) / df.residual(m),
               tolerance = 1e-8)
  expect_equal(odp$phi, odp$phi_deviance)
  expect_equal(odp$df, 55 - 19)          # |D_I| - (I + J), I = 10, J = 9
})

test_that("the chain ladder gives the ccODP reserves", {
  y <- unclass(cum2incr(GenIns))
  expect_equal(unname(cl_reserves(y)), unname(ccodp_fit(y)$reserve_o),
               tolerance = 1e-8)
})

test_that("the ODP sample is phi times a Poisson count on the cells", {
  set.seed(1)
  cells <- !is.na(upper_triangle(matrix(1, 4, 4)))
  y <- odp_sample(matrix(10, 4, 4), 2.5, cells)
  expect_true(all(is.na(y[!cells])))
  expect_equal(y[cells] / 2.5, round(y[cells] / 2.5))
  x <- replicate(4000, odp_sample(matrix(10, 1, 1), 2.5, TRUE)[1, 1])
  expect_equal(mean(x), 10, tolerance = 0.03)         # mean mu
  expect_equal(var(x), 25, tolerance = 0.1)           # variance phi times mu
})

test_that("the E&V bootstrap of zero residuals gives the CL reserves", {
  y <- unclass(cum2incr(GenIns))
  odp <- ccodp_fit(y)
  odp$y <- ifelse(odp$cells, odp$mu, NA)          # Pearson residuals 0
  boot <- ev_bootstrap(odp, 2)
  expect_equal(unname(boot[1, ]), unname(odp$reserve_o), tolerance = 1e-8)
  expect_equal(unname(boot[2, ]), unname(odp$reserve_o), tolerance = 1e-8)
})

test_that("the RMSEP adds the process and the bootstrap variance", {
  boot <- cbind(0, c(1, 3), c(2, 2))    # accident period 1 has no reserve
  tab <- rmsep_table("x", 2, c(0, 2, 2), boot)
  expect_equal(tab$origin, c("2", "3", "total"))
  expect_equal(tab$rmsep, sqrt(2 * c(2, 2, 4) + c(2, 0, 2)))
  tab <- rmsep_table("x", 2, c(0, 2, 2), boot, factor = 1.5)
  expect_equal(tab$rmsep, sqrt(2 * c(2, 2, 4) + 1.5 * c(2, 0, 2)))
})

test_that("rolling-origin partitions split the observed cells", {
  parts <- rolling_origin(upper_triangle(matrix(1, 20, 20)), c(5, 2), 2, 2)
  expect_equal(sapply(parts, function(p) p$origin), c(15, 18, 20))
  for (p in parts) {
    known <- !is.na(p$y)
    expect_false(any(p$train & p$vali))
    expect_true(all((p$train | p$vali) == known))
    expect_true(all(rowSums(p$train) > 0) && all(colSums(p$train) > 0))
    if (!p$final) expect_false(any(known & !is.na(p$test)))
  }
})

test_that("the rolling origin of a 12 x 12 triangle (the six LoBs)", {
  # config.yml datasets lob6: test partitions hold out the latest 3 and 1
  # calendar years, validation the latest one except the first period
  parts <- rolling_origin(upper_triangle(matrix(1, 12, 12)), c(3, 1), 1, 1)
  expect_equal(sapply(parts, function(p) p$origin), c(9, 11, 12))
  expect_equal(sapply(parts, function(p) sum(p$vali)), c(7, 9, 10))
  expect_equal(sapply(parts, function(p) sum(!is.na(p$test))), c(21, 10, 0))
})

test_that("the bCCNN grid has 2,880 uniquely named runs", {
  # the settings of config.yml bccnn$grid: 4 x 2 x 3 x 3 x 2 combinations,
  # 20 seeds
  grid_cfg <- list(hidden = list(20, c(20, 15), c(20, 15, 10), c(40, 30, 20)),
                   activation = c("tanh", "relu"),
                   dropout = c(0, 0.1, 0.2),
                   optimizers = c("rmsprop", "adam", "sgd_momentum"),
                   learning_rate = list(rmsprop = 0.001,
                                        adam = 0.002,
                                        sgd_momentum = 0.003),
                   momentum = 0.9,
                   batch_size = c(0, 64),
                   seeds = 20)
  runs <- bccnn_grid_runs(grid_cfg, 2026)
  expect_length(runs, 2880)
  expect_equal(anyDuplicated(names(runs)), 0)
  expect_equal(names(runs)[c(1, 2880)],
               c("grid_20_tanh_d0_rmsprop_bfull_s2026",
                 "grid_40-30-20_relu_d0.2_sgd_momentum_b64_s2045"))
  # the seed runs fastest, the hidden layers slowest; 0 = full batch (NULL)
  expect_equal(unname(sapply(runs[1:20], `[[`, "seed")), 2026:2045)
  expect_null(runs[[1]]$batch_size)
  expect_equal(runs[[2880]],
               list(hidden = c(40, 30, 20), activation = "relu",
                    dropout = 0.2, trainable = FALSE,
                    optimizer = "sgd_momentum", learning_rate = 0.003,
                    momentum = 0.9, batch_size = 64, seed = 2045))
})

test_that("bccnn_fit keeps the triangle, the losses and the seconds per step", {
  y <- unclass(cum2incr(GenIns))
  odp <- ccodp_fit(y)
  fit_nn <- with_stand_ins(bccnn_fit, keras_stand_ins)
  nn <- fit_nn(odp, 3, list(), track = list(vali = y))
  h <- nn$history
  expect_named(h, c("epoch", "train_dropout", "train", "vali", "vali_pred",
                    "time", "time_predict"))
  expect_equal(h$epoch, 0:3)
  # epoch 0 is the ccODP start: no step, the first prediction of the triangle
  expect_equal(is.na(h$time), c(TRUE, FALSE, FALSE, FALSE))
  expect_true(all(h$time[-1] >= 0) && all(h$time_predict >= 0))
  expect_equal(h$train[1], odp$deviance)
  expect_equal(h$vali, h$train)
  expect_equal(h$vali_pred, (1 + 0:3 / 100) * sum(odp$mu[odp$cells]))
  expect_length(nn$mu_path, 4)
  expect_equal(nn$mu, 1.03 * odp$mu)
  expect_named(nn$time, c("build", "fit", "total"))
  expect_true(all(nn$time >= 0))
  # no steps: the ccODP start
  nn <- fit_nn(odp, 0, list(), track = list())
  expect_equal(nn$history$epoch, 0)
  expect_equal(nn$mu, odp$mu)
})

test_that("the seconds per epoch of a run are kept in milliseconds", {
  h <- data.frame(epoch = 0:2,
                  vali = 1,
                  time = c(NA, 0.0514, 2),
                  time_predict = c(0.1, 0.0026, 0.0004))
  x <- epoch_ms(epoch_time("final", "refit", h))
  expect_named(x, c("partition", "fit", "epoch", "time", "time_predict"))
  expect_identical(x$time, c(NA, 51L, 2000L))
  expect_identical(x$time_predict, c(100L, 3L, 0L))
})

test_that("rolling_origin_fit scores the test partitions and keeps the times", {
  # stand-in for bccnn_fit(): the validation loss is lowest at step 2, the
  # test loss of step e is 10 + e, the Keras fit takes 0.4 s per step
  calls <- NULL
  stub <- function(odp, epochs, param, track) {
    calls <<- rbind(calls, data.frame(cells = sum(odp$cells), epochs = epochs))
    h <- data.frame(epoch = 0:epochs,
                    vali = (0:epochs - 2)^2,
                    test = 10 + 0:epochs,
                    test_pred = 100 + 0:epochs,
                    time = c(NA, rep(0.02, epochs)),
                    time_predict = 0.001)
    mu_path <- lapply(0:epochs, function(e) odp$mu + e)
    list(mu = mu_path[[epochs + 1]],
         history = h,
         mu_path = mu_path,
         time = c(build = 1, fit = 0.4 * epochs, total = 9))
  }
  ro_fit <- with_stand_ins(rolling_origin_fit, list(bccnn_fit = stub))
  y <- unclass(cum2incr(GenIns))
  parts <- rolling_origin(y, c(3, 1), 1, 1)        # valuation years 7, 9, 10
  n_obs <- sapply(parts, function(p) sum(!is.na(p$y)))
  n_train <- sapply(parts, function(p) sum(p$train))
  #
  # refit: the early-stopping run of 5 steps on the training cells, then at
  # a test partition the chain ladder of its valuation date trained for the
  # 2 steps
  ro <- ro_fit(parts, NULL, list(), 5, "refit")
  expect_equal(calls$epochs, c(5, 2, 5, 2, 5))
  expect_equal(calls$cells,
               c(n_train[1], n_obs[1], n_train[2], n_obs[2], n_train[3]))
  s <- ro$summary
  expect_equal(s$partition, c("1", "2", "final"))
  expect_equal(s$best_epoch, c(2, 2, 2))
  expect_equal(s$test_loss_bCCNN, c(12, 12, NA))
  expect_equal(s$test_bCCNN, c(102, 102, NA))
  expect_equal(s$test_loss_ccODP_train, c(10, 10, NA))
  expect_equal(s$time_build, c(1, 1, 1))
  expect_equal(s$time_early_stop, c(2, 2, 2))
  expect_equal(s$time_refit, c(0.8, 0.8, NA))
  expect_equal(ro$time_fit, 3 * 2 + 2 * 0.8)       # all Keras fits
  expect_named(ro$epoch_time,
               c("partition", "fit", "epoch", "time", "time_predict"))
  expect_equal(as.vector(table(ro$epoch_time$partition, ro$epoch_time$fit)),
               c(6, 6, 6, 3, 3, 0))                # early_stop, then refit
  expect_length(ro$mu_test, 2)
  expect_equal(ro$final$best_epoch, 2)
  expect_length(ro$final$mu_path, 6)
  #
  # partition: the early-stopped network of the partition, no refit
  calls <- NULL
  ro <- ro_fit(parts, NULL, list(), 5, "partition")
  expect_equal(calls$epochs, c(5, 5, 5))
  expect_equal(ro$summary$test_loss_bCCNN, c(12, 12, NA))
  expect_true(all(is.na(ro$summary$time_refit)))
  expect_equal(ro$time_fit, 3 * 2)
  expect_true(all(ro$epoch_time$fit == "early_stop"))
  expect_equal(ro$mu_test[[1]],
               ccodp_fit(parts[[1]]$y, parts[[1]]$train)$mu + 2)
  # the test partitions only (hyperparameter search): no final network
  expect_null(ro_fit(parts[1:2], NULL, list(), 5, "refit")$final)
})

test_that("the bCCNN bootstrap refits triangle k with the seed seed + k", {
  # stand-in for bccnn_fit(): the ccODP of the bootstrap triangle, a Keras
  # fit of 0.5 s
  seeds <- NULL
  stub <- function(odp, epochs, param, track) {
    seeds <<- c(seeds, param$seed)
    list(mu = odp$mu, time = c(build = 1, fit = 0.5, total = 2))
  }
  boot_nn <- with_stand_ins(bccnn_bootstrap, list(bccnn_fit = stub))
  odp <- ccodp_fit(unclass(cum2incr(GenIns)))
  set.seed(1)
  y_boot <- replicate(4, odp_sample(odp$mu, 1000, odp$cells), simplify = FALSE)
  boot <- boot_nn(y_boot, 3:4, odp$cells, 7, list(seed = 100))
  expect_equal(seeds, c(103, 104))
  expect_equal(dim(boot$reserves), c(2, 10))
  expect_equal(unname(boot$reserves[2, ]),
               unname(ccodp_fit(y_boot[[4]], odp$cells)$reserve_o))
  # seconds per refit: by the clock and of its Keras fit
  expect_length(boot$time, 2)
  expect_true(all(boot$time >= 0))
  expect_equal(boot$time_fit, c(0.5, 0.5))
})

test_that("periods without payments are masked", {
  # the cells of the periods with no payments in y, fitted or not
  m <- matrix(1, 4, 4)
  y <- upper_triangle(matrix(c(1, 0, 1, 1), 4, 4))  # nothing paid in row 2
  y[1, 4] <- 0                                     # ... and in column 4
  masked <- mask_zero_periods(m, y)
  expect_true(all(is.na(masked[2, ])) && all(is.na(masked[, 4])))
  expect_equal(sum(is.na(masked)), 7)
  #
  # 20 x 20 triangle with payments in every cell: no cell is masked
  y <- matrix(1, 20, 20)
  parts <- rolling_origin(upper_triangle(y), c(5, 2), 2, 2)
  expect_identical(mask_partitions(parts), parts)
  #
  # partition 1 (valuation date 15): development period 13 pays in its
  # validation cell (3, 13) only, development period 14 in its test cells only
  y[, 13:14] <- 0
  y[3, 13] <- 50
  y[3:7, 14] <- 40
  parts <- rolling_origin(upper_triangle(y), c(5, 2), 2, 2)
  masked <- mask_partitions(parts)
  p1 <- parts[[1]]
  m1 <- masked[[1]]
  expect_true(p1$vali[3, 13] && !m1$vali[3, 13])
  expect_equal(sum(m1$vali), sum(p1$vali) - 1)
  # the chain ladder at 15 knows period 13 (test cells kept), not period 14
  expect_equal(which(is.na(m1$test) & !is.na(p1$test), arr.ind = TRUE)[, 2],
               rep(14, 5))
  expect_identical(m1[c("y", "train")], p1[c("y", "train")])
  # scored against the ccODP of the training cells, cell (3, 13) dominates
  odp <- suppressWarnings(ccodp_fit(p1$y, cells = p1$train))
  expect_gt(poisson_deviance(ifelse(p1$vali, p1$y, NA), odp$mu),
            1000 * poisson_deviance(ifelse(m1$vali, p1$y, NA), odp$mu))
  # by the final partition both periods have payments: no cell is masked
  expect_identical(masked[[3]], parts[[3]])
})
