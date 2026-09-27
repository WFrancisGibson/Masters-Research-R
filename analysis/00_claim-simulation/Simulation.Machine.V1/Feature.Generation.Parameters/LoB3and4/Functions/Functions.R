### Define the inverse distribution functions for the marginals cc, age and inj_part

f.cc <- function(x, alpha, beta, const){
  (exp(alpha*x/const + log(beta)) - beta) / alpha
}

f.age1 <- function(x, alpha, beta, const){
  -sqrt(42*x/(beta*const) + 21^2 * alpha^2 / beta^2) - 21*alpha/beta + 14
}

f.age2 <- function(x, alpha, beta, gamma, const){
  -sqrt(pmax(0,-70*x/(gamma*const) + 35^2/(gamma^2)*(alpha+beta)^2 + 21*70*alpha/gamma + 10.5*70*beta/gamma)) + 35*alpha/gamma + 35 * beta/gamma + 35
}

f.inj_part <- function(x, alpha, beta, const){
  (exp(alpha*x/const + log(beta)) - beta) / alpha
}