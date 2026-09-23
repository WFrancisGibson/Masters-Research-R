############################# TRIANGLE MANIPULATION FUNCTION ##################

# Function to create a triangle for visualisation
# of claim payments over development periods
make_triangle_vis <- function(tr, runoff = 0L, n_dev) {
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