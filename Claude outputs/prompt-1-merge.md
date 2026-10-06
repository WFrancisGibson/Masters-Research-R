You are in plan mode. Do not create, move, edit or run anything yet. Read what is listed below, ask me questions so that we can clarify this prompt further, and then give me a plan I can approve. Ask again once the plan is approved and before you implement any of it: nothing is to be implemented on an assumption you have not put to me. Accuracy matters more than speed here: take your time, and read the code and the two papers themselves instead of working from memory of them.

# What I want

I am writing a masters thesis on claims reserving with neural networks. The code sits in two R projects that grew separately and now overlap:

- `C:\Users\frang\Projects\Masters-Research-R`: claim simulation, Mack chain ladder, ODP GLM (ccODP), the bCCNN, and the neural-network chain ladder of Wuthrich (2018), which I call the **MackNet** (code prefix `nncl_`).
- `C:\Users\frang\Projects\TabM reserving`: the bCCNN again, plus the main new model of my research, the **TabMbCCNN** (the bCCNN fitted as a TabM weight-sharing ensemble), with its stopping rules and bootstrap.

This is the first of two jobs. This job only merges: plan one new project that replaces both, with one code base, nothing duplicated, nothing lost, and the same results as today. A second job, with its own prompt, will add new datasets, models and experiments to the merged project. Do not plan or build any of that now; the section "What comes next" only tells you what the design must leave room for.

Put the new project in a new sibling folder, `C:\Users\frang\Projects\Thesis-Reserving-Models`, with its own git repository. The two existing projects stay untouched as archives: copy from them, never edit them, and never overwrite their outputs, which are the reference for the regression check.

# Read first

1. Both projects in full: `README.md`, `config.yml`, `analysis/00_setup.R`, every file in `R/`, every script in `analysis/`, `tests/`, and the file names in `output/tables`, `output/figures` and `data/processed` (they are the inventory of what must survive). `analysis/00_claim-simulation/Simulation.Machine.V1/` is the authors' simulation machine, third-party code that is only sourced.
2. Wuthrich (2018), *Neural networks applied to chain-ladder reserving*, EAJ 8:407-436: Sections 2 to 5 and Listings 1 and 2.
3. Gabrielli (2020), *Claims reserving and neural networks*, PhD thesis ETH Zurich: Chapter 4 and Paper C (Gabrielli, Richman & Wuthrich 2020, *Neural network embedding of the over-dispersed Poisson reserving model*): Section 2 with eqs. (1) to (6) (Section 2.3 holds the dispersion estimate (5), the RMSEP (6) and the parametric bootstrap), Sections 3.2 to 3.3.4 with eqs. (13) to (16), Tables 2 to 5, and Listings 1 to 4.

Both PDFs are in `papers/` of the new folder. If they are not there, ask me for them. You need the papers to decide which of two implementations is the right one where they differ. Whenever the plan relies on a paper, cite the section, equation, table or listing.

# Scope of this job

Every strand of both projects moves into the new project and runs on the data it runs on today, with the settings it has today:

| strand | from | data it runs on today |
|---|---|---|
| Claim simulation | Masters-Research-R | SynthETIC, one portfolio, annual 20 x 20 (seed 2026, 399,568 claims; a quarterly 40 x 40 option exists) and the simulation machine portfolio of Wuthrich (2018) Listing 1 (V = 5,000,000, seed1 = 100, four LoBs, 5,003,204 claims) |
| Mack chain ladder | Masters-Research-R | SynthETIC annual |
| ODP GLM / ccODP, with its seven RMSEP methods and 1,000 bootstrap samples | Masters-Research-R | SynthETIC annual |
| bCCNN, early stopping by rolling origin or by the 50/50 claims split over 1,000 steps, bootstrap with 1,000 refits | Masters-Research-R | SynthETIC annual |
| MackNet, seven runs (q = 5, 10, 20 and S1 to S4), zero claims features, data description | Masters-Research-R | machine, four LoBs, 12 x 12 |
| ccODP, single bCCNN and the five ensembles, time-aware split (6,000 steps) and claim-level split (2,000 steps), three stopping rules, 5 seeds, k = 20, bootstrap with 25 replicates at the elbow stop | TabM reserving | machine, six LoBs of Paper C Listing 1 (seed 75, 1,198,888 claims, 12 x 12) |

Also in scope:

- A script that regenerates the six-LoB portfolio. Neither project has one: TabM reserving holds only `data/raw/simulated_claims.csv` and `simulation_manifest.json` (seed 75, std1 = std2 = 0.85, V 1,000,000 and 200,000, sample.kind "Rounding"). Write it from Paper C Listing 1 with the machine already in Masters-Research-R, and check it against the existing file.
- One Keras backend for the whole project (see "Things I already found").

# Rules for the merge

- **Nothing lost, nothing twice.** Every table and figure either project produces now is still produced, and every job is done by one function. Where the two projects do the same job in two ways (the section "Duplication I know about" lists the cases I have found), the plan keeps one implementation and says which and why.
- **Settings do not change.** Every hyper-parameter, seed, step count and replicate count keeps its current value and moves into the one `config.yml`. Give me the map from each old key to its new key.
- **Differences in behaviour are my decision.** Where two implementations differ in what they compute, not only in how they are written, show me both and ask which one survives. Cases I know of: the GLM tolerance (1e-12 against 1e-14) and the way the coefficients are read; weights set after the build against constant initialisers; the sort key of the 50/50 claims split (accident period and claim number, against LoB and accident year); the minimum of the raw validation curve against the smoothed minimum and the elbow; the order in which the bootstrap draws its random numbers; the units (millions on SynthETIC, thousands on the machine data).
- **Mack and ccODP are two separate models.** Each is fitted on its own. Paper C states that the two give the same reserves, but I do not want the code to rely on that: no table may fill a "chain ladder" column from the ccODP fit or the other way round, and no script may stop when they differ. `bCCNN fit.R` and `01_data and ccODP/data and ccODP.R` call `stopifnot()` on that equality today: turn it into a reported check. On the current data the two agree, so this changes no result.
- **Mark what is inferred.** Comments cite the paper section or equation, and anything the papers do not state is marked INFERRED, as TabM reserving does now.

# What comes next (design for it, do not build it)

The second job will ask for the following, so the functions and the config of the merged project must not assume the opposite:

- Three datasets of several lines of business each (the two machine portfolios and a new six-line SynthETIC dataset), with 12 x 12 and 20 x 20 triangles, and every model fitted on every triangle.
- Three validation schemes (rolling origin, time-aware hold-out, claim-level split) and the three stopping rules available to every network on every triangle.
- A search over the number and width of the hidden layers, the dropout rate and the optimiser for the bCCNN and the ensembles, so none of these may be hard-coded (the single `bccnn_model()` writes out three hidden layers today).
- The ensembles with K = 10, 20 and 25 submodels side by side, so K must be a dimension of the checkpoints, tables and tests and not a single project-wide value (`tabm: k: 20` today).
- MackNet variants: deeper networks, other feature pre-processing (entity embeddings, one-hot encoding), several seeds.
- A nagging predictor for the bCCNN, a stored run time for every fit, one tidy results table across all models, and the parametric bootstrap for any model with any number of replicates.

# Conventions to keep

The layout and style of Masters-Research-R: numbered folders under `analysis/`, short scripts that run top to bottom, functions only in `R/`, one `analysis/00_setup.R`, one `config.yml` read with `config::get()` holding every setting, a `quick` profile that runs the whole chain in minutes, renv, `here`, testthat, and lintr defaults with `%>%` as the only pipe. Keep TabM reserving's checkpointing and its `run_all.ps1` chain, extended to the whole project.

# Duplication I know about

Resolve each of these to one implementation, and look for more:

- `ccodp_fit()` exists in both `R/fit ODP GLM.R` files with different inputs (matrix with NA and a `cells` argument, against a triangle object with a mask), different GLM tolerances and different ways of reading the coefficients.
- `poisson_deviance()` exists in both `R/loss functions.R` files.
- `bccnn_model()` exists in both `R/nn_models.R` files (weights set after the build, against constant initialisers, which TabM reserving's README explains is the safer one for reproducible seeds); `bccnn_fit()` and `nn_fit()` both train it and record curves.
- Two triangle representations: `claims_triangle()`, `triangle_sets()`, `upper_triangle()`, `lower_triangle()` (1-based, NA below the diagonal) against `triangle()`, `runoff_mask()`, `train_cells()`, `aggregate_claims()`, `lob_triangles()` (0-based, mask).
- The 50/50 claims split is coded twice (inside `triangle_sets()` and as `split_claims()`), with different sort keys.
- Two time-based validation splits, `rolling_origin()` with `rolling_origin_fit()` and `time_aware_split()`. Both stay, as two schemes behind one interface.
- Early stopping: `which.min()` on the raw validation curve in Masters-Research-R against the rules in `R/early stopping.R`.
- Bootstrap: `odp_sample()`, `ccodp_bootstrap()`, `bccnn_bootstrap()`, `rmsep_table()` against `sample_triangle()`, `bootstrap_ccodp()`, `bootstrap_nn()`, `bootstrap_result()`, `reduced_phi()`.
- `bias_plot()` is defined in both `R/plots.R` files with different arguments, so sourcing both would silently overwrite one. `loss_plot()` and `curves_plot()` draw the same kind of figure.
- Mack is fitted in `01_Mack model/Mack chainladder fit.R` and again in `nncl_mack()`; chain-ladder reserves are computed in `cl_reserves()` and by `chainladder()` calls in several scripts.
- Two `00_setup.R` files and two `config.yml` files with different key layouts and seed conventions.

# Things I already found that the plan must handle

- **Two Keras backends.** TabM reserving runs keras3 1.5.1 on torch (venv `C:/Users/frang/.venvs/dlfa`, TensorFlow not installed), and its custom layers and tests were validated there. Masters-Research-R is documented as running on TensorFlow. Propose the one backend, and list which existing numbers will then no longer reproduce exactly.
- **Outputs without a script.** `Masters-Research-R/output/figures/GLM reserves triangle.png` is produced by no current script. TabM reserving's README lists an assembled bootstrap table `tabm_time_aware_bootstrap_<rule>.csv`, but it is not in `output/tables`, although the per-LoB results are in `data/processed/tabm_time_aware_bootstrap/`. Look for more and tell me what to do with each.
- **Validation cells without parameters.** `bCCNN fit.R` drops validation cells whose accident or development year has no payments in the training half, and `time_aware_split()` excludes cells with no ccODP parameter in the training triangle. Bring these under one rule without changing either result.
- **Seeds.** `set_random_seed()` also reseeds R's generator (TabM reserving's README), and the two projects handle this differently around their bootstraps. Say how the merged code keeps each current result reproducible.

# The regression check

The merge is finished when the new project reproduces the results of both old projects. Plan this check first and run it before anything else is called done.

- TabM reserving: `table2_ccodp.csv`, the two `*_selection.json` files, `*_curves.csv`, `*_elbow_sensitivity.csv`, `*_table.csv`, the four `tabm_summary_*.csv` files, `*_submodel_reserves.csv` and the bootstrap results.
- Masters-Research-R: `mack_raw_*`, `odp_*`, `bccnn_annual_*` and `nncl_*` in `output/tables`, and the `summary.csv` of each simulated dataset.

For every output say whether it will match exactly, within a stated tolerance, or not at all, and why (a changed backend, a changed order of random draws, a merged function). Some of these runs are long: the machine simulation takes about 7 minutes and 20 GB, the MackNet fits about 75 minutes, the 1,000 bCCNN refits about 3.5 hours, and the TabM chain runs 6,000 steps for six configurations, six LoBs and five seeds. Propose which checks are rerun in full, which on a subset or the `quick` profile, and in what order.

# What the plan must contain

1. The folder tree of the new project and the run order of its scripts.
2. A function map: every function of both projects, what happens to it (kept, merged into which function, dropped) and why.
3. An output map: every table and figure either project produces now, and the script and function that will produce it in the new project.
4. The `config.yml` layout, with the map from the old keys.
5. The regression check, as described above.
6. The tests carried over from both projects and the new ones.
7. The work in stages I can approve one at a time, each with its own check.
8. Your open questions and every assumption you made, separated from what you read in the code or the papers.

# Ask me before finalising the plan

Where a paper and my code disagree, or my two projects disagree with each other, show me both and ask; do not pick one silently. I expect questions at least on: the backend; each difference in behaviour listed under "Rules for the merge"; whether the `final_fit: partition` option of the rolling origin survives; and the outputs that no script produces.

These are a minimum. Ask about anything else in this prompt that is unclear, underspecified or that you would do differently, and tell me where my wording should change. Before implementing each stage, put any questions that stage raises to me first.
