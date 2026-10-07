##################################################################
#########  bCCNN hyperparameters chosen on the rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2, 4.1
##################################################################
#
# The test partitions of rolling_origin_sets() (valuation years 15 and 18 of
# 20) are the folds of a time-series cross-validation: on each, the whole
# procedure is replayed at the earlier valuation date (ccODP start on the
# training cells, early stopping on the partition's own validation cells,
# refit at that date for the chosen steps) and scored on the calendar years
# that followed. The score of a hyperparameter set is the pooled test
# deviance per test cell (Al-Mudafer et al. eq. (4.4)), averaged over seeds
# ("Averaging the error of these runs reduces the impact of random weight
# initialisations", Al-Mudafer et al. 2021, PDF p. 16, Section 4.1). The set
# with the lowest score is kept; the final partition then chooses the number
# of steps of the reported model as before (bccnn_calibrate()).
#
# Not K-fold: the folds overlap, are ordered in time and do not cover the
# triangle; a K-fold split of the cells is infeasible with the ccODP start
# (thesis/claude_explainer-bccnn-rolling-origin-versus-k-fold-cross-
# validation.pdf, Section 4.3).
#
# Once hyperparameters are chosen on it, the test error is a validation
# score, no longer an unbiased estimate of the error of the chosen model.
# The true lower triangle of the simulation stays the independent check.


###############################################
#########  hyperparameter sets
###############################################

# arguments of bccnn_model() / fit_bccnn() that can be tuned
bccnn_tunable <- function() {
  c(setdiff(names(formals(bccnn_model)), c("odp", "seed")), "batch_size")
}

check_hp <- function(hp) {
  bad <- setdiff(names(hp), bccnn_tunable())
  if (length(bad) > 0) {
    stop("not a bCCNN hyperparameter: ", paste(bad, collapse = ", "),
         " (tunable: ", paste(bccnn_tunable(), collapse = ", "), ")")
  }
  invisible(hp)
}

# "dropout=0.1, q=20-15-10": key for the cache and the tables
hp_label <- function(hp) {
  if (length(hp) == 0) return("(fixed settings)")
  paste0(names(hp), "=",
         vapply(hp, function(v) paste(v, collapse = "-"), ""),
         collapse = ", ")
}

# every combination of the candidate values: list of hyperparameter sets
hp_grid <- function(candidates) {
  candidates <- lapply(candidates, as.list)
  idx <- expand.grid(lapply(candidates, seq_along), KEEP.OUT.ATTRS = FALSE)
  lapply(seq_len(nrow(idx)), function(r) {
    Map(function(vals, k) vals[[k]], candidates, unlist(idx[r, ]))
  })
}


###############################################
#########  score of one hyperparameter set
###############################################

# Time-series cross-validation score of `hp` (named list of bccnn_model() /
# fit_bccnn() arguments, overriding `fixed`). Every test partition of
# `parts` is fitted once per seed with bccnn_ro_partition(); the final
# partition is not needed. score = mean over seeds of
#   sum_tau test deviance(tau) / sum_tau n_test(tau),
# the bCCNN row of bccnn_rolling_origin()'s test_error. score_ccODP is the
# same for the chain ladder at each valuation date (no seed, no hp).
bccnn_tscv_score <- function(parts,
                             hp = list(),
                             fixed = list(),
                             seeds = 2026,
                             max_epochs = 1000,
                             scale = 1,
                             phi = "deviance",
                             final_fit = "refit",
                             fit_partition = bccnn_ro_partition) {
  check_hp(hp)
  tests <- Filter(function(p) !p$final, parts)
  if (length(tests) == 0) stop("no test partitions: use test_periods")

  runs <- do.call(rbind, lapply(seeds, function(s) {
    args <- modifyList(modifyList(fixed, hp), list(seed = s))
    do.call(rbind, lapply(tests, function(p) {
      f <- do.call(fit_partition,
                   c(list(p, max_epochs = max_epochs, scale = scale,
                          phi = phi, final_fit = final_fit), args))
      data.frame(seed = s, origin = f$origin, n_test = f$n_test,
                 best_epoch = f$best_epoch,
                 test_loss_bCCNN = f$test[["test_loss_bCCNN"]],
                 test_loss_ccODP = f$test[["test_loss_ccODP"]])
    }))
  }))

  per_seed <- vapply(split(runs, runs$seed), function(r) {
    sum(r$test_loss_bCCNN) / sum(r$n_test)
  }, 0)
  first <- runs[runs$seed == seeds[1], ]
  list(hp = hp,
       label = hp_label(hp),
       score = mean(per_seed),
       score_sd = if (length(per_seed) > 1) sd(per_seed) else NA_real_,
       score_ccODP = sum(first$test_loss_ccODP) / sum(first$n_test),
       per_seed = per_seed,
       runs = runs)
}

# one row per scored hyperparameter set, best first
tuning_table <- function(scored) {
  rows <- lapply(scored, function(x) {
    hp <- lapply(x$hp, function(v) paste(v, collapse = "-"))
    steps <- tapply(x$runs$best_epoch, x$runs$origin, mean)
    data.frame(hp, label = x$label,
               score = x$score, score_sd = x$score_sd,
               n_seeds = length(x$per_seed),
               score_ccODP = x$score_ccODP,
               ratio_to_ccODP = x$score / x$score_ccODP,
               as.list(setNames(steps, paste0("mean_steps_", names(steps)))),
               check.names = FALSE)
  })
  # sets of a successive search can tune different names: fill the gaps
  cols <- unique(unlist(lapply(rows, names)))
  rows <- lapply(rows, function(r) {
    r[setdiff(cols, names(r))] <- NA
    r[cols]
  })
  tab <- do.call(rbind, rows)
  tab <- tab[order(tab$score), ]
  rownames(tab) <- NULL
  tab
}


###############################################
#########  searches
###############################################

# Every combination of `candidates` (named list; each element the values to
# try, e.g. list(dropout = c(0, 0.1), q = list(c(20, 15, 10), c(40, 30, 20)))).
# `...` goes to bccnn_tscv_score().
bccnn_grid_search <- function(parts, candidates, ..., verbose = TRUE) {
  sets <- hp_grid(candidates)
  scored <- lapply(seq_along(sets), function(k) {
    if (verbose) message(sprintf("[%d/%d] %s", k, length(sets),
                                 hp_label(sets[[k]])))
    bccnn_tscv_score(parts, sets[[k]], ...)
  })
  best <- scored[[which.min(vapply(scored, `[[`, 0, "score"))]]
  list(method = "grid", best = best$hp, best_score = best$score,
       table = tuning_table(scored), scored = scored)
}

# Al-Mudafer et al. (2021, PDF p. 12, Section 3.2): starting from `start`,
# tune one hyperparameter at a time in `order`, the others held at their
# current best ("Using θ initial and keeping all other hyper-parameters
# fixed, use Grid Search to test all desired values ... Select the
# coefficient with the lowest test error"). The current value stays unless
# a candidate scores lower. Sets already scored are not refitted.
bccnn_successive_search <- function(parts, start, candidates,
                                    order = names(candidates), ...,
                                    verbose = TRUE) {
  check_hp(start)
  stopifnot(all(order %in% names(candidates)))
  cache <- list()
  score <- function(hp) {
    key <- hp_label(hp)
    if (is.null(cache[[key]])) {
      if (verbose) message(sprintf("[%d] %s", length(cache) + 1, key))
      cache[[key]] <<- bccnn_tscv_score(parts, hp, ...)
    }
    cache[[key]]
  }

  current <- start
  path <- data.frame(step = 0, tuned = "start", label = hp_label(current),
                     score = score(current)$score)
  for (name in order) {
    values <- as.list(candidates[[name]])
    if (any(vapply(values, is.null, TRUE))) stop("NULL candidate for ", name)
    if (!is.null(current[[name]]) &&
        !any(vapply(values, identical, TRUE, current[[name]]))) {
      values <- c(list(current[[name]]), values)
    }
    trials <- lapply(values, function(v) {
      hp <- current
      hp[[name]] <- v
      hp
    })
    s <- vapply(trials, function(hp) score(hp)$score, 0)
    current <- trials[[which.min(s)]]
    path <- rbind(path, data.frame(step = nrow(path), tuned = name,
                                   label = hp_label(current), score = min(s)))
  }
  list(method = "successive", best = current,
       best_score = score(current)$score,
       table = tuning_table(cache), path = path, scored = unname(cache))
}
