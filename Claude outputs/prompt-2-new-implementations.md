You are in plan mode. Do not create, move, edit or run anything yet. Read what is listed below, ask me questions so that we can clarify this prompt further, and then give me a plan I can approve. Ask again once the plan is approved and before you implement any of it: nothing is to be implemented on an assumption you have not put to me. Accuracy matters more than speed here: take your time, and read the code and the two papers themselves instead of working from memory of them.

# What I want

I am writing a masters thesis on claims reserving with neural networks. This is the second of two jobs. The first merged my two old R projects into one, `C:\Users\frang\Projects\Thesis-Reserving-Models`, which reproduces their results. This job adds the new datasets, models and experiments to that project, so that every model is fitted on the same datasets under the same validation schemes and stopping rules and feeds one set of thesis tables.

The models are Mack's chain ladder, the ccODP (ODP GLM), the neural-network chain ladder of Wuthrich (2018), which I call the **MackNet**, the **bCCNN** of Paper C, and the main new model of my research, the **TabMbCCNN** (the bCCNN fitted as a TabM weight-sharing ensemble).

# Read first

1. The merged project in full: `README.md`, `config.yml`, `analysis/00_setup.R`, every file in `R/`, every script in `analysis/`, `tests/`, and its regression check.
2. Wuthrich (2018), *Neural networks applied to chain-ladder reserving*, EAJ 8:407-436: Sections 2 to 5 and Listings 1 and 2. Section 3.3 (feature pre-processing), Section 4 (zero claims features) and the reserve formula (5.1) matter most.
3. Gabrielli (2020), *Claims reserving and neural networks*, PhD thesis ETH Zurich: Chapter 4 and Paper C (Gabrielli, Richman & Wuthrich 2020, *Neural network embedding of the over-dispersed Poisson reserving model*): Section 2 with eqs. (1) to (6) (Section 2.3 holds the dispersion estimate (5), the RMSEP (6) and the parametric bootstrap), Sections 3.2 to 3.3.4 with eqs. (13) to (16), Tables 2 to 5, and Listings 1 to 4.

Both PDFs are in `papers/`. If they are not there, ask me for them. Whenever the plan relies on a paper, cite the section, equation, table or listing.

The two old projects, `C:\Users\frang\Projects\Masters-Research-R` and `C:\Users\frang\Projects\TabM reserving`, are archives: read them if you need to, never edit them. The file and function names in this prompt are the ones those projects use. Where the merge renamed something, use the merged project's name and tell me the mapping.

# Rules for this job

- Extend the functions the merged project has. No job may get a second implementation.
- Every setting goes into `config.yml`. Nothing new is hard-coded.
- The regression check of the merge must still pass after every stage. New outputs get their own names and never overwrite the results it compares against.
- Keep the conventions of the merged project: short scripts that run top to bottom, functions only in `R/`, a `quick` profile that runs the whole chain in minutes, checkpointed and resumable runs, tests, lintr, comments that cite the paper section or equation, and INFERRED on anything the papers do not state. What is my own design and not a paper's is marked as such.

# The three datasets

Every model is fitted on all three. They give 16 triangles in total (6 + 4 + 6).

| dataset | what it is | state |
|---|---|---|
| Machine, six LoBs | Gabrielli & Wuthrich (2018) individual claims simulation machine, the portfolio of Paper C Listing 1: seed 75, six lines of business, 1,198,888 claims, 12 x 12 triangles, accident years 1994 to 2005 | in the merged project; so far used by the ccODP, the bCCNN and the ensembles |
| Machine, four LoBs | the same machine, the portfolio of Wuthrich (2018) Listing 1: V = 5,000,000, seed1 = 100, four lines of business, 5,003,204 claims, 12 x 12 | in the merged project; so far used by the MackNet only |
| SynthETIC, six LoBs | annual 20 x 20, six lines of business that each develop differently (specified below), individual claims with the five covariates of the current simulation (Legal Representation, Injury Severity, Age of Claimant, Vehicle type, Business use); payments after development year 20 are reported apart | not simulated yet. `short_tailed_claims.R` is the starting point: it simulates a single portfolio (seed 2026, 399,568 claims) |

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

The existing single-portfolio data stays in the project only for the regression check.

# Decisions already made (do not reopen these)

- **Validation schemes: three, side by side.** (a) Rolling origin after Al-Mudafer, Avanzi, Taylor & Wong (2021) Section 3.1, as in `rolling_origin()` and `rolling_origin_fit()`. (b) The time-aware hold-out of the last calendar years, as in `time_aware_split()`. (c) Paper C's 50/50 claim-level split (Listing 2).
- **Stopping rules: the three of TabM reserving** (`R/early stopping.R`), applied to every bCCNN and TabM fit under every scheme: the protocol stop (minimum of the 51-step smoothed pooled validation curve), the slope elbow (tolerance 0.01, window 200, with the sensitivity table over tolerances 0.005, 0.01, 0.02, 0.05), and Paper C's fixed 300 steps. The search window is 2,000 full-batch steps for every scheme (the time-aware split used 6,000 until now). Keep the `at_edge` flag in every table, because with 2,000 steps the protocol minimum may sit at the end of the window.
- **Mack and ccODP are two separate models.** Each is fitted on its own and each has its own rows in every results table. Paper C states that the two give the same reserves, but that will not hold on all of the new data, and no table may fill one from the other.
- **Negative cells are set to zero.** A negative incremental payment in a triangle is replaced by zero before the triangle is used. The four-LoB portfolio has one in the observed triangle: LoB 2, accident year 1994, development year 11, about -296 (in 1,000), see `nncl_table4_triangles.csv`. A quasi-Poisson GLM, the Poisson deviance and the ODP sampler all need non-negative cells, so the ccODP, the bCCNN and the ensembles cannot be fitted otherwise. Check every triangle of every dataset, including the training triangles of each validation scheme and the true lower triangles, and list every cell that is changed and the amount. I take this to mean that Mack, fitted on the same aggregate triangle, also sees the zeroed cell, that the MackNet keeps the paper's own treatment at the level of its feature cells, and that the true outstanding payments are not altered. Confirm these three points with me.
- **Dispersion: Paper C's.** The ccODP dispersion is eq. (5), the unscaled in-sample deviance over |D_I| - (I + J). The network dispersion is Section 3.3.2: the ccODP estimate reduced by the relative decrease of the validation loss at the chosen stop, with a negative decrease counted as zero. This is the headline estimate everywhere. Pearson's estimate and the other RMSEP methods of the ODP GLM script stay as comparisons.
- **Bias and RMSE as the two papers define them.** Bias is the reserve minus the true outstanding payments. "RMSE" is the root mean square error of prediction: Mack's analytic root msep (Wuthrich 2018, Tables 2 and 3) and the conditional RMSEP of Paper C, eq. (6) for the ccODP and eqs. (15) and (16) for the networks.
- **Bootstrap: Paper C's parametric bootstrap, 1,000 replicates everywhere**, for the ccODP (Section 2.3) and for the bCCNN and TabM models that are carried forward (Section 3.3.4). Mack keeps its analytic root msep. The MackNet is not bootstrapped and reports a bias only, as in Wuthrich (2018).

# The models

## 1. MackNet (Wuthrich 2018)

Start from the seven runs of the `nncl:` block of the config with the hyper-parameters as they stand: Listing 2 with q = 5, 10 and 20 hidden tanh neurons (rmsprop, mse, 100 epochs, batch size 10,000, validation split 0.1), then S1 Adam, S2 early stopping, S3 chain-ladder start and S4 balance correction at q = 20. Fit them on all three datasets.

- Architecture sensitivities: two networks with the layers and neurons of the bCCNN (Paper C Listing 4), to compare the paper's single hidden layer with a deeper network.

  | architecture | hidden layers | dropout |
  |---|---|---|
  | paper | one tanh layer of q = 5, 10 or 20 neurons | none |
  | D1 | three tanh layers of 20, 15 and 10 neurons | none |
  | D2 | three tanh layers of 20, 15 and 10 neurons | 10% after every hidden layer |

  D1 changes only the depth and width; D2 also takes the bCCNN's dropout, so the effect of dropout can be read off between the two. Each is run the way q = 20 is: with Listing 2's training, and then under S1 to S4 (each of them adding one change, S4 being the balance correction of that network's S3). That makes 7 + 5 + 5 = 17 runs. Everything outside the hidden layers stays as in Listing 2 (exponential output, offset, mse loss, one network per development period). Say how the parameter count of EAJ Table 5 is reported for D1 and D2.
- Runs in total: every one of the 17 runs is fitted under each of the four feature pre-processing variants below, 68 runs per dataset.
- Seeds: every run is fitted with 5 seeds and reported as the mean and the spread over the seeds of its reserves, bias and losses. Until now each run used the single seed 2026; keep that seed among the five. Differences between runs that are smaller than the spread over seeds must not be presented as findings. Propose one way of reporting seeds for all models.
- Cost: the seven runs take about 75 minutes on the four-LoB portfolio, so 68 runs with 5 seeds are of the order of 60 hours on that dataset alone. Measure it and put it in the experiment grid.
- Features: on the two machine portfolios LoB, cc and inj_part (categorical) and AQ and age (continuous). On SynthETIC the line of business and the five covariates, all categorical. The input dimension changes with the dataset and the variant (100 for the base on the four-LoB portfolio).
- Feature pre-processing, four variants crossed with the 17 runs:

  | variant | continuous covariates | categorical covariates |
  |---|---|---|
  | base | MinMax scaling to [-1, 1] | dummy coding, the label with the most reported claims as reference |
  | P1 | normalisation (mean 0, variance 1) | an entity embedding for each categorical variable |
  | P2 | zero-one scaling (MinMax to [0, 1]) | an entity embedding for each categorical variable |
  | P3 | zero-one scaling (MinMax to [0, 1]) | one-hot encoding, every label its own column |

  The base is the current design of `NN chain ladder fit.R` unchanged (Wuthrich 2018, Section 3.3) and is the comparison model for P1 to P3. Everything else stays as in the run. For the entity embeddings, propose the embedding dimension of each variable and how the network of Listing 2 changes (one integer input and embedding layer per categorical variable, concatenated with the continuous covariates before the first hidden layer), and say from which rows the scaling statistics are computed. On SynthETIC there is no continuous covariate, so P1 and P2 are the same run there: fit it once, report it under both names, and say so in the tables.
- Report every variant: all 68 runs of each dataset appear in the MackNet tables (parameters, run time and losses as in EAJ Table 5; reserves, zero claims reserve and bias by LoB as in the sensitivity table), in the run-time table and in the comparison table, and the figures cover them too. There is no headline MackNet: every variant is a row of the comparison table, side by side, and no variant is to be singled out because its bias against the true reserves is smallest, since the true reserves are the test data. The current scripts draw the figures for one or two runs only, so propose how the figures show 68 runs against the paper's network with the base pre-processing without 68 copies of each.
- Zero claims features: apply Section 4 of the paper on every dataset. Part 1 covers the cells with a positive diagonal and part 2 the zero claims features with the factors g of Section 4.2, giving the reserves (5.1). Carry over the three deviations documented in `R/nn_chain_ladder.R` (zero set defined by C <= 0 because of recoveries, 0/0 gives a factor 1, a positive numerator over a zero denominator takes the ratio pooled over the LoBs) and say how each behaves on the new data. Report per dataset how many cells and how much reserve fall into part 2.
- Keep every table and figure of the MackNet scripts (EAJ Tables 2 to 5, Figures 2 to 4 and 7 to 9, the data description tables and figures), with analogues on the new datasets using the features each one has.

## 2. Mack chain ladder and ccODP

Fit both on all 16 triangles, with every table and figure the Mack, ODP GLM and ccODP scripts produce now.

## 3. bCCNN and its nagging predictor

The single bCCNN of Paper C eqs. (13) and (14), Listing 4: hidden layers (20, 15, 10), tanh, dropout 0.1, frozen ccODP embeddings, RMSprop (learning rate 0.001, rho 0.9, epsilon 1e-7), full batch, Keras `poisson` loss. I call this Paper C's setting. Fit it on all 16 triangles under all three validation schemes: the 2,000-step validation run, the three stopping rules, then the refit on the full triangle at each stop.

- All figures and tables the project has for this model: the rolling-origin partition plots and test-error table, validation and fit loss curves, the bCCNN versus ccODP heatmap, the Pearson residual heatmaps, cumulative development factors, bias and RMSEP by accident year, bootstrap densities, the dispersion comparison, the Paper C Figure 2 curves with the stops marked, the pooled curves, the bias comparison and the stop and sensitivity tables.
- New: a nagging predictor (Richman & Wuthrich 2020, *Nagging predictors*), the average of the fitted means of 20 bCCNNs that differ only in their seed, with the reserve taken from the averaged means. Report it next to the 20 individual fits. The `packed_tanh` configuration at K = 20 is already 20 independent bCCNNs trained in lockstep, apart from the skip weight (fixed at 1 there, trainable in the single bCCNN). Say whether the nagging predictor should be 20 runs of the single bCCNN or a variant of the packed network, and do not build the same thing twice.

## 4. TabMbCCNN

All five ensembles (`tabm_tanh_signs`, `tabm_tanh_normal`, `tabm_relu_signs`, `tabm_relu_normal`, `packed_tanh`) with Paper C's setting for the hidden layers, dropout and optimiser, on all 16 triangles, under all three validation schemes and all three stopping rules, with the elbow sensitivity table and every figure and table the project has for them (including the submodel reserves).

- Number of submodels: every ensemble is fitted with K = 10, K = 20 and K = 25 (`tabm: k` in the config, 20 until now). This holds for the four TabM variants and for the deep ensemble `packed_tanh`, which is their benchmark and must have the same K. K is crossed with everything the ensembles go through in this project: the validation runs, the three stopping rules, the hyper-parameter search below, the comparison table, the run-time table and the bootstrap. The nagging predictor of the bCCNN stays at 20 networks.
- Treat each (ensemble, K) pair as a model of its own: its own validation curves, stops, selected setting, checkpoints and rows in every table. Add a table and a figure that show how the validation loss, reserve, bias, RMSEP, submodel spread and run time move with K for each ensemble.
- The tests check the parameter counts at K = 20 (3,250 for the TabM variants and 10,920 for the deep ensemble); extend them to the other K values.

# Hyper-parameter search for the bCCNN and the five ensembles

Search the following grid for the single bCCNN and for each of the five ensembles at each of K = 10, 20 and 25: 1 + 5 x 3 = 16 searches in all. The grid has 4 x 5 x 3 = 60 settings, and Paper C's setting is one of them.

| factor | values |
|---|---|
| hidden layers | (20, 15, 10); (25, 20, 15); (20, 20, 15, 10); (25, 20, 15, 10) |
| dropout after every hidden layer | 0%, 2%, 5%, 10%, 15% |
| optimiser | RMSprop (as now), Adam, Nadam, each at learning rate 0.001 with the other Keras defaults |

Everything else stays as in Paper C: the ccODP start, frozen embeddings, full batch, the `poisson` loss and the 2,000-step window. The activation is part of each model's configuration (tanh or ReLU), not of the grid.

- **Selection on the validation set only.** Under each of the three validation schemes, and for each model (for an ensemble, each K) and each triangle, the selected setting is the one with the lowest validation loss. That gives one winner per model, K, triangle and scheme. The true reserves and the lower triangle never enter the selection. Propose the exact criterion (which point of the validation curve, averaged over which seeds, smoothed how) and tell me how a winner chosen per triangle sits with the stopping rules, which share one stop across the lines of a portfolio.
- **Everything is reported.** One table with every one of the 60 settings for every model, K, triangle and scheme: validation loss, steps, reserve, bias and bias in percent, spread over seeds and training time, with Paper C's setting and the winner marked. Getting a reserve and a bias for a setting needs a refit on the full triangle, so say how that is done for all 60.
- **What is carried forward.** Paper C's setting and the selected setting both go through the rest of the pipeline: the three stopping rules, the refit, the nagging predictor for the bCCNN, the comparison table and the 1,000-replicate bootstrap. The other 58 settings appear only in the search table.
- **Cost.** The search alone is 60 settings x 16 searches x 16 triangles x 3 schemes x 5 seeds = 230,400 validation runs of 2,000 steps, of the order of 5,000 CPU-hours if the cost of a step grows in proportion to K (TabM reserving's README gives about 48 ms for a recorded step of a 20-submodel ensemble on a 12 x 12 triangle). Do not shrink the grid on your own. Measure the cost, show it to me, and propose the run order and every saving that does not change the results.
- **Points the plan must address.**
  - Selection noise: some validation sets are small (17 cells for the time-aware split on a 12 x 12 triangle), so a winner among 60 can be luck. Report for each winner how many settings lie within the spread over seeds of it.
  - Dispersion of a selected setting: Section 3.3.2 reduces the ccODP dispersion by the decrease of the validation loss. When the same validation set has also chosen the setting, that decrease is optimistic. Say how the dispersion of the selected setting is estimated and ask me.
  - No dropout: Paper C's argument in Section 3.3.2 refers to dropout as model averaging. Mark the 0% rows and say what changes for them.
  - Four hidden layers: check that the network functions, the tests on parameter counts and the layer names the tests look up all work for any number of hidden layers.

# Run times

Record the run time of every neural network variant and produce one table of them: model and variant, K for the ensembles, dataset and triangle, validation scheme, stopping rule and steps, trainable parameters, seconds per fit and per step, split into validation run, refit and bootstrap. Timings must be comparable: say how they will be measured (threads, nothing else running, curve recorder off), since TabM reserving's README notes that the recorder adds about 15 ms to a 33 ms step and that the chain runs six processes in parallel.

# The comparison table

One large table that sets every neural network against Mack and against the ccODP. One row per dataset, triangle, model variant, K for the ensembles, hyper-parameter setting (Paper C's and the selected one), validation scheme and stopping rule. Columns at least: true reserve, reserve, bias and bias in percent, steps, dispersion, process standard deviation, estimation standard deviation, RMSEP, coefficient of variation, in-sample and out-of-sample deviance, spread over seeds, run time, and the differences in absolute bias and in RMSEP to Mack and to the ccODP. Write it as one long tidy CSV and as wide tables ready for the thesis (propose the layout). Cells that do not exist, such as an RMSEP for the MackNet, are shown as missing, never as zero. The MackNet enters with all 68 variants per dataset, which makes this table very long, so propose how the wide thesis tables stay readable (for example one block per model family) without dropping any variant from the tidy CSV. Paper C makes no dependence assumption between LoBs, so say how portfolio totals are treated for the RMSEP before adding anything up.

# Bootstrap section

A separate section that runs Paper C's parametric bootstrap for the ccODP, the single bCCNN, the nagging bCCNN and the five ensembles at each K: resample the upper triangle from assumption (1) around the fitted means with the model's dispersion, refit from scratch exactly as the original was fitted (a fresh ccODP, then the network started in it and trained for the chosen steps), and combine the variance of the refitted reserves with the process variance phi times the reserve. Runs must be checkpointed and resumable and must report the Monte Carlo error of the RMSEP.

I chose 1,000 replicates for every model, K, triangle, scheme and rule, for Paper C's setting and for the selected setting, and I know this is heavy. One 1,000-step fit of a 20-submodel ensemble on a 12 x 12 triangle takes roughly half a minute (the 20 x 20 triangles have 210 observed cells instead of 78, so measure those). The ensembles alone have 5 ensembles x 3 values of K x 16 triangles x 3 schemes x 3 rules x 2 settings = 4,320 combinations, before the single and the nagging bCCNN, which puts the bootstrap of the order of 35,000 CPU-hours. Do not reduce the count on your own. Measure the real cost per fit, give me the projected CPU-hours and wall-clock time for the whole grid on my machine, and propose an order of runs that delivers the headline results first, the parallel layout, and every saving that does not change the results (for example, a refit at a given step count does not depend on the validation scheme).

# Things I already found that the plan must handle

- **Zero cells and empty halves.** The current SynthETIC upper triangle already has a zero cell, the new long-delay lines may have more, and the zeroed negative cells add to them. Validation cells whose accident or development year has no ccODP parameter in the training data cannot be predicted. Apply the merged project's rule for them under all three schemes and report how many cells each scheme loses per triangle.
- **Dispersion at the fixed 300 steps.** TabM reserving gave the 300-step stop no reduction (marked INFERRED in its bootstrap script), while Paper C reduces by the validation decrease at its 300 steps (Table 3). Tell me which the code will do.
- **Scheme settings do not transfer between triangle sizes.** The rolling-origin settings (test periods 5 and 2, validation 2, exclude 2) were scaled for 20 x 20 and the hold-out of 2 years for 12 x 12. Propose settings for the other size and show the cell counts of every partition.
- **MackNet on SynthETIC.** The five covariates are all categorical and have 2 x 6 x 5 x 4 x 2 = 480 level combinations per line, so there are far fewer cells than on the machine data and a batch of 10,000 may be a large part of the sample. Keep the hyper-parameters, report the number of learning cells per development period, and flag where the setting stops meaning what it meant in the paper.
- **The whole experiment is large.** The search, the bootstrap and the MackNet runs together are of the order of 40,000 CPU-hours by my rough arithmetic, most of it the bootstrap of the ensembles at three values of K. I want the full design planned, but the plan must state the total, say what my machine can do in a week, and order the work so that a complete set of results for Paper C's setting exists early.

# What the plan must contain

1. The new scripts and functions, where they go in the folder tree, and which existing functions they extend.
2. The `config.yml` additions.
3. The experiment grid (dataset x triangle x model x K x setting x scheme x rule x seed) with the number of fits, the measured or estimated time of each block, and the run order.
4. The new tables and figures, with their file names and the script that writes each.
5. The tests for everything new, and how the regression check of the merge is kept passing.
6. The work in stages I can approve one at a time, each with its own check. The six-line SynthETIC data comes first, because everything else depends on it.
7. Your open questions and every assumption you made, separated from what you read in the code or the papers.

# Ask me before finalising the plan

Where a paper and my code disagree, show me both and ask; do not pick one silently. I expect questions at least on: the parameter values of the six SynthETIC lines; the three points about the zeroed negative cells; the embedding dimensions and scaling statistics of the MackNet pre-processing variants; the selection criterion of the hyper-parameter search and the dispersion of a selected setting; whether stops are shared across the LoBs of a portfolio (pooled curve, as now) or taken per triangle, given that the six SynthETIC lines are built to develop differently and that the search selects per triangle; whether I also want refits at every elbow tolerance or only the table of stops; and the run order of the search and of the bootstrap.

These are a minimum. Ask about anything else in this prompt that is unclear, underspecified or that you would do differently, and tell me where my wording should change. Before implementing each stage, put any questions that stage raises to me first.
