##########################################
#########  hyperparameter search on rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2 and 4.1
##########################################

## Shared by the bCCNN (R/bccnn_tuning.R) and the NN chain ladder
## (R/nncl_tuning.R). A hyperparameter set is scored by time-series
## cross-validation: at each earlier valuation date of the rolling origin
## (test partitions) the whole fitting procedure is replayed on what was
## known then and scored on the calendar years that followed; the losses are
## pooled per test cell over the valuation dates (Al-Mudafer et al. eq.
## (4.4)) and averaged over seeds ("Averaging the error of these runs reduces
## the impact of random weight initialisations", Al-Mudafer et al. 2021, PDF
## p. 16). The set with the lowest score is kept.
##
## Not K-fold cross-validation: the folds overlap, are ordered in time and do
## not cover the triangle (thesis/claude_explainer-bccnn-rolling-origin-
## versus-k-fold-cross-validation.pdf). Once hyperparameters are chosen on
## it, the test error is a validation score: the true lower triangle of the
## simulation stays the independent check.

## "dropout=0.1, hidden=20-15-10": the key of a set in the tables and cache
hp_label <- function(hp) {
  if (length(hp) == 0) return("(defaults)")
  paste0(names(hp), "=",
         vapply(hp, function(v) paste(v, collapse = "-"), ""),
         collapse = ", ")
}

## every combination of the candidate values: a list of hyperparameter sets
hp_grid <- function(candidates) {
  candidates <- lapply(candidates, as.list)
  idx <- expand.grid(lapply(candidates, seq_along), KEEP.OUT.ATTRS = FALSE)
  lapply(seq_len(nrow(idx)), function(r) {
    Map(function(vals, k) vals[[k]], candidates, unlist(idx[r, ]))
  })
}

## stops if hp names an argument the model does not take
hp_check <- function(hp, tunable) {
  bad <- setdiff(names(hp), tunable)
  if (length(bad) > 0) {
    stop("not a tunable hyperparameter: ", paste(bad, collapse = ", "),
         " (tunable: ", paste(tunable, collapse = ", "), ")")
  }
  invisible(hp)
}

## score of a set from its runs (data frame, one row per seed and valuation
## date: seed, origin, n_test, loss, loss_baseline, steps): per seed the
## losses pooled per test cell, then the mean over the seeds; a diverged
## run (non-finite loss) scores Inf, so it is never chosen
tscv_summary <- function(runs, hp) {
  per_seed <- vapply(split(runs, runs$seed), function(r) {
    sum(r$loss) / sum(r$n_test)
  }, 0)
  score <- mean(per_seed)
  if (!is.finite(score)) score <- Inf
  first <- runs[runs$seed == runs$seed[1], ]
  list(hp = hp,
       label = hp_label(hp),
       score = score,
       score_sd = if (length(per_seed) > 1) sd(per_seed) else NA_real_,
       score_baseline = sum(first$loss_baseline) / sum(first$n_test),
       per_seed = per_seed,
       runs = runs)
}

## one row per scored set, best first
tuning_table <- function(scored) {
  rows <- lapply(scored, function(x) {
    hp <- lapply(x$hp, function(v) paste(v, collapse = "-"))
    steps <- tapply(x$runs$steps, x$runs$origin, mean)
    data.frame(hp,
               label = x$label,
               score = x$score,
               score_sd = x$score_sd,
               n_seeds = length(x$per_seed),
               score_baseline = x$score_baseline,
               ratio_to_baseline = x$score / x$score_baseline,
               as.list(setNames(steps, paste0("mean_steps_", names(steps)))),
               check.names = FALSE)
  })
  # sets of a successive search can name different hyperparameters
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

## search over 'candidates' (named list, each element the values to try),
## score_fn(hp) giving tscv_summary() of a set:
## method "grid": every combination;
## method "successive" (Al-Mudafer et al. 2021, PDF p. 12, Section 3.2):
## starting from 'start', one hyperparameter at a time in 'order', the others
## held at their current best ("Using θ initial and keeping all other
## hyper-parameters fixed, use Grid Search to test all desired values ...
## Select the coefficient with the lowest test error"); the current value
## stays unless a candidate scores lower.
## A scored set is not refitted; with cache_dir it is saved there and read
## back on the next call, so a stopped search resumes where it stopped.
tune_search <- function(score_fn,
                        candidates,
                        method = "successive",
                        start = list(),
                        order = names(candidates),
                        cache_dir = NULL,
                        verbose = TRUE) {
  if (!is.null(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  cache <- list()
  score <- function(hp) {
    key <- hp_label(hp)
    if (is.null(cache[[key]])) {
      file <- if (!is.null(cache_dir)) {
        file.path(cache_dir,
                  paste0(gsub("[^A-Za-z0-9.=-]+", "_", key), ".rds"))
      }
      if (!is.null(file) && file.exists(file)) {
        cache[[key]] <<- readRDS(file)
        if (verbose) message("[cached] ", key)
      } else {
        if (verbose) message(sprintf("[%d] %s", length(cache) + 1, key))
        t0 <- Sys.time()
        res <- score_fn(hp)
        res$run_time <- as.numeric(Sys.time() - t0, units = "secs")
        if (!is.null(file)) saveRDS(res, file)
        cache[[key]] <<- res
      }
      if (verbose) message(sprintf("    score %.6g (baseline %.6g)",
                                   cache[[key]]$score,
                                   cache[[key]]$score_baseline))
    }
    cache[[key]]
  }

  if (method == "grid") {
    sets <- hp_grid(candidates)
    s <- vapply(sets, function(hp) score(hp)$score, 0)
    best <- sets[[which.min(s)]]
    path <- NULL
  } else if (method == "successive") {
    stopifnot(all(order %in% names(candidates)))
    best <- start
    path <- data.frame(step = 0, tuned = "start", label = hp_label(best),
                       score = score(best)$score)
    for (name in order) {
      values <- as.list(candidates[[name]])
      if (any(vapply(values, is.null, TRUE))) {
        stop("NULL candidate for ", name)
      }
      if (!is.null(best[[name]]) &&
            !any(vapply(values, identical, TRUE, best[[name]]))) {
        values <- c(list(best[[name]]), values)
      }
      trials <- lapply(values, function(v) {
        hp <- best
        hp[[name]] <- v
        hp
      })
      s <- vapply(trials, function(hp) score(hp)$score, 0)
      best <- trials[[which.min(s)]]
      path <- rbind(path, data.frame(step = nrow(path), tuned = name,
                                     label = hp_label(best), score = min(s)))
    }
  } else {
    stop("method must be grid or successive")
  }
  list(method = method,
       best = best,
       best_score = score(best)$score,
       table = tuning_table(cache),
       path = path,
       scored = unname(cache))
}

## the runs of all scored sets, one data frame
tuning_runs <- function(search) {
  do.call(rbind, lapply(search$scored, function(x) {
    cbind(label = x$label, x$runs)
  }))
}

## the chosen set as a two-column table
tuning_best <- function(search) {
  data.frame(hyperparameter = names(search$best),
             value = vapply(search$best, paste, "", collapse = ", "))
}
