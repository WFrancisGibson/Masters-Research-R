##########################################
#########  hyperparameter search on rolling-origin folds
#########  Al-Mudafer, Avanzi, Taylor & Wong (2021), Sections 3.2 and 4.1
##########################################

## shared by the bCCNN (R/bccnn_tuning.R) and the NN chain ladder
## (R/nncl_tuning.R): a hyperparameter set is fitted at the earlier valuation
## dates of the rolling origin (test partitions) and scored on the calendar
## years that followed, the losses pooled per test cell (their eq. (4.4)) and
## averaged over seeds (their p. 16); the set with the lowest score is kept

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

## hp names arguments of the model only: any other name would be ignored
## and its candidates would all score the same
hp_check <- function(hp, tunable) {
  stopifnot("not a tunable hyperparameter" = names(hp) %in% tunable)
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
## held at their current best; the current value stays unless a candidate
## scores lower (a tie, or all candidates diverged: no move).
## A scored set is not refitted; with cache_dir it is saved there (save_run()
## of R/runs.R) and read back on the next call, so a stopped search resumes
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
        res <- readRDS(file)
      } else {
        t0 <- Sys.time()
        res <- score_fn(hp)
        res$run_time <- as.numeric(Sys.time() - t0, units = "secs")
        if (!is.null(file)) save_run(res, file)
      }
      cache[[key]] <<- res
      if (verbose) {
        cat(sprintf("%s %s: score %.6g (baseline %.6g), %.0f s\n",
                    format(Sys.time(), "%H:%M"),
                    key,
                    res$score,
                    res$score_baseline,
                    res$run_time))
      }
    }
    cache[[key]]
  }

  if (method == "grid") {
    sets <- hp_grid(candidates)
    s <- vapply(sets, function(hp) score(hp)$score, 0)
    best <- sets[[which.min(s)]]
    path <- NULL
  } else {
    stopifnot(all(order %in% names(candidates)))
    best <- start
    path <- data.frame(step = 0, tuned = "start", label = hp_label(best),
                       score = score(best)$score)
    for (name in order) {
      values <- as.list(candidates[[name]])
      # hp[[name]] <- NULL would drop the hyperparameter from the set
      stopifnot("NULL candidate" = !vapply(values, is.null, TRUE))
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
      # which.min() takes the first of equal scores: move only if lower
      if (min(s) < score(best)$score) best <- trials[[which.min(s)]]
      path <- rbind(path, data.frame(step = nrow(path), tuned = name,
                                     label = hp_label(best),
                                     score = score(best)$score))
    }
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
