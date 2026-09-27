##########################################
#########  ccODP: cross-classified over-dispersed Poisson model
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
  # dispersion:
  # deviance (eq. (5))
  # Pearson statistic over (cells - parameters)
  y_fit <- ifelse(cells, y, NA)
  deviance <- poisson_deviance(y_fit, mu)
  df <- sum(cells) - (2 * n - 1)
  phi <- if (phi_method == "deviance") deviance / df else
    sum((y_fit - mu)^2 / mu, na.rm = TRUE) / df
  #
  list(intercept = intercept,
       alpha = alpha,
       beta = beta,
       mu = mu,
       y = y,
       cells = cells,
       deviance = deviance,
       phi = phi,
       reserve_o = rowSums(lower_triangle(mu), na.rm = TRUE))
}
