############################# TRIANGLE MANIPULATION FUNCTION ##################

# Function to create a triangle for visualisation
# of claim payments over development periods
# Producing incremental triangles 
triangle_vis <- function(tr, runoff = 0L, n_dev) {
  dev <- tr$payment_period - tr$occurrence_period + 1L
  if (runoff == 1) dev[dev > n_dev] <- n_dev
  keep <- dev >= 1L & dev <= n_dev
  m <- matrix(0, n_dev, n_dev)
  cells <- rowsum(tr$payment_inflated[keep],
                  group = (dev[keep] - 1L) * n_dev + tr$occurrence_period[keep])
  m[as.integer((rownames(cells)))] <- cells[, 1]
  out <- data.frame(AY = 1:n_dev, m)
  colnames(out) <- c("AY", 1:n_dev)
  out
}


# Saves reserves plot 
save_reserve_tables <- function(fit, name) {
  data.table::fwrite(fit$by_origin,
                     file.path(paths$tables, paste0(name, "_by_origin.csv")))
  data.table::fwrite(as.list(fit$total),
                     file.path(paths$tables, paste0(name, "_total.csv")))
}
## ----- 0a. triangle helpers --------------------------------------------------
## Fill an n x n matrix from cell indices. M[cbind(row, col)], never a linear
## index: R fills matrices column by column, so a linear index transposes.
square <- function(i, j, v, n = n) {
  a <- data.table(i = i, j = j, v = v)[j <= n, .(v = sum(v)), by = .(i, j)]
  mat <- matrix(0, n, n, dimnames = list(origin = 1:n, dev = 1:n))
  mat[cbind(a$i, a$j)] <- a$v
  mat
}
#future masking function
fut_mask  <- function(n) { # future cells, i + j > n + 1
  outer(1:n, 1:n, "+") > n + 1
}
# Upper triangle functions

upper     <- function(m) {
  m[fut_mask(nrow(m))] <- NA
  m
}

# Cumulative upper triangle function
upper_cum <- function(m) {
  incr2cum(as.triangle(upper(m))) # observed cumulative triangle
}

# Transfer cumulative triangle to incremental triangle
cum_to_inc <- function(m) {
  m <- unname(as.matrix(m))
  cbind(m[, 1], m[, -1, drop = FALSE] - m[, -ncol(m), drop = FALSE])
}


fut_cells <- function(m) {
  m <- unname(as.matrix(m))
  m[!fut_mask(nrow(m))] <- NA
  m
}

# Sum of v by origin, over rows 'keep'
origin_sum <- function(i, v, keep, n = n) {
  o <- numeric(n)
  if (any(keep)) {
    a <- rowsum(v[keep], i[keep])
    o[as.integer(rownames(a))] <- a[, 1]
  }
  o
}
## Truth for one triangle: the lower triangle (to the last development column)
## and the full run-off (lower triangle + payments beyond the last column).
make_truth <- function(name, inc_full, tail_o) {
  f <- fut_mask(nrow(inc_full))
  last_o <- rowSums(inc_full * f)
  list(name = name, last = sum(last_o), last_o = last_o,
       full = sum(last_o + tail_o), full_o = last_o + tail_o,
       cells = ifelse(f, inc_full, NA))
}


## ----- 0b. training / validation / test triangles -----------------------------

#' Full, training, validation and test triangles from individual claims
#'
#' Paper C (Gabrielli, Richman & Wuthrich 2020, Section 3.3.1 and Listing 2)
#' chooses the number of gradient-descent steps of the neural network on a
#' 50/50 split of the individual CLAIMS, not of the triangle cells: the upper
#' triangle has too few cells to hold some back. The claims, ordered by
#' accident period, are allocated alternately to a training and a validation
#' portfolio, and each portfolio is aggregated to its own triangle. Both
#' halves then hold (almost) the same number of claims in every accident
#' period, so the cross-classified parameters -- which carry the portfolio
#' volume -- transfer from one half to the other (except where a half has no
#' payments at all, e.g. in the sparse last development periods; see
#' bccnn_validation()).
#'
#' The triangles hold development periods 1..n_dev only, so every observed
#' cell (origin + dev <= n_dev + 1) holds exactly the payments made up to the
#' valuation date, period n_dev. Payments after development period n_dev
#' (the simulator's triangle.csv folds them into the last column, which for
#' accident period 1 is an observed cell) are returned separately as tail_o.
#'
#' The test data is the lower triangle of the full portfolio: the true
#' outstanding payments to development period n_dev, known here only because
#' the data is simulated. It is used to back-test reserves, never to fit or to
#' choose the stopping time.
#'
#' @param transactions one row per payment with claim_no, occurrence_period,
#'   payment_period and payment_inflated (the simulator's transactions.csv).
#' @param n_dev number of accident periods = development periods (20 annual).
#' @param claims optional table with claim_no and occurrence_period (claims.csv)
#'   listing the claims to allocate; by default the claims in transactions.
#' @return a list of n_dev x n_dev incremental matrices (rows = accident
#'   period, columns = development period):
#'   * full        all claims, observed and future cells;
#'   * upper       observed part of full (future cells NA): the data to fit;
#'   * test        future part of full (observed cells NA): the true reserves;
#'   * train, vali observed upper triangles of the two halves (future NA);
#'   * train_full, vali_full  the two halves' full squares;
#'   plus tail_o (payments after development period n_dev, by origin; in no
#'   triangle), alloc (claim_no, occurrence_period, half: 1 = train,
#'   2 = vali) and n_claims (claims by accident period and half).
triangle_sets <- function(transactions, n_dev, claims = NULL) {
  need <- c("claim_no", "occurrence_period", "payment_period", "payment_inflated")
  miss <- setdiff(need, names(transactions))
  if (length(miss) > 0) {
    stop("triangle_sets(): transactions lacks column(s) ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  tr <- as.data.frame(transactions)[, need]

  alloc <- if (is.null(claims)) tr[, c("claim_no", "occurrence_period")] else
    as.data.frame(claims)[, c("claim_no", "occurrence_period")]
  alloc <- alloc[!duplicated(alloc$claim_no), ]
  alloc <- alloc[order(alloc$occurrence_period, alloc$claim_no), ]
  alloc$half <- rep(1:2, length.out = nrow(alloc))   # Paper C Listing 2
  rownames(alloc) <- NULL

  hit <- match(tr$claim_no, alloc$claim_no)
  if (anyNA(hit)) {
    stop("triangle_sets(): ", sum(is.na(hit)),
         " payment(s) belong to claims that are not in `claims`", call. = FALSE)
  }
  if (any(alloc$occurrence_period[hit] != tr$occurrence_period)) {
    stop("triangle_sets(): claims and transactions disagree on occurrence_period",
         call. = FALSE)
  }
  half <- alloc$half[hit]

  # runoff = 0: development periods 1..n_dev only
  square_of <- function(keep) {
    m <- as.matrix(triangle_vis(tr[keep, , drop = FALSE], 0L, n_dev)[, -1])
    dimnames(m) <- list(origin = seq_len(n_dev), dev = seq_len(n_dev))
    m
  }
  full       <- square_of(rep(TRUE, nrow(tr)))
  train_full <- square_of(half == 1L)
  vali_full  <- square_of(half == 2L)
  stopifnot(isTRUE(all.equal(train_full + vali_full, full)))

  late <- tr$payment_period - tr$occurrence_period + 1L > n_dev
  tail_o <- origin_sum(tr$occurrence_period, tr$payment_inflated, late, n_dev)

  test <- fut_cells(full)
  dimnames(test) <- dimnames(full)
  list(full = full, upper = upper(full), test = test,
       train = upper(train_full), vali = upper(vali_full),
       train_full = train_full, vali_full = vali_full,
       tail_o = tail_o, alloc = alloc,
       n_claims = table(origin = alloc$occurrence_period,
                        half = c("train", "vali")[alloc$half]))
}


#' Rolling-origin training / validation / test partitions of a triangle
#'
#' Al-Mudafer, Avanzi, Taylor & Wong (2021), Stochastic loss reserving with
#' mixture density neural networks (arXiv:2108.07924), Sections 3.1 and 4.3
#' and Figures 3 and 9. A loss triangle is extrapolated along calendar
#' periods, so the data is split sequentially, never at random:
#'
#' * a test partition moves the valuation date back to calendar period
#'   c = n - t: its data is the c x c triangle observed at c, and its test
#'   set is the next t calendar periods inside that c x c square (the part of
#'   the current upper triangle that a model fitted at c would forecast).
#'   Al-Mudafer et al. use two, t = 10 and t = 4 on a 40 x 40 triangle: the
#'   first tests long-term projection, the second recent trends. A model
#'   design's test error is the cell-weighted average over these partitions
#'   (their eq. (4.4));
#' * the final partition (their "Partition 3") is the whole upper triangle,
#'   with no test set: the chosen model is trained on it;
#' * in every partition the validation set, used for early stopping, is the
#'   latest vali_periods calendar periods of that partition's triangle, except
#'   the first `exclude` accident and development periods (their 3 and 3):
#'   those stay in training so that the latest accident periods and the latest
#'   development periods keep training data. The validation cells this removes
#'   at development periods 2..exclude are replaced by as many cells of those
#'   development periods from earlier accident periods, spread evenly (their
#'   "DQ2 and DQ3 validation points ... taken evenly from earlier AQs"). For a
#'   cross-classified model such as the bCCNN, the exclusions also guarantee
#'   that every accident and development period of the partition has a
#'   training cell, so the ccODP start can be fitted on the training cells.
#'
#' Only the data observed at the valuation date n is used: m is cut to its
#' upper triangle, so the true lower triangle can never leak in.
#'
#' @param m n x n incremental triangle (e.g. triangle_sets()$upper; a full
#'   square is cut to its upper triangle).
#' @param test_periods number of calendar periods held out by each test
#'   partition, e.g. c(5, 2) for a 20 x 20 triangle (Al-Mudafer et al.:
#'   c(10, 4) of 40). The final partition (no test set) is always added.
#' @param vali_periods number of latest calendar periods of each partition used
#'   for validation (Al-Mudafer et al.: 4 of 40).
#' @param exclude first accident and development periods kept out of the
#'   validation diagonals (Al-Mudafer et al.: 3); >= 1.
#' @return a list of partitions, test partitions first and the final one last.
#'   Each is a list:
#'   * origin  the partition's valuation calendar period c;
#'   * y       its c x c incremental triangle observed at c (future NA);
#'   * train, vali  c x c logical masks of the training and validation cells;
#'   * test    c x c matrix of the test values (NA elsewhere), NULL for the
#'             final partition;
#'   * role    c x c character matrix "train" / "validation" / "test" / NA;
#'   * final   TRUE for the final partition; n  the full triangle size.
rolling_origin_sets <- function(m, test_periods = c(5, 2), vali_periods = 2,
                                exclude = 2) {
  y <- upper(unname(as.matrix(m)))
  n <- nrow(y)
  if (ncol(y) != n) stop("rolling_origin_sets(): m must be square", call. = FALSE)
  if (exclude < 1 || vali_periods < 1 || any(test_periods < 1)) {
    stop("rolling_origin_sets(): exclude, vali_periods and test_periods must ",
         "be >= 1", call. = FALSE)
  }
  origins <- c(n - sort(test_periods, decreasing = TRUE), n)
  if (any(origins - vali_periods < 2 * exclude + 1)) {
    stop("rolling_origin_sets(): a partition of ", min(origins), " periods is ",
         "too small for ", vali_periods, " validation periods and exclude = ",
         exclude, call. = FALSE)
  }

  lapply(origins, function(c0) {
    idx <- seq_len(c0)
    ys <- y[idx, idx, drop = FALSE]   # c0 x c0 square, observed at n
    cal <- row(ys) + col(ys) - 1L     # calendar period of each cell
    known <- cal <= c0
    vali <- known & cal > c0 - vali_periods &
      row(ys) > exclude & col(ys) > exclude
    if (exclude >= 2) {
      # k cells at the centres of k equal bins of accident periods
      # lo..hi; hi keeps them off the validation diagonals
      k <- vali_periods * (exclude - 1L)
      lo <- exclude + 1
      hi <- c0 - vali_periods - exclude + 1
      rows <- round(lo + (hi - lo) * (seq_len(k) - 0.5) / k)
      devs <- rep(exclude:2, length.out = k)
      vali[cbind(rows, devs)] <- TRUE   # calendar <= c0 - vali_periods
    }
    train <- known & !vali
    test <- if (c0 < n) ifelse(cal > c0, ys, NA) else NULL
    role <- matrix(NA_character_, c0, c0)
    role[train] <- "train"
    role[vali] <- "validation"
    if (!is.null(test)) role[!is.na(test)] <- "test"
    list(origin = c0, y = ifelse(known, ys, NA), train = train, vali = vali,
         test = test, role = role, final = c0 == n, n = n)
  })
}


#' Long format of an n x n triangle: one row per cell
#'
#' @param m n x n matrix (NA allowed).
#' @return data.frame with origin, dev (both 1-based), value, and upper
#'   (TRUE for the observed cells origin + dev <= n + 1).
triangle_long <- function(m) {
  m <- unname(as.matrix(m))
  n <- nrow(m)
  data.frame(origin = as.vector(row(m)), dev = as.vector(col(m)),
             value = as.vector(m),
             upper = as.vector(row(m) + col(m) <= n + 1))
}
