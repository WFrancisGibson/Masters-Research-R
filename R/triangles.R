##########################################
#########  Claims reserving triangles
#########  Paper C: Gabrielli, Richman & Wuthrich (2020), Listings 2 and 3
#########  rolling origin: Al-Mudafer, Avanzi, Taylor & Wong (2021), Sec. 3.1
##########################################

## n x n incremental triangle of the payments (rows accident periods AY, columns
## development periods DY)
## tail = TRUE puts the payments after DY n into column n
claims_triangle <- function(trans, n, tail = FALSE) {
  ay <- trans$occurrence_period
  dy <- trans$payment_period - trans$occurrence_period + 1
  if (tail) dy <- pmin(dy, n)
  keep <- which(dy <= n)
  # add up the payments by cell
  # cell (AY, DY) is element (DY - 1) * n + AY of the n x n
  # matrix (column by column), and rowsum names its rows by that position
  cell <- (dy[keep] - 1) * n + ay[keep]
  paid <- rowsum(trans$payment_inflated[keep], cell)
  tri <- matrix(0, n, n, dimnames = list(origin = 1:n, dev = 1:n))
  tri[as.integer(rownames(paid))] <- paid[, 1]
  tri
}

## observed cells AY + DY <= n + 1 (upper triangle)
## and future cells (lower triangle)
upper_triangle <- function(tri) {
  tri[row(tri) + col(tri) > nrow(tri) + 1] <- NA
  tri
}
lower_triangle <- function(tri) {
  tri[row(tri) + col(tri) <= nrow(tri) + 1] <- NA
  tri
}

## the triangles of the simulated portfolio at the valuation date n
triangle_sets <- function(trans, n) {
  full <- claims_triangle(trans, n)
  # payments after development period n: in no triangle, reported apart
  late <- which(trans$payment_period - trans$occurrence_period + 1 > n)
  late_paid <- rowsum(trans$payment_inflated[late],
                      trans$occurrence_period[late])
  tail <- rep(0, n)
  tail[as.integer(rownames(late_paid))] <- late_paid[, 1]
  # Paper C Listing 2:
  # the claims, ordered by accident period, go alternately to a
  # training and a validation half, and each half gives its own triangle
  claims <- unique(trans[, c("claim_no", "occurrence_period")])
  claims <- claims[order(claims$occurrence_period, claims$claim_no), ]
  claims$vali <- rep(c(1, 2), length.out = nrow(claims))
  half <- claims$vali[match(trans$claim_no,
                            claims$claim_no)]   # half of each payment
  list(full  = full,
       upper = upper_triangle(full), # observed triangle: the data to fit
       test  = lower_triangle(full), # true outstanding payments
       train = upper_triangle(claims_triangle(trans[which(half == 1), ], n)),
       vali  = upper_triangle(claims_triangle(trans[which(half == 2), ], n)),
       tail  = tail)
}

## rolling-origin partitions of the observed triangle y
## (Al-Mudafer et al. 2021): test partitions at c0 = n - t
## (test set: the next t calendar periods), final one at c0 = n
rolling_origin <- function(y, test_periods, vali_periods, exclude) {
  n <- nrow(y)
  lapply(c(n - sort(test_periods, decreasing = TRUE), n), function(c0) {
    y0 <- unname(y[1:c0, 1:c0])
    cal <- row(y0) + col(y0) - 1               # calendar period of each cell
    # validation: the latest vali_periods calendar periods, except the cells
    # of the first 'exclude' accident and development periods (these stay in
    # training) ...
    vali <- cal <= c0 & cal > c0 - vali_periods &
      row(y0) > exclude & col(y0) > exclude
    # ... the vali_periods * (exclude - 1) excluded cells of DY 2..exclude are
    # replaced by cells of the same DY from older calendar periods, spread
    # evenly over the AYs
    if (exclude >= 2) {
      k <- vali_periods * (exclude - 1)
      lo <- exclude + 1
      hi <- c0 - vali_periods - exclude + 1
      ay <- round(lo + (hi - lo) * (1:k - 0.5) / k)
      dy <- rep(exclude:2, length.out = k)
      vali[cbind(ay, dy)] <- TRUE
    }
    list(origin = c0,
         n = n,
         final = (c0 == n),
         y     = ifelse(cal <= c0, y0, NA),
         train = cal <= c0 & !vali,
         vali  = vali,
         test  = if (c0 < n) ifelse(cal > c0, y0, NA))
  })
}
