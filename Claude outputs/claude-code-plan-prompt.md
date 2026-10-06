You are in plan mode. Do not create, move, edit or run anything yet. Read what is listed below, ask me questions so that we can clarify this prompt further, and then give me a plan I can approve. Ask again once the plan is approved and before you implement any of it: nothing is to be implemented on an assumption you have not put to me. Accuracy matters more than speed here: take your time, and read the code and the two papers themselves instead of working from memory of them.

# What I want

I am writing a masters thesis on claims reserving with neural networks. The code sits in two R projects that grew separately and now overlap:

- `C:\Users\frang\Projects\Masters-Research-R`: claim simulation, Mack chain ladder, ODP GLM (ccODP), the bCCNN, and the neural-network chain ladder of Wuthrich (2018), which I call the **MackNet** (code prefix `nncl_`).
- `C:\Users\frang\Projects\TabM reserving`: the bCCNN again, plus the main new model of my research, the **TabMbCCNN** (the bCCNN fitted as a TabM weight-sharing ensemble), with its stopping rules and bootstrap.

Plan one new project that replaces both: every model fitted by one code base, on the same datasets, under the same validation schemes and stopping rules, feeding one set of thesis tables. Nothing that either project currently produces may be lost, and nothing may exist twice. Where the two projects do the same job in two ways (the section "Duplication I know about" lists the cases I have found), the plan keeps one implementation and says which and why.

Put the new project in a new sibling folder, `C:\Users\frang\Projects\Thesis-Reserving-Models`, with its own git repository. The two existing projects stay untouched as archives: copy from them, never edit them.

# Read first

1. Both projects in full: `README.md`, `config.yml`, `analysis/00_setup.R`, every file in `R/`, every script in `analysis/`, `tests/`, and the file names in `output/tables` and `output/figures` (they are the inventory of what must survive). `analysis/00_claim-simulation/Simulation.Machine.V1/` is the authors' simulation machine, third-party code that is only sourced.
2. Wuthrich (2018), *Neural networks applied to chain-ladder reserving*, EAJ 8:407-436: Sections 2 to 5 and Listings 1 and 2. Section 4 (zero claims features) and the reserve formula (5.1) matter most.
3. Gabrielli (2020), *Claims reserving and neural networks*, PhD thesis ETH Zurich: Chapter 4 and Paper C (Gabrielli, Richman & Wuthrich 2020, *Neural network embedding of the over-dispersed Poisson reserving model*): Section 2 with eqs. (1) to (6) (Section 2.3 holds the dispersion estimate (5), the RMSEP (6) and the parametric bootstrap), Sections 3.2 to 3.3.4 with eqs. (13) to (16), Tables 2 to 5, and Listings 1 to 4.

Both PDFs are in `papers/` of the new folder. If they are not there, ask me for them. Whenever the plan relies on a paper, cite the section, equation, table or listing.

# The three datasets

Every model is fitted on all three. They give 16 triangles in total (6 + 4 + 6).

| dataset | what it is | where it is now |
|---|---|---|
| Machine, six LoBs | Gabrielli & Wuthrich (2018) individual claims simulation machine, the portfolio of Paper C Listing 1: seed 75, six lines of business, 1,198,888 claims, 12 x 12 triangles, accident years 1994 to 2005 | `TabM reserving/data/raw/simulated_claims.csv` and `simulation_manifest.json` (git-ignored) |
| Machine, four LoBs | the same machine, the portfolio of Wuthrich (2018) Listing 1: V = 5,000,000, seed1 = 100, four lines of business, 5,003,204 claims, 12 x 12 | `Masters-Research-R/data/raw/claim-simulation-machine/claims.csv` (about 395 MB), made by `analysis/00_claim-simulation/individual_claims_simulation_machine.R` |
| SynthETIC, six LoBs | annual 20 x 20, six lines of business that each develop differently (specified below), individual claims with the five covariates of the current simulation (Legal Representation, Injury Severity, Age of Claimant, Vehicle type, Business use); payments after development year 20 are reported apart | not simulated yet. `Masters-Research-R/analysis/00_claim-simulation/short_tailed_claims.R` is the starting point: it simulates a single portfolio (seed 2026, 399,568 claims, in `data/raw/claim-simulation-annual/`) |

## The SynthETIC dataset: six lines of business

The current SynthETIC data is one portfolio and one triangle. Replace it as a thesis dataset by one SynthETIC dataset with six lines of business, still annual 20 x 20, stored like the machine data (one claims file and one transactions file with a `LoB` column). Each line has its own claim development pattern:

| line | reporting delay | settlement | claim amounts | inflation across calendar years |
|---|---|---|---|---|
| 1 | short | quick | small | no hyperinflation |
| 2 | longer | quick | small | no hyperinflation |
| 3 | longer | longer | small | no hyperinflation |
| 4 | longer | longer | large and volatile | no hyperinflation |
| 5 | short | quick | normal | hyperinflation |
| 6 | longer | slower | normal | hyperinflation |

I have not fixed the numbers behind these words. Propose a value for every level and show me the table of parameters before anything is simulated. Anchor the proposal to what `short_tailed_claims.R` does now, and say which line, if any, keeps the current settings:

- Reporting delay: `notidel_mean` and `notidel_cv` (now environment 1 of Al-Mudafer et al. 2021: mean 0.49 quarters, cv 1.92).
- Settlement: `setldel_mean` and `setldel_cv` (now mean 6.58 quarters, cv 1.02), which also drive the payment delays.
- Claim amounts: `sev_cdf` and `ref_claim` (now 200,000). "Large and volatile" means a higher mean and a heavier tail, so state both.
- Inflation: `base_inflation` (now 2% a year) and the superimposed inflation `si_occurrence` and `si_payment` (now switched off). The hyperinflation of lines 5 and 6 must act on the calendar year of payment, not on the accident year.
- Also to settle: the claim volume of each line (now 20,000 claims a year), whether the six lines share the five covariates with their frequency, severity and delay relativities, and the seed of each line.

Lines 5 and 6 are meant to break the accident-year by development-year structure that the chain ladder and the ccODP assume, and lines 3, 4 and 6 are meant to settle slowly. Do not tune the data to make any model look better. The plan must include a description table per line that shows the simulated data has the intended properties (mean reporting and settlement delay, mean and coefficient of variation of the claim size, cumulative share paid by development year, the calendar-year inflation index, the share of the ultimate that lies in the observed triangle, and the amount paid after development year 20), as `summary.csv` and `development_by_level.csv` do for the current portfolio. Tell me how large the part after development year 20 becomes on the long-settlement lines and how the true reserve is defined there.

The existing single-portfolio data stays in the new project only for the regression check of the current Mack, ODP GLM and bCCNN results.

# Decisions already made (do not reopen these)

- **Validation schemes: three, side by side.** (a) Rolling origin after Al-Mudafer, Avanzi, Taylor & Wong (2021) Section 3.1, as in `rolling_origin()` and `rolling_origin_fit()` of Masters-Research-R. (b) The time-aware hold-out of the last calendar years, as in `time_aware_split()` of TabM reserving. (c) Paper C's 50/50 claim-level split (Listing 2).
- **Stopping rules: the three of TabM reserving** (`R/early stopping.R`, `stopping:` in its `config.yml`), applied to every bCCNN and TabM fit under every scheme: the protocol stop (minimum of the 51-step smoothed pooled validation curve), the slope elbow (tolerance 0.01, window 200, with the sensitivity table over tolerances 0.005, 0.01, 0.02, 0.05), and Paper C's fixed 300 steps. The search window is 2,000 full-batch steps for every scheme (TabM reserving currently uses 6,000 on the time-aware split), held in `config.yml`. Keep the `at_edge` flag in every table, because with 2,000 steps the protocol minimum may sit at the end of the window.
- **Mack and ccODP are two separate models.** Each is fitted on its own, and each has its own rows in every results table. Paper C states that the two give the same reserves, but I do not want the code to rely on that: no table may fill a "chain ladder" column from the ccODP fit or the other way round, and no script may stop when they differ.
- **Dispersion: Paper C's.** The ccODP dispersion is eq. (5), the unscaled in-sample deviance over |D_I| - (I + J). The network dispersion is Section 3.3.2: the ccODP estimate reduced by the relative decrease of the validation loss at the chosen stop, with a negative decrease counted as zero. This is the headline estimate everywhere. Pearson's estimate and the other RMSEP methods that `ODP glm fit plot.R` computes stay as comparisons.
- **Bias and RMSE as the two papers define them.** Bias is the reserve minus the true outstanding payments. "RMSE" is the root mean square error of prediction: Mack's analytic root msep (Wuthrich 2018, Tables 2 and 3) and the conditional RMSEP of Paper C, eq. (6) for the ccODP and eqs. (15) and (16) for the networks.
- **Bootstrap: Paper C's parametric bootstrap, 1,000 replicates everywhere**, for the ccODP (Section 2.3) and for every bCCNN and TabM variant (Section 3.3.4). Mack keeps its analytic root msep. The MackNet is not bootstrapped and reports a bias only, as in Wuthrich (2018).

# The models

## 1. MackNet (Wuthrich 2018)

Start from the seven runs of the `nncl:` block of `Masters-Research-R/config.yml` with the hyper-parameters as they stand: Listing 2 with q = 5, 10 and 20 hidden tanh neurons (rmsprop, mse, 100 epochs, batch size 10,000, validation split 0.1), then S1 Adam, S2 early stopping, S3 chain-ladder start and S4 balance correction at q = 20. Fit them on all three datasets.

- Architecture sensitivities: two networks with the layers and neurons of the bCCNN (Paper C Listing 4), to compare the paper's single hidden layer with a deeper network.

  | architecture | hidden layers | dropout |
  |---|---|---|
  | paper | one tanh layer of q = 5, 10 or 20 neurons | none |
  | D1 | three tanh layers of 20, 15 and 10 neurons | none |
  | D2 | three tanh layers of 20, 15 and 10 neurons | 10% after every hidden layer |

  D1 changes only the depth and width; D2 also takes the bCCNN's dropout, so the effect of dropout can be read off between the two. Each is run the way q = 20 is: with Listing 2's training, and then under S1 to S4 (each of them adding one change, S4 being the balance correction of that network's S3). That makes 7 + 5 + 5 = 17 runs. Everything outside the hidden layers stays as in Listing 2 (exponential output, offset, mse loss, one network per development period). D1 and D2 are my design, not the paper's, so mark them as such in the code comments, and say how the parameter count of EAJ Table 5 is reported for them.
- Runs in total: every one of the 17 runs is fitted under each of the four feature pre-processing variants below, 68 runs per dataset.
- Seeds: every run is fitted with 5 seeds, held in `config.yml`, and reported as the mean and the spread over the seeds of its reserves, bias and losses. Today each run uses the single seed 2026; keep that seed among the five so that the current results can still be reproduced. Differences between runs that are smaller than the spread over seeds must not be presented as findings. TabM reserving reports a seed-0 reserve with the mean and standard deviation over seeds, so propose one way of reporting seeds for all models.
- Cost: the seven runs take about 75 minutes on the four-LoB portfolio now, so 68 runs with 5 seeds are of the order of 60 hours on that dataset alone. Measure it, put it in the experiment grid, and make the runs checkpointed per run and seed, as `nncl_fit_<run>.rds` is now.
- Features: on the two machine portfolios LoB, cc and inj_part (categorical) and AQ and age (continuous). On SynthETIC the line of business and the five covariates, all categorical. The input dimension changes with the dataset and the variant (100 for the base on the four-LoB portfolio), so nothing may be hard-coded.
- Feature pre-processing, four variants crossed with the 17 runs:

  | variant | continuous covariates | categorical covariates |
  |---|---|---|
  | base | MinMax scaling to [-1, 1] | dummy coding, the label with the most reported claims as reference |
  | P1 | normalisation (mean 0, variance 1) | an entity embedding for each categorical variable |
  | P2 | zero-one scaling (MinMax to [0, 1]) | an entity embedding for each categorical variable |
  | P3 | zero-one scaling (MinMax to [0, 1]) | one-hot encoding, every label its own column |

  The base is the current design of `NN chain ladder fit.R` unchanged (Wuthrich 2018, Section 3.3) and is the comparison model for P1 to P3. Everything else stays as in the run: one network per development period, the same hidden layers, loss, optimiser, offset and validation split. For the entity embeddings, propose the embedding dimension of each variable and how the network of Listing 2 changes (one integer input and embedding layer per categorical variable, concatenated with the continuous covariates before the hidden layer), and say from which rows the scaling statistics are computed. P1 to P3 are my design, not the paper's, so mark them as such in the code comments. On SynthETIC there is no continuous covariate, so P1 and P2 are the same run there: fit it once, report it under both names, and say so in the tables.
- Report every variant: all 68 runs of each dataset appear in the MackNet tables (parameters, run time and losses as in EAJ Table 5; reserves, zero claims reserve and bias by LoB as in the sensitivity table), in the run-time table and in the comparison table, and the figures cover them too. There is no headline MackNet: every variant is a row of the comparison table, side by side, and no variant is to be singled out because its bias against the true reserves is smallest, since the true reserves are the test data. The current scripts draw the figures for one or two runs only, so propose how the figures show 68 runs against the paper's network with the base pre-processing without 68 copies of each.
- Zero claims features: apply Section 4 of the paper on every dataset. Part 1 covers the cells with a positive diagonal and part 2 the zero claims features with the factors g of Section 4.2, giving the reserves (5.1). Carry over the three deviations documented in `R/nn_chain_ladder.R` (zero set defined by C <= 0 because of recoveries, 0/0 gives a factor 1, a positive numerator over a zero denominator takes the ratio pooled over the LoBs) and say how each behaves on the new data. Report per dataset how many cells and how much reserve fall into part 2.
- Keep every table and figure of the three `trackA_wuthrich2018` scripts (EAJ Tables 2 to 5, Figures 2 to 4 and 7 to 9, the data description tables and figures), with analogues on the new datasets using the features each one has.

## 2. Mack chain ladder and ccODP

Fit both on all 16 triangles, with every table and figure that `Mack chainladder fit.R`, `ODP glm fit plot.R` and `01_data and ccODP/data and ccODP.R` produce now.

## 3. bCCNN and its nagging predictor

The single bCCNN of Paper C eqs. (13) and (14), Listing 4: hidden layers (20, 15, 10), tanh, dropout 0.1, frozen ccODP embeddings, RMSprop (learning rate 0.001, rho 0.9, epsilon 1e-7), full batch, Keras `poisson` loss. Fit it on all 16 triangles under all three validation schemes: the 2,000-step validation run, the three stopping rules, then the refit on the full triangle at each stop.

- All figures and tables of both projects for this model: the rolling-origin partition plots and test-error table, validation and fit loss curves, the bCCNN versus ccODP heatmap, the Pearson residual heatmaps, cumulative development factors, bias and RMSEP by accident year, bootstrap densities and the dispersion comparison (Masters-Research-R); the Paper C Figure 2 curves with the stops marked, the pooled curves, the bias comparison and the stop and sensitivity tables (TabM reserving).
- New: a nagging predictor (Richman & Wuthrich 2020, *Nagging predictors*), the average of the fitted means of 20 bCCNNs that differ only in their seed, with the reserve taken from the averaged means. Report it next to the 20 individual fits. TabM reserving's `packed_tanh` configuration is already 20 independent bCCNNs trained in lockstep, apart from the skip weight (fixed at 1 there, trainable in the single bCCNN). Say whether the nagging predictor should be 20 runs of the single bCCNN or a variant of the packed network, and do not build the same thing twice.

## 4. TabMbCCNN

All five ensembles of TabM reserving (`tabm_tanh_signs`, `tabm_tanh_normal`, `tabm_relu_signs`, `tabm_relu_normal`, `packed_tanh`) with k = 20, on all 16 triangles, under all three validation schemes and all three stopping rules, with the elbow sensitivity table and every figure and table TabM reserving produces now (including the submodel reserves).

# Run times

Record the run time of every neural network variant and produce one table of them: model and variant, dataset and triangle, validation scheme, stopping rule and steps, trainable parameters, seconds per fit and per step, split into validation run, refit and bootstrap. Today only the MackNet (per development period) and TabM reserving's bootstrap store a run time; the validation runs and refits print theirs to the log, and the bCCNN of Masters-Research-R records none. Timings must be comparable: say how they will be measured (threads, nothing else running, curve recorder off), since TabM reserving's README notes that the recorder adds about 15 ms to a 33 ms step and that the chain runs six processes in parallel.

# The comparison table

One large table that sets every neural network against Mack and against the ccODP. One row per dataset, triangle, model variant, validation scheme and stopping rule. Columns at least: true reserve, reserve, bias and bias in percent, steps, dispersion, process standard deviation, estimation standard deviation, RMSEP, coefficient of variation, in-sample and out-of-sample deviance, spread over seeds, run time, and the differences in absolute bias and in RMSEP to Mack and to the ccODP. Write it as one long tidy CSV and as wide tables ready for the thesis (propose the layout). Cells that do not exist, such as an RMSEP for the MackNet, are shown as missing, never as zero. The MackNet enters with all 68 variants per dataset, which makes this table very long, so propose how the wide thesis tables stay readable (for example one block per model family) without dropping any variant from the tidy CSV. Paper C makes no dependence assumption between LoBs, so say how portfolio totals are treated for the RMSEP before adding anything up.

# Bootstrap section

A separate section that runs Paper C's parametric bootstrap for the ccODP, the single bCCNN, the nagging bCCNN and the five ensembles: resample the upper triangle from assumption (1) around the fitted means with the model's dispersion, refit from scratch exactly as the original was fitted (a fresh ccODP, then the network started in it and trained for the chosen steps), and combine the variance of the refitted reserves with the process variance phi times the reserve. Runs must be checkpointed and resumable, as both projects do now, and must report the Monte Carlo error of the RMSEP as `rmsep_table()` does.

I chose 1,000 replicates for every model, triangle, scheme and rule, and I know this is heavy. By the timings above, one 1,000-step ensemble fit on a 12 x 12 triangle takes roughly half a minute (the 20 x 20 triangles have 210 observed cells instead of 78, so measure those), so 1,000 replicates of one combination take hours, and the ensembles alone have 5 x 16 x 3 x 3 = 720 combinations before the single and the nagging bCCNN. Do not reduce the count on your own. Measure the real cost per fit, give me the projected CPU-hours for the whole grid, and propose an order of runs that delivers the headline results first, the parallel layout, and every saving that does not change the results (for example, a refit at a given step count does not depend on the validation scheme).

# Things I already found that the plan must handle

- **A negative cell breaks the ccODP on the four-LoB portfolio.** LoB 2, accident year 1994, development year 11 has a negative increment of about -296 (in 1,000) in the observed triangle (`output/tables/nncl_table4_triangles.csv`). A quasi-Poisson GLM, the Poisson deviance and the ODP sampler all need non-negative cells, and the thesis (Section 4.2) says its six-LoB data was chosen to avoid exactly this. Check every triangle, including the training triangles of each validation scheme, and propose a treatment for me to choose. This is also a case where Mack and the ccODP cannot agree.
- **Hard stops on ccODP = chain ladder.** `bCCNN fit.R` and `data and ccODP.R` call `stopifnot()` on that equality. Turn it into a reported check.
- **Zero cells and empty halves.** The current SynthETIC upper triangle already has a zero cell, the new long-delay lines may have more, and `bCCNN fit.R` already drops validation cells whose accident or development year has no payments in the training half. Make that rule common to all schemes.
- **Dispersion at the fixed 300 steps.** TabM reserving gives the 300-step stop no reduction (marked INFERRED in `06_bootstrap/bootstrap.R`), while Paper C reduces by the validation decrease at its 300 steps (Table 3). Tell me which the merged code will do.
- **The six-LoB portfolio has no generator in either project**, only the CSV and its manifest (seed 75, std1 = std2 = 0.85, V 1,000,000 and 200,000, sample.kind "Rounding"). Plan a script that regenerates it from Paper C Listing 1 with the machine already in Masters-Research-R, and check it against the existing file.
- **Scheme settings do not transfer between triangle sizes.** The rolling-origin settings (test periods 5 and 2, validation 2, exclude 2) were scaled for 20 x 20 and the hold-out of 2 years for 12 x 12. Propose settings for the other size and show the cell counts of every partition.
- **MackNet on SynthETIC.** The five covariates are all categorical and have 2 x 6 x 5 x 4 x 2 = 480 level combinations per line, so there are far fewer cells than on the machine data and a batch of 10,000 may be a large part of the sample. Keep the hyper-parameters, report the number of learning cells per development period, and flag where the setting stops meaning what it meant in the paper. Because none of these covariates is continuous, the pre-processing variants P1 and P2 coincide on SynthETIC and only the machine data separates them.
- **Two Keras backends.** TabM reserving runs keras3 1.5.1 on torch (venv `C:/Users/frang/.venvs/dlfa`, TensorFlow not installed), and its custom layers and tests were validated there. Masters-Research-R is documented as running on TensorFlow. The new project has one backend. Propose which, and list which existing numbers will no longer reproduce exactly.

# Conventions to keep

The layout and style of Masters-Research-R: numbered folders under `analysis/`, short scripts that run top to bottom, functions only in `R/`, one `analysis/00_setup.R`, one `config.yml` read with `config::get()` holding every setting, a `quick` profile that runs the whole chain in minutes, renv, `here`, testthat, lintr defaults with `%>%` as the only pipe, comments that cite the paper section or equation, and INFERRED on anything the papers do not state. Keep TabM reserving's checkpointing and its `run_all.ps1` chain. Units differ today (thousands on the machine data, millions on SynthETIC): settle them per dataset in the config.

# Duplication I know about

Resolve each of these to one implementation, and look for more:

- `ccodp_fit()` exists in both `R/fit ODP GLM.R` files with different inputs (matrix with NA and a `cells` argument, against a triangle object with a mask), different GLM tolerances and different ways of reading the coefficients.
- `poisson_deviance()` exists in both `R/loss functions.R` files.
- `bccnn_model()` exists in both `R/nn_models.R` files (weights set after the build, against constant initialisers, which TabM reserving's README explains is the safer one for reproducible seeds); `bccnn_fit()` and `nn_fit()` both train it and record curves.
- Two triangle representations: `claims_triangle()`, `triangle_sets()`, `upper_triangle()`, `lower_triangle()` (1-based, NA below the diagonal) against `triangle()`, `runoff_mask()`, `train_cells()`, `aggregate_claims()`, `lob_triangles()` (0-based, mask).
- The 50/50 claims split is coded twice (inside `triangle_sets()` and as `split_claims()`), with different sort keys.
- Early stopping: `which.min()` on the raw validation curve in Masters-Research-R against the rules in `R/early stopping.R`.
- Bootstrap: `odp_sample()`, `ccodp_bootstrap()`, `bccnn_bootstrap()`, `rmsep_table()` against `sample_triangle()`, `bootstrap_ccodp()`, `bootstrap_nn()`, `bootstrap_result()`, `reduced_phi()`.
- `bias_plot()` is defined in both `R/plots.R` files with different arguments, so sourcing both would silently overwrite one. `loss_plot()` and `curves_plot()` draw the same kind of figure.
- Mack is fitted in `01_Mack model/Mack chainladder fit.R` and again in `nncl_mack()`; chain-ladder reserves are computed in `cl_reserves()` and by `chainladder()` calls in several scripts.
- Two `00_setup.R` files and two `config.yml` files with different key layouts and seed conventions.

# What the plan must contain

1. The folder tree of the new project and the run order of its scripts.
2. A function map: every function of both projects, what happens to it (kept, merged into which function, dropped) and why.
3. An output map: every table and figure either project produces now, the script and function that will produce it in the new project, and the datasets it will now be produced for. Flag any file in the `output` folders that no current script produces.
4. The `config.yml` layout.
5. The experiment grid (dataset x triangle x model x scheme x rule) with the number of fits, the measured or estimated time of each block, and the run order.
6. A regression check to run before anything new: the merged code reproduces the existing results of both projects on the data they already ran (for example `table2_ccodp.csv`, the claim-level selection and summary tables, `mack_raw_*`, `odp_*`, `nncl_*`; the Mack, ODP GLM and bCCNN results are on the current single-portfolio SynthETIC data), with a list of what will not reproduce and why.
7. The tests carried over from both projects and the new ones.
8. The work in stages I can approve one at a time, each with its own check.
9. Your open questions and every assumption you made, separated from what you read in the code or the papers.

# Ask me before finalising the plan

Where a paper and my code disagree, or my two projects disagree with each other, show me both and ask; do not pick one silently. I expect questions at least on: the parameter values of the six SynthETIC lines; the embedding dimensions and scaling statistics of the MackNet pre-processing variants; the treatment of the negative cell; whether stops are shared across the LoBs of a portfolio (pooled curve, as now) or taken per triangle, given that the six SynthETIC lines are built to develop differently; whether I also want refits at every elbow tolerance or only the table of stops; whether the `final_fit: partition` option of the rolling origin survives; and the run order of the bootstrap grid.

These are a minimum. Ask about anything else in this prompt that is unclear, underspecified or that you would do differently, and tell me where my wording should change. Before implementing each stage, put any questions that stage raises to me first.
