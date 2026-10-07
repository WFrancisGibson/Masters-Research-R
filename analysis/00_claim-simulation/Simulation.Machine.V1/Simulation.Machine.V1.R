################################################################
### Demonstration of the Simulation Machine:                 ###
### Generates individual accident insurance claims           ###
### including reporting pattern, cash flow pattern           ###
### and claims closing information.                          ###
### Authors: Andrea Gabrielli, Mario V. Wuthrich             ###
### Date: 26.02.2018                                         ###
### Version: 1                                               ###
### Reference: Individual Claims History Simulation Machine. ###
###            SSRN Manuscript ID 3130560.                   ###  
################################################################



### IMPORTANT: Change the working directory to current directory through:
### Session --> Set Working Directory --> To Source File Location



##################################
### Load the required packages ###
##################################

library(parallel)
library(foreach)
library(doParallel)
library(data.table)
library(plyr)
library(MASS)
library(ChainLadder)



#######################################################################
### Read in the functions Simulation.Machine and Feature.Generation ###
#######################################################################

source(file="./Functions.V1.R")



#############################
### Generate the features ###
#############################

V <- 500000                           # totally expected number of claims (over 12 accounting years)
LoB.dist <- c(0.25,0.30,0.20,0.25)    # categorical distribution for the allocation of the claims to the 4 lines of business
inflation <- c(0.01,0.01,0.01,0.01)   # growth parameters (per LoB) for the numbers of claims in the 12 accident years
seed1 <- 100                          # setting seed for simulation
features <- Feature.Generation(V = V, LoB.dist = LoB.dist, inflation = inflation, seed1 = seed1)

str(features)

###############################################
### Simulate (and store) cash flow patterns ###
###############################################

npb <- nrow(features)                # blocks for parallel computing
seed1 <- 100                         # setting seed for simulation
std1 <- 0.85                         # standard deviation parameter for total claim size simulation
std2 <- 0.85                         # standard deviation parameter for recovery simulation
output <- Simulation.Machine(features = features, npb = npb, seed1 = seed1, std1 = std1, std2 = std2)

str(output)

# write.table(output, "./Simulated.Cashflow.txt", sep=";", row.names=FALSE)

##########################################################
### CL analysis on aggregated claims of simulated data ###
##########################################################

### We add artificial observations with 0 payments
### to ensure that we have at least one observation per accident year
add.obs <- output[rep(1,12),]
add.obs[,4] <- 1994:2005
add.obs[,9:20] <- 0
output <- rbind(output,add.obs)

### Cumulative cash flows
cum_CF <- round((1000)^(-1)*ddply(output, .(AY), summarise, CF00=sum(Pay00),CF01=sum(Pay01),CF02=sum(Pay02),CF03=sum(Pay03),CF04=sum(Pay04),CF05=sum(Pay05),CF06=sum(Pay06),CF07=sum(Pay07),CF08=sum(Pay08),CF09=sum(Pay09),CF10=sum(Pay10),CF11=sum(Pay11))[,2:13])
for (j in 2:12){cum_CF[,j] <- cum_CF[,j-1] + cum_CF[,j]}
cum_CF

### Mack chain-ladder analysis
tri_dat <- array(NA, dim(cum_CF))
reserves <- data.frame(array(0, dim=c(12+1,3)))
reserves <- setNames(reserves, c("true Res.","CL Res.","MSEP^(1/2)"))
for (i in 0:11){
  for (j in 0:(11-i)){tri_dat[i+1,j+1] <- cum_CF[i+1,j+1]}
  reserves[i+1,1] <- cum_CF[i+1,12]-cum_CF[i+1,12-i]
}
reserves[13,1] <- sum(reserves[1:12,1])
tri_dat <- as.triangle(as.matrix(tri_dat))
dimnames(tri_dat)=list(origin=1:12, dev=1:12)
Mack <- MackChainLadder(tri_dat, est.sigma="Mack")
for (i in 0:11){reserves[i+1,2] <- round(Mack$FullTriangle[i+1,12]-Mack$FullTriangle[i+1,12-i])}
reserves[13,2] <- sum(reserves[1:12,2])
reserves[1:12,3] <- round(Mack$Mack.S.E[,12])
reserves[13,3] <- round(Mack$Total.Mack.S.E)
reserves                           # true reserves, chain-ladder reserves and square-rooted MSEP
