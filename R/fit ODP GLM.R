##########################################
#########  ccODP: cross-classified over-dispersed Poisson model
#########  Paper C Section 2; bootstraps: Paper C Section 2.3 and
#########  England & Verrall (1999) Section 4
##########################################

## E[Y_ij] = mu_ij = exp(c + alpha_i + beta_j), Var(Y_ij) = phi * mu_ij
## with alpha_1 = beta_1 = 0 (eq. (3)),
## fitted on the cells of y; the quasi-Poisson MLE
## gives the chain-ladder reserves
ccodp_fit <- function(y, cells = !is.na(y), phi_method = "deviance") {
  n <- nrow(y)
  dat <- data.frame(Y  = y[cells],
                    AY = factor(row(y)[cells], levels = 1:n),
                    DY = factor(col(y)[cells], levels = 1:n))
  d_glm <- glm(Y ~ AY + DY, data = dat, family = quasipoisson(),
               control = glm.control(epsilon = 1e-12, maxit = 100))
  b <- coef(d_glm)
  intercept <- b[["(Intercept)"]]
  alpha <- c(0, unname(b[paste0("AY", 2:n)]))
  beta <- c(0, unname(b[paste0("DY", 2:n)]))
  mu <- exp(intercept + outer(alpha, beta, "+"))
  dimnames(mu) <- list(origin = 1:n, dev = 1:n)
  #
  # dispersion over df = cells - parameters = |D_I| - (I + J):
  # the unscaled deviance (eq. (5)) and Pearson's statistic (glmReserve);
  # phi is the one of phi_method
  y_fit <- ifelse(cells, y, NA)
  deviance <- poisson_deviance(y_fit, mu)
  df <- sum(cells) - (2 * n - 1)
  phi_deviance <- deviance / df
  phi_pearson <- sum((y_fit - mu)^2 / mu, na.rm = TRUE) / df
  #
  list(intercept = intercept,
       alpha = alpha,
       beta = beta,
       mu = mu,
       y = y,
       cells = cells,
       deviance = deviance,
       df = df,
       phi_deviance = phi_deviance,
       phi_pearson = phi_pearson,
       phi = if (phi_method == "deviance") phi_deviance else phi_pearson,
       reserve_o = rowSums(lower_triangle(mu), na.rm = TRUE))
}

## Paper C eq. (1): Y_ij / phi ~ Poi(mu_ij / phi), independent, on the
## cells; NA elsewhere
odp_sample <- function(mu, phi, cells) {
  y <- matrix(NA, nrow(mu), ncol(mu))
  y[cells] <- phi * rpois(sum(cells), mu[cells] / phi)
  y
}

## Paper C Section 2.3: parametric bootstrap; triangles simulated from (1)
## with the ccODP means and the dispersion phi, each refitted by the ccODP;
## bootstrap reserves by accident period (nsim x n)
ccodp_bootstrap <- function(odp, phi, nsim) {
  t(replicate(nsim, {
    ccodp_fit(odp_sample(odp$mu, phi, odp$cells), odp$cells)$reserve_o
  }))
}

## chain-ladder reserves by accident period of the incremental triangle y
## (NA below the latest diagonal); negative increments are allowed
cl_reserves <- function(y) {
  n <- nrow(y)
  cum <- t(apply(y, 1, cumsum))                # NA after the latest diagonal
  for (j in 1:(n - 1)) {
    f <- sum(cum[1:(n - j), j + 1]) / sum(cum[1:(n - j), j])
    cum[(n - j + 1):n, j + 1] <- f * cum[(n - j + 1):n, j]
  }
  cum[, n] - rowSums(y, na.rm = TRUE)
}

## England & Verrall (1999) Section 4: the unscaled Pearson residuals
## r = (y - mu) / sqrt(mu) of the cells resampled with replacement, pseudo
## data y* = mu + r* sqrt(mu) (negatives allowed) and their chain-ladder
## reserves by accident period (nsim x n)
ev_bootstrap <- function(odp, nsim) {
  cells <- odp$cells
  mu <- odp$mu[cells]
  r <- (odp$y[cells] - mu) / sqrt(mu)
  y <- matrix(NA, nrow(odp$mu), ncol(odp$mu))
  t(replicate(nsim, {
    y[cells] <- mu + sample(r, replace = TRUE) * sqrt(mu)
    cl_reserves(y)
  }))
}
