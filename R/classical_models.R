############################# CLASSICAL RESERVING MODELS #######################
# R/classical_models.R -- functions only, no top-level code.
#
# Wrappers around three model functions of the ChainLadder package (0.2.21):
#   fit_chainladder()  -> chainladder()      Barnett & Zehnwirth (2000); ?chainladder
#   fit_mack()         -> MackChainLadder()  Mack (1993, 1999); ?MackChainLadder
#   fit_glm_reserve()  -> glmReserve()       England & Verrall (1999, 2002); ?glmReserve
#
# Each wrapper takes a claims triangle plus the model's own arguments (same
# names and defaults as the package), fits the model and returns a list:
#   $model          the object returned by the ChainLadder function, unchanged
#   $full_triangle  the cumulative triangle completed by the model
#   $by_origin      data.frame, one row per origin:
#                   origin, latest, dev_to_date, ultimate, ibnr, se, cv
#   $total          named vector: latest, ultimate, ibnr, se, cv
#   $settings       the arguments used
# plus model-specific extras (factors, sigma, risk, var_power, simulations).
# For an input that is already a triangle (NA below the latest diagonal) the
# fit is the package's own: fit_mack(tri)$model is MackChainLadder(tri).
#
# Functions are called as ChainLadder::fun, so the file also works when it is
# sourced on its own (e.g. by the tests). Analysis scripts get it through
# analysis/00_setup.R.


#' Turn claims data into the observed cumulative triangle the models need
#'
#' @param triangle one of
#' * a matrix or ChainLadder "triangle" (rows = origins, columns = development);
#' * a wide data.frame / data.table with one column per development period,
#'     optionally preceded by an origin column (like the simulated triangle.csv:
#'     AQ, 1, 2, ..., 40), or with the origins as row names;
#' * a long data.frame with one row per origin x development cell
#' (ChainLadder's as.data.frame(triangle), or any frame with format = "long").
#' @param cum TRUE if the values are cumulative, FALSE if incremental.
#' @param mask_future what to do with cells below the latest diagonal
#'   (origin + dev > number of origins + 1):
#'   NULL (default) masks them only when the input is a full SQUARE with no NA,
#'   e.g. the simulated triangle.csv, which holds the future too; a triangle that
#'   already has NA is used as it is, and a full non-square rectangle stops and
#'   asks you to choose. TRUE always masks (stops if that would delete values
#'   from an input that already has NA); FALSE never masks.
#'   Assuming that origin and development periods have the same length, so the
#'   latest diagonal, origin + dev = n_origin + 1, is the valuation date.]
#' @param origin_col wide data only: NULL guesses (the first column is the
#'   origin unless its name looks like a development period: 1, V1, X1, dev1,
#'   DQ1, DY1); a column name or number; or FALSE for none (row names are then
#'   used as origins if the frame has real row names).
#' @param format "auto", "wide" or "long". "auto" treats a data.frame as long if
#'   it has class long.triangle or columns named origin, dev, value.
#' @param long_cols long data only: names of the origin, dev and value columns.
#' @return a cumulative ChainLadder "triangle" with dimnames origin / dev.



prepare_triangle <- function(triangle,
                     cum = TRUE,
                     mask_future = NULL,
                     origin_col = NULL,
                     format = c("auto", "wide", "long"),
                     long_cols = c(origin = "origin",
                                   dev = "dev",
                                   value = "value")) {
  format <- match.arg(format)

  m <- triangle_matrix(triangle, origin_col, format, long_cols)
  
  if (is.null(rownames(m))) rownames(m) <- seq_len(nrow(m))
  if (is.null(colnames(m))) colnames(m) <- seq_len(ncol(m))
  dimnames(m) <- list(origin = rownames(m), dev = colnames(m))

  full <- !anyNA(m)
  if (is.null(mask_future)) {
    if (full && nrow(m) != ncol(m)) {
      stop(sprintf(paste("prepare_triangle(): the input is a full %d x %d rectangle",
                         "with no NA. Set mask_future = TRUE to keep only cells with",
                         "origin + dev <= %d, or FALSE to use it as it is."),
                   nrow(m), ncol(m), nrow(m) + 1), call. = FALSE)
    }
    mask_future <- full
  }
  if (isTRUE(mask_future)) {
    future <- row(m) + col(m) > nrow(m) + 1
    n_masked <- sum(future & !is.na(m))
    if (!full && n_masked > 0) {
      stop(sprintf(paste("prepare_triangle(): the input already has NA cells, and",
                         "mask_future = TRUE would also delete %d observed values",
                         "(origin + dev > %d): its latest diagonal is not that line.",
                         "Use mask_future = FALSE."), n_masked, nrow(m) + 1),
           call. = FALSE)
    }
    if (n_masked > 0) {
      message(sprintf(paste("prepare_triangle(): %d cells below the latest diagonal",
                            "(origin + dev > %d) were set to NA"),
                      n_masked, nrow(m) + 1))
    }
    m[future] <- NA
  }

  if (!cum) {
    # An NA inside the observed increments would make incr2cum() turn the
    # rest of that row into NA, silently shortening the origin's history.
    last_obs <- apply(m, 1, function(r) max(c(0L, which(!is.na(r)))))
    holes <- which(is.na(m) & col(m) < last_obs[row(m)], arr.ind = TRUE)
    if (nrow(holes) > 0) {
      stop(sprintf(paste("prepare_triangle(): %d NA cell(s) inside the observed",
                         "incremental triangle, e.g. origin %s dev %s. Replace them",
                         "(e.g. by 0) before fitting."),
                   nrow(holes), rownames(m)[holes[1, 1]], colnames(m)[holes[1, 2]]),
           call. = FALSE)
    }
  }
  tri <- ChainLadder::as.triangle(m)
  if (!cum) tri <- ChainLadder::incr2cum(tri)
  tri
}


# prepare_triangle()'s reader: any supported input -> numeric matrix, with
# origin labels as row names when there are any.

triangle_matrix <- function(x, origin_col, format, long_cols) {
  if (!is.data.frame(x)) {
    return(matrix(as.numeric(x), nrow(x), ncol(x), dimnames = dimnames(x)))
  }
  df <- as.data.frame(x)
  is_long <- format == "long" ||
    (format == "auto" && (inherits(x, "long.triangle") ||
                            identical(tolower(names(df)), c("origin", "dev", "value"))))
  if (is_long) {
    df[[long_cols[["value"]]]] <- as.numeric(df[[long_cols[["value"]]]])
    tri <- ChainLadder::as.triangle(df, origin = long_cols[["origin"]],
                                    dev = long_cols[["dev"]], value = long_cols[["value"]])
    return(matrix(as.numeric(tri), nrow(tri), ncol(tri), dimnames = dimnames(tri)))
  }
  if (is.null(origin_col)) {
    dev_like <- grepl("^(v|x|dev|dq|dy|d)?[0-9]+$", tolower(names(df)[1]))
    origin_col <- if (dev_like) FALSE else 1L
  }
  labels <- NULL
  if (!isFALSE(origin_col)) {
    idx <- if (is.character(origin_col)) match(origin_col, names(df)) else origin_col
    labels <- as.character(df[[idx]])
    df <- df[, -idx, drop = FALSE]
  }
  df[] <- lapply(df, as.numeric)       # also turns bit64 integer64 (fread) into doubles
  m <- as.matrix(df)                   # keeps real row names, NULL for automatic ones
  if (!is.null(labels)) rownames(m) <- labels
  if (format == "auto" && nrow(m) > 4 * ncol(m)) {
    stop(sprintf(paste("prepare_triangle(): %d rows x %d value columns does not look",
                       "like a wide triangle (rows = origins, columns = development).",
                       "For long data (one row per cell) use format = \"long\";",
                       "to force the wide reading use format = \"wide\"."),
                 nrow(m), ncol(m)), call. = FALSE)
  }
  m
}


# Totals from a by-origin table. The total SE is not the sum of the origin SEs,
# so it comes from the model.
reserve_totals <- function(by_origin, se_total = NA_real_, ibnr_total = NULL) {
  ibnr <- if (is.null(ibnr_total)){ 
    sum(by_origin$ibnr) 
  } else {
    ibnr_total
  }
  latest <- sum(by_origin$latest)
  c(latest = latest,
    ultimate = latest + ibnr,
    ibnr = ibnr,
    se = unname(se_total),
    cv = unname(se_total) / ibnr)
}


#' Write a fit_*() wrapper's tables to output/tables/
#'
#' Works with any fit_chainladder()/fit_mack()/fit_glm_reserve() result (or
#' any future wrapper following the same $by_origin/$total shape). Writes two
#' CSVs under paths$tables: "<name>_by_origin.csv" and "<name>_total.csv".
#'
#' @param fit a list with $by_origin (data.frame) and $total (named vector),
#'   as returned by this file's fit_*() functions.
#' @param name file prefix, e.g. "mack".



#' Chain ladder as weighted link-ratio regressions (no standard errors)
#'
#' Fits chainladder(): for each development period k, C[i, k+1] = f_k C[i, k]
#' by weighted least squares with weights w_ik / C_ik^delta (Barnett & Zehnwirth
#' 2000; ?chainladder). delta = 1 volume-weighted, 2 simple average,
#' 0 ordinary regression through the origin.
#'
#' @param triangle claims data (see prepare_triangle()).
#' @param weights 1, or a matrix of 0/1 weights the size of the prepared
#'   triangle (0 drops a link ratio; the weight sits on the ratio's starting
#'   cell; columns are matched by position, so no origin column).
#' @param delta see above.
#' @param cum,mask_future,... passed to prepare_triangle().
fit_chainladder <- function(triangle, weights = 1, delta = 1,
                            cum = TRUE, mask_future = NULL, ...) {
  tri <- prepare_triangle(triangle, cum, mask_future, ...)
  fit <- ChainLadder::chainladder(tri, weights = weights, delta = delta)
  full <- predict(fit)                   # cumulative, completed to the last column
  n <- ncol(tri)
  latest <- as.numeric(ChainLadder::getLatestCumulative(tri))
  ultimate <- as.numeric(full[, n])
  factors <- vapply(fit$Models, function(md) unname(stats::coef(md)[1]), numeric(1))
  names(factors) <- paste0(colnames(tri)[-n], "-", colnames(tri)[-1])
  by_origin <- data.frame(origin = rownames(tri), latest = latest,
                          dev_to_date = ifelse(ultimate > 0, latest / ultimate, NA_real_),
                          ultimate = ultimate, ibnr = ultimate - latest,
                          se = NA_real_, cv = NA_real_)
  list(model = fit, full_triangle = full, factors = factors,
       by_origin = by_origin, total = reserve_totals(by_origin),
       settings = list(weights = weights, delta = delta,
                       cum = cum, mask_future = mask_future))
}


#' Mack's distribution-free chain ladder with standard errors
#'
#' Fits MackChainLadder() (Mack 1993; tail factor Mack 1999). The arguments and
#' their defaults are the package's own.
#'
#' @param triangle claims data (see prepare_triangle()).
#' @param weights 1, or a matrix of weights the size of the prepared triangle.
#' @param alpha 1 volume-weighted, 0 simple average, 2 regression (alpha = 2 - delta).
#' @param est.sigma "log-linear" (package default), "Mack" (Mack 1993's rule for
#'   the last sigma) or a number.
#' @param tail FALSE, TRUE (log-linear tail fitted to f - 1) or a numeric tail factor.
#' @param tail.se,tail.sigma standard error and sigma of the tail factor. NULL
#'   (the package default): extrapolated log-linearly from the fitted f.se and
#'   sigma whenever the tail factor is > 1, whether tail = TRUE or numeric; pass
#'   0 to add no tail uncertainty. Ignored when the tail factor is 1.
#' @param mse.method "Mack" or "Independence" (Buchwalder, Buhlmann, Merz &
#'   Wuthrich 2006; Murphy 1994).
#' @param cum,mask_future,... passed to prepare_triangle().
fit_mack <- function(triangle, weights = 1, alpha = 1, est.sigma = "log-linear",
                     tail = FALSE, tail.se = NULL, tail.sigma = NULL,
                     mse.method = "Mack", cum = TRUE, mask_future = NULL, ...) {
  tri <- prepare_triangle(triangle, cum, mask_future, ...)
  fit <- ChainLadder::MackChainLadder(tri, weights = weights, alpha = alpha,
                                      est.sigma = est.sigma, tail = tail,
                                      tail.se = tail.se, tail.sigma = tail.sigma,
                                      mse.method = mse.method)
  # Built from the fitted object, not summary(): summary.MackChainLadder()
  # drops origins whose latest value is 0. The last columns of FullTriangle
  # and Mack.S.E are the ultimate (including the tail, if any).
  latest <- as.numeric(ChainLadder::getLatestCumulative(fit$Triangle))
  ultimate <- as.numeric(fit$FullTriangle[, ncol(fit$FullTriangle)])
  se <- as.numeric(fit$Mack.S.E[, ncol(fit$Mack.S.E)])
  se[ultimate == 0 & is.nan(se)] <- 0
  ibnr <- ultimate - latest
  by_origin <- data.frame(origin = rownames(fit$Triangle), latest = latest,
                          dev_to_date = ifelse(ultimate > 0, latest / ultimate, NA_real_),
                          ultimate = ultimate, ibnr = ibnr, se = se,
                          cv = ifelse(ibnr > 0, se / ibnr, NA_real_))
  # Total process and parameter risk are accumulated over development; the
  # last element is the risk to ultimate.
  risk <- c(process = unname(utils::tail(fit$Total.ProcessRisk, 1)),
            parameter = unname(utils::tail(fit$Total.ParameterRisk, 1)))
  list(model = fit, full_triangle = fit$FullTriangle,
       factors = fit$f, sigma = fit$sigma, risk = risk,
       by_origin = by_origin,
       total = reserve_totals(by_origin, se_total = fit$Total.Mack.S.E),
       settings = list(weights = weights, alpha = alpha, est.sigma = est.sigma,
                       tail = tail, tail.se = tail.se, tail.sigma = tail.sigma,
                       mse.method = mse.method, cum = cum, mask_future = mask_future))
}


#' GLM reserving: incremental claims ~ Tweedie family, factor(origin) + factor(dev)
#'
#' Fits glmReserve() (England & Verrall 1999, 2002). The model arguments and
#' their defaults are the package's own. var.power = 1 with the log link is the
#' over-dispersed Poisson, which reproduces the chain ladder reserve.
#'
#' @param triangle claims data (see prepare_triangle()).
#' @param var.power Tweedie variance power: 1 ODP, 2 gamma, 0 normal, 3 inverse
#'   Gaussian, a value in (1, 2) compound Poisson, or NULL to estimate it with
#'   cplm (slow).
#' @param link.power 0 log link (default); 1 identity, 0.5 square root, ...
#' @param cum TRUE if `triangle` is cumulative. The wrapper always hands
#'   glmReserve() the cumulative triangle, so here `cum` only describes the input.
#' @param mse.method "formula" (delta method) or "bootstrap". The bootstrap
#'   redraws the whole pseudo triangle until every increment is >= 0, which can
#'   take a very long time on large triangles (hours at 40 x 40).
#' @param nsim number of bootstrap simulations.
#' @param nb TRUE fits a negative binomial GLM (MASS::glm.nb, Var = mu + mu^2 /
#'   theta, increments rounded). It is not the Verrall (2000) recursive negative
#'   binomial and does not reproduce the chain ladder.
#' @param exposure optional exposure per origin; defaults to
#'   attr(triangle, "exposure") if the input has one. glmReserve() adds
#'   offset = link(exposure) (log(exposure) for link.power = 0, sqrt for 0.5)
#'   and ignores it when nb = TRUE. Its formula always contains factor(origin),
#'   which absorbs any per-origin offset, so exposure never changes the fitted
#'   values, reserves or standard errors.
#' @param mask_future,origin_col,format,long_cols passed to prepare_triangle().
#' @param ... passed to glmReserve() and on to glm() / cpglm().
fit_glm_reserve <- function(triangle, var.power = 1, link.power = 0, cum = TRUE,
                            mse.method = c("formula", "bootstrap"), nsim = 1000,
                            nb = FALSE, exposure = NULL, mask_future = NULL,
                            origin_col = NULL, format = "auto",
                            long_cols = c(origin = "origin", dev = "dev", value = "value"),
                            ...) {
  mse.method <- match.arg(mse.method)
  if (is.null(exposure)) exposure <- attr(triangle, "exposure")
  tri <- prepare_triangle(triangle, cum, mask_future, origin_col, format, long_cols)

  # A log-link Poisson, gamma or Tweedie GLM cannot take negative increments;
  # glmReserve() would stop with an obscure "cannot find valid starting values".
  inc <- ChainLadder::cum2incr(tri)
  if ((is.null(var.power) || var.power >= 1 || nb) && any(inc < 0, na.rm = TRUE)) {
    bad <- which(inc < 0, arr.ind = TRUE)
    stop(sprintf(paste("fit_glm_reserve(): %d negative incremental value(s), e.g.",
                       "origin %s dev %s = %s; var.power >= 1 (or nb = TRUE)",
                       "needs non-negative increments"),
                 nrow(bad), rownames(tri)[bad[1, 1]], colnames(tri)[bad[1, 2]],
                 format(inc[bad[1, , drop = FALSE]])), call. = FALSE)
  }
  if (!is.null(exposure)) {
    stopifnot(length(exposure) == nrow(tri))
    if (nb) warning("fit_glm_reserve(): glmReserve() ignores exposure when nb = TRUE",
                    call. = FALSE)
    attr(tri, "exposure") <- exposure
  }

  fit <- ChainLadder::glmReserve(tri, var.power = var.power, link.power = link.power,
                                 cum = TRUE, mse.method = mse.method, nsim = nsim,
                                 nb = nb, ...)
  if (!isS4(fit$model) && !isTRUE(fit$model$converged)) {
    warning("fit_glm_reserve(): the GLM did not converge; results are not reliable",
            call. = FALSE)
  }

  # glmReserve()'s summary leaves out origins with no reserve (the fully
  # developed first origin), and its "total" Latest leaves them out too.
  s <- fit$summary
  latest <- as.numeric(ChainLadder::getLatestCumulative(tri))
  hit <- match(rownames(tri), rownames(s))
  ibnr <- ifelse(is.na(hit), 0, s$IBNR[hit])
  se <- ifelse(is.na(hit), 0, s$S.E[hit])
  ultimate <- latest + ibnr
  by_origin <- data.frame(origin = rownames(tri), latest = latest,
                          dev_to_date = ifelse(ultimate > 0, latest / ultimate, NA_real_),
                          ultimate = ultimate, ibnr = ibnr, se = se,
                          cv = ifelse(ibnr > 0, se / ibnr, NA_real_))

  sims <- NULL
  if (mse.method == "bootstrap") {
    sims <- list(reserve_pred = fit$sims.reserve.pred,       # nsim x origins with a reserve
                 total = rowSums(fit$sims.reserve.pred))
  }
  list(model = fit, full_triangle = fit$FullTriangle,
       var_power = if (nb) NA_real_ else if (isS4(fit$model)) fit$model@p else var.power,
       by_origin = by_origin,
       total = reserve_totals(by_origin, se_total = s["total", "S.E"],
                              ibnr_total = s["total", "IBNR"]),
       simulations = sims,
       settings = list(var.power = var.power, link.power = link.power, cum = cum,
                       mse.method = mse.method, nsim = nsim, nb = nb,
                       exposure = exposure, mask_future = mask_future))
}
