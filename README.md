# Masters-Research-R

Research compendium for the masters thesis (R strands). The code follows the style of
Gabrielli (2020, PhD thesis, Paper C listings) and the *AI Tools for Actuaries* course code:
short scripts that run from top to bottom, a few small functions, base R.

## Strands
- `analysis/00_claim-simulation/short_tailed_claims.R`: simulates the synthetic claims with
  SynthETIC (annual 20 x 20 by default; `time_unit <- 1/4`, `years <- 10` for quarterly 40 x 40)
  and writes them to `data/raw/claim-simulation-annual/` (quarterly: `data/raw/claim-simulation/`)
- `analysis/00_claim-simulation/SynthETIC claims description.R` (~30 s): description of the
  annual SynthETIC portfolio at the valuation date (end of year 20), the counterpart of
  `simulated data description.R` for the machine data: portfolio, accident years, claim sizes,
  delays, reported claims and claim status (Risks Tables 3 and 6), triangles, development
  factors, calendar years and Mack's chain ladder against the true outstanding (Risks Tables 5
  and 7); 19 tables `output/tables/00_claim-simulation/data-description/synthetic_data_t*.csv`
  and 12 figures `output/figures/00_claim-simulation/data-description/`
- `analysis/00_claim-simulation/SynthETIC feature impact.R` (~1 min): the five claim features:
  their design (probabilities, severity relativities, delay multipliers), the portfolio mix
  against the design, and their impact on the claim size, the delays, the number of payments,
  the payment pattern, the true outstanding and the chain-ladder factors and reserves by level;
  designed, one-way and all-else-equal effects (log-linear model on the five features) and the
  variance explained; 27 tables `output/tables/00_claim-simulation/feature-impact/
  synthetic_features_t*.csv` and 13 figures `output/figures/00_claim-simulation/feature-impact/`.
  Both scripts measure on the full simulation ("true") unless a table says "observed"; the
  figures have no title and grey fills (the number and heading go below the figure in the
  report)
- `thesis/claude_explainer-synthetic-claims-data-and-feature-impact.Rmd`: the report of the two
  scripts (47 tables, 25 figures; the numbers quoted in the text are computed from the output
  tables when it is knitted),
  knitted to Word in the format of `project_folder_guide.docx`: `thesis/guide_reference.docx`
  holds the guide's styles (built by `thesis/make_guide_reference.R`) and
  `thesis/guide_tables.lua` gives the tables the guide's table style. Run the two scripts first,
  then knit (from a shell: `Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/Quarto/bin/tools")`
  before `rmarkdown::render()`)
- `analysis/01_Mack model/Mack chainladder fit.R`: Mack chain ladder
- `analysis/02_ODP glm model/ODP glm fit plot.R`: ODP GLM, standard errors by formula and bootstrap;
  the dispersion by Pearson's statistic (glmReserve) and by Paper C eq. (5), and the RMSEP of the
  CL reserves by seven methods: analytic under both phi, glmReserve's bootstrap (residuals times
  sqrt(n/(n-p)), pseudo triangles with a negative cell redrawn), England & Verrall (1999)
  Section 4 without and with the factor n/(n-p), and Paper C's parametric bootstrap (Section 2.3)
  under both phi (`output/tables/02_ODP-glm/odp_dispersion.csv`, `odp_rmsep_*.csv`,
  `odp_bootstrap_totals.csv`; figures `GLM ODP RMSEP *.png`, `GLM ODP bootstrap densities.png`)
- `analysis/03_bCCNN/bCCNN fit.R`: bCCNN of Paper C (Gabrielli, Richman & Wuthrich 2020) with
  early stopping by rolling origin (Al-Mudafer et al. 2021) or the 50/50 claims split; its
  RMSEP by Paper C's parametric bootstrap (Section 3.3.4, eqs. (15)-(16)) next to the ccODP's
  (Section 2.3), and the dispersions of both models by Pearson and eq. (5)
  (`output/tables/03_bCCNN/bccnn_annual_rmsep_*.csv`, `_dispersion.csv`, `_bootstrap_totals.csv`).
  The 1,000 bCCNN refits take ~3.5 h on the first run (~13 s each on CPU); they are saved in
  `data/processed/bccnn_bootstrap_<final_fit>_n<nsim>.rds` after every tenth, a stopped run
  resumes there, and later runs reuse them while the network, phi and steps are unchanged
  (`bccnn: bootstrap: nsim: 0` in `config.yml` skips them)
- `analysis/04_nn-chain-ladder/`, `analysis/05_TabM ODP model/`: to come

## Layout
- `analysis/00_setup.R`: sourced first by every script (packages, `config.yml`, paths, seed,
  functions in `R/`)
- `R/`: functions only
  - `triangles.R`: claims triangles, 50/50 claims split, rolling-origin partitions
  - `loss functions.R`: Poisson deviance
  - `reserves.R`: reserve tables, back-test against the true reserves, RMSEP table
  - `fit ODP GLM.R`: ccODP model (Paper C Section 2) with both dispersion estimates, the
    ODP sample (1), the parametric bootstrap (Section 2.3), the chain ladder and the
    England & Verrall (1999) bootstrap
  - `nn_models.R`: bCCNN network, fitting, early stopping and bootstrap (Paper C Section 3)
  - `plots.R`: figures
  - `claims_description.R`: the portfolio at the valuation date, summaries by feature level,
    SynthETIC's relativity of a level combination, chain-ladder factors, Cramer's V, Gini
    coefficient, log-linear effects and variance explained
  - `plots_claims_description.R`: figures of the two description scripts
- `data/raw` (never edited) -> `data/interim` -> `data/processed`
- `models/`, `output/`: regenerated by the scripts, never saved by hand
- `config.yml`: seed, hyper-parameters, paths (read with `config::get()`); the `quick` profile
  runs the ODP GLM and bCCNN scripts with few bootstrap samples, its outputs in `output/quick/`
  and `data/processed/quick/` (`R_CONFIG_ACTIVE=quick Rscript ...` in bash,
  `$env:R_CONFIG_ACTIVE = "quick"` in PowerShell)
- `reviews/`: paper-critique .Rmd files
- `thesis/`: chapters and references.bib
- `tests/`: checks of the functions in `R/` (`Rscript tests/testthat.R`)
- `.lintr`: lintr settings (default linters: snake_case names, lines up to 80
  characters; `%>%` as the only pipe)

## Setup
1. Open `Masters-Research-R.Rproj` in RStudio.
2. Run `renv::init()` once, then `renv::snapshot()` after installing packages.
3. For the bCCNN, point reticulate to a Python with tensorflow and keras
   (`RETICULATE_PYTHON=<path>/python.exe` in `.Renviron`).
4. Keep `renv/library`, `models/` and `.git` out of OneDrive sync.

## NN chain ladder (Wuthrich 2018) on the Gabrielli & Wuthrich simulation machine
Wuthrich (2018), *Neural networks applied to chain-ladder reserving*, EAJ 8:407-436, on
the individual claims of the Gabrielli & Wuthrich (2018) simulation machine (Risks
6(2):29). Settings: the `nncl:` block of `config.yml`. Run in this order:
1. `analysis/00_claim-simulation/individual_claims_simulation_machine.R` (~7 min, peak
   ~20 GB): the paper's Listing 1 portfolio (V = 5,000,000, seed1 = 100); with
   `rng_rounding: true` (sample.kind "Rounding" of R < 3.6, also in the machine's
   workers) it reproduces the paper's data exactly (5,003,204 claims, 4,970,856 reported
   by 2005, Table 4). Writes `data/raw/claim-simulation-machine/claims.csv` (~395 MB)
2. `analysis/04_nn-chain-ladder/trackA_wuthrich2018/simulated data description.R`
   (~3 min): Risks Tables 3, 5, 6, 7 and Figures A1-A4; EAJ Figures 5-6
3. `.../trackA_wuthrich2018/NN chain ladder fit.R` (~75 min on CPU): the networks of
   Listing 2 (q = 5, 10, 20) and the sensitivity runs S1 Adam, S2 + early stopping,
   S3 + CL-initialised output, S4 + balance correction; the zero claims factors
   (Section 4.2). Each run is saved to `data/processed/nncl_fit_<run>.rds` (a saved run
   is not refitted), the networks to `models/`
4. `.../trackA_wuthrich2018/NN chain ladder analysis.R` (~2 min, no Keras): reserves
   (5.1), EAJ Tables 2-5, the sensitivity runs, Figures 2-4 and 7-9
   (`output/tables/04_NN-chain-ladder/`, `output/figures/04_NN-chain-ladder/`)

The same networks, runs and zero claims rules on the SynthETIC portfolio (annual 20 x 20,
`data/raw/claim-simulation-annual/`; settings from the `data:` and `nncl:` blocks):
1. `.../trackA_wuthrich2018/NN chain ladder SynthETIC fit.R` (~3 h on CPU for the seven
   runs and one seed of the grid): cells (accident year, feature value) of the five covariates, all categorical
   (14 dummies, no LoB); 3,342 cells, 226 of the 480 feature values occur. Besides the
   seven runs of the machine data it fits a grid of my own design (`nncl: synthetic:` in
   `config.yml`): hidden layers (20), (20, 20, 15) and (20, 15, 10) x ten optimisers
   (SGD, SGD with momentum, Nesterov, Adagrad, Adadelta, RMSprop, Adam, AdamW, Adamax,
   Nadam) x training (`paper`: Listing 2's; `cl_start`: early stopping from the
   homogeneous CL factor, as S3), each combination with `seeds` seeds (2026, 2027, ...).
   The networks are fitted on the payments in millions (SGD needs moderate gradients).
   Runs saved to `data/processed/nncl_synthetic_fit_<run>.rds`, the networks of the
   first seed to `models/nncl_synthetic/`. With 20 seeds that is 1,200 grid runs: about
   20 times as long when the script runs them one after the other (the saved runs were
   fitted in about 7 h by ten R sessions, each on its own share of the runs)
2. `.../trackA_wuthrich2018/NN chain ladder SynthETIC analysis.R` (no Keras): reserves
   (5.1) against the true reserves and Mack's CL, the analogues of EAJ Tables 2-5 and
   Figures 2-4 and 7-9, the zero claims cells by accident year, and for the hidden
   layers and optimisers the table of all runs (`nncl_synthetic_layers_optimisers.csv`),
   the spread over the seeds (`nncl_synthetic_seed_spread.csv`) and the nagging
   predictors (`nncl_synthetic_nagging.csv`; Richman & Wuthrich 2020: the CL factors of
   10 seeds averaged per development period, one predictor per block of 10 seeds), with
   a figure of the bias per training
   (`output/tables/04_NN-chain-ladder/synthetic/`,
   `output/figures/04_NN-chain-ladder/synthetic/`)

What differs from the machine data: with at most 2,952 learning cells per development
period the batch of 10,000 holds all rows, so an epoch is one gradient step and a paper
run is 100 steps (the paper's j = 1: about 18,400); the portfolio is one LoB, so a zero
claims factor with a positive numerator over a zero denominator has nothing to be pooled
over and stays infinite, which is harmless while the first factor of its accident year
is 0 (accident years 14-16) and stops the reserves otherwise; SynthETIC pays no
recoveries, so the zero claims features are the cells with C = 0.

Functions: `R/nn_chain_ladder.R` (networks of one or more hidden layers, optimisers, zero
claims factors, reserves, Mack),
`R/plots_nn_chain_ladder.R` (figures); checks in `tests/testthat/test-nn_chain_ladder.R`.
Packages: MASS and doParallel (the machine), keras3. Deviations from the paper: the zero
claims features are the cells with C <= 0 (recoveries), 0/0 gives a factor 1, and a
zero claims factor with a positive numerator over a zero denominator takes the ratio
pooled over the LoBs (LoB 3, accident year 1997). `analysis/00_claim-simulation/
Simulation.Machine.V1/` is the authors' machine V1, unmodified: third-party code, not
lint-clean, sourced only by the simulation script.
