---
title: "How the literature and the textbooks set a neural network's hyperparameters"
subtitle: "Every selection method, selection signal and value found in the 78 documents of the *Mistakes in each paper* folder and its shipped code, set against Wüthrich–Merz (2023), *AI Tools for Actuaries* (2026), Goodfellow–Bengio–Courville (2016) and Hindley (2017)"
author: "Claude (for Francis Gibson)"
date: "2026-09-24"
output:
  html_document:
    toc: true
    toc_depth: 3
    number_sections: true
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = TRUE, eval = FALSE)
```

# Scope, sources and conventions

**Question answered.** For every neural network fitted in the documents of your *Mistakes in each paper* folder, how was each hyperparameter arrived at? And what do the textbooks in the project say about how it *should* be arrived at? The answer is organised as a catalogue of **methods** (Section 3), a catalogue of **selection signals**, i.e. what score on what data drove the choice (Section 4), a per-hyperparameter reference card (Section 5), a textbook-by-textbook account (Section 6), the shipped code (Section 7), the recurring referee flags (Section 8) and R/keras3 skeletons for each method (Section 9). Appendix A has the paper-by-paper extraction tables that everything else rests on.

**Hyperparameters in scope** (your choice):

* **Architecture:** depth, width, activation, embedding dimension, skip/CANN/residual connection, recurrent cell and units, attention heads, kernel sizes.
* **Optimisation:** optimiser, learning rate and its schedule, batch size, number of epochs / gradient steps / early-stopping patience, weight initialisation, random seed.
* **Regularisation and ensembles:** dropout, L1/L2/ridge penalty, weight decay, batch/layer normalisation, noise, number of ensemble members (nagging, bagging, snapshot averaging).

**Out of scope** (your choice): distribution and loss parameters, e.g. the Tweedie power $p$, dispersion $\phi$, the number of mixture components $K$ and loss weights in multi-task fits. They are mentioned in one line only where they were tuned inside the same loop as an in-scope hyperparameter (Al-Mudafer et al. 2021 is the main case).

**Evidence base.** The PDFs in the folder and the code bases shipped with it. Your own `NOTE_` critique files were deliberately **not** used, so every flag in this document was found independently in the primary text.

| Corpus | Count | Treatment |
|---|---|---|
| Documents in the folder (duplicates of Avanzi et al. 2025 and Gabrielli PhD 2020 counted once) | 78 | all read |
| … that fit at least one neural network | 50 | full extraction (48 papers/theses/reports + 2 books: Graziani & Xibilia 2021, Gridin 2021) |
| … that fit no network but were read for any selection method they describe or use | 12 | extraction of the method, where there is one (Balona & Richman 2020, Avanzi et al. 2024, Jin 2021, Tavares 2023, Mayr 2025, Mienye et al. 2024, Richman 2024, Yeo et al. 2019, Baeder et al. 2021, Mukesh & Aitha 2021, Zhai 2024; Nirmala 2026 survives only as a bibliography) |
| … screened out at inventory | 16 | no network and no selection method: zero hits for "epoch", "hidden layer", "keras", "tensorflow" or "pytorch" in each |
| Shipped code bases | 6 | 4 contain a network (Manai 2026, Zelený 2026, Richman et al. 2025 PIN example, the Gabrielli 2019 NNDODP notebook); 2 do not (Utulu 2026, Van Oirbeek 2026 `hgr`) |

**Paper citations** give the **PDF page of the file in your folder** ("PDF p. 12"), because many of the files are preprints without printed journal page numbers. Where a paper exists in several versions, the version in your folder is the one used and it is named in Appendix A (for example, Gabrielli, Richman & Wüthrich is the SSRN version of 21 November 2018; Gabrielli 2019 is the SSRN version of 4 April 2019; Wüthrich 2017 is the version of 10 May 2017). Gridin (2021) is an EPUB and is cited by chapter and section.

**Textbooks and page conventions.** Every textbook citation gives the **printed** page (the number on the page itself). The PDF offsets in the last column are carried over from the 17 September explainers so that you can jump to the page; they were not re-derived in this session.

| Tag | Book (file in the project) | Role here | Printed → PDF |
|---|---|---|---|
| [WM] | Wüthrich & Merz, *Statistical Foundations of Actuarial Learning and its Applications* (Springer Actuarial, 2023) | actuarial networks: U/V/T early stopping, nagging, minimal-complexity argument, AIC not valid for networks | PDF = printed + 10 |
| [AIT] | Wüthrich, Richman, Avanzi, Lindholm, Maggi, Mayer, Schelldorfer & Scognamiglio, *AI Tools for Actuaries* (version 20 January 2026) | the six-step FNN recipe, default ranges, test-sample use, Optuna (GBM chapter) | PDF = printed |
| [GBC] | Goodfellow, Bengio & Courville, *Deep Learning* (MIT Press, 2016) | the machine-learning playbook: validation machinery, manual/grid/random/Bayesian search, early-stopping algorithms 7.1–7.3 | PDF = printed + 15 |
| [H] | Hindley, *Claims Reserving in General Insurance* (CUP, 2017; imprint 2018) | no neural networks at all; the reserving analogues (judgement parameters, removed-diagonal test, back-testing, A vs E) | PDF = printed + 13 |
| [ISL] | James, Witten, Hastie & Tibshirani, *An Introduction to Statistical Learning* (1st ed.) | **pending**: the PDF is not in the project and could not be downloaded here (Section 6.5) | – |

**Labels.** Methods are labelled `HP-M01` … `HP-M27`, selection signals `HP-V1` … `HP-V9` (plus `HP-VX`, not stated), referee flags `HP-F01` … and textbook rows `TB-WM-n`, `TB-AIT-n`, `TB-GBC-n`, `TB-H-n`, so that they can be cited in later sessions in the same way as your `CY-`, `WM-` and `G-` labels. Appendix A uses the extraction codes `S1`–`S27` and `V1`–`V9`; Table 2.1 maps them to the `HP-M` labels.

**Verification.** Every quotation that carries a page reference was inserted by a build script from the extraction index and checked there: paper quotes as whitespace-normalised exact substrings of the PDF text, on the PDF page stated; textbook quotes against the printed-page markers of the book text, on the printed page stated. The short phrases quoted in Table 2.2 and in the reference card of Section 5 were checked the same way against the page given. The count of checks and the result are in Appendix B. Numbers read from table or figure *images* (not text) are marked "from the table image" in Appendix A. Nothing was re-run numerically: this document reports what the papers did, not new experiments.

# The map: every method, how often it was used, and by whom

Table 2.1 lists the 27 ways a hyperparameter value was arrived at, grouped into six families. The count is the number of the **50 network-fitting documents** in which the method determines at least one in-scope hyperparameter. A document usually uses several methods (for example, a fixed architecture, a library-default optimiser and early-stopped epochs), so the counts do not add up to 50.

For the three "ubiquitous" methods (`HP-M01`, `HP-M02`, `HP-M03`) and for `HP-M27` the list is taken mechanically from the extraction tables in Appendix A (every document with at least one row coded `S1`, `S2`, `S3` or `S19`). For the other methods the list was compiled by reading the evidence for each document, because the extraction passes coded some borderline cases differently (for instance, initialisation at a classical model was coded `S20` in one pass and `S2` in another).

**Table 2.1 – Methods, extraction codes and users.** Families: I = no search, the value is set before any comparison; II = an explicit search over configurations; III = set during training; IV = average over runs instead of choosing one (or choose the best run); V = a structural device that pins or removes a hyperparameter; VI = assessment or reporting after the fact.

| Label | Method | Family | Code in App. A | n (of 50) | Network documents that use it |
|---|---|---|---|---|---|
| `HP-M01` | Value set by fiat (no reason given) | I. No search | S1 | 46 | Al-Mudafer et al. 2021; Andersen–Roed-Sørensen MSc 2021; Avanzi et al. 2025; Avanzi et al. 2026; Belabed et al. 2025; Bücher–Rosenstock 2022; Cai MSc 2021; Cai et al. 2025; Cai PhD 2025; Côté et al. 2025; Dong et al. 2020; Fang et al. 2022; Ferrario et al. 2020; Gabrielli et al. 2018; Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Graziani–Xibilia (eds.) 2021; Gridin 2021; Guo 2026; Härkönen MSc 2021; Hiabu et al. 2025; Kuo 2020 BMDN; Kuo 2020 generative; Richman–Wüthrich 2021 LocalGLMnet; Lindholm et al. 2020; Nicholas MSc 2026; Noordhoek MSc 2025; Qiu MSc 2019; Ramos-Pérez et al. 2020; Ramos-Pérez et al. 2022; Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Rügamer et al. 2023; Spedicato–Richman 2025; Schneider–Schwab 2025; Schwab PhD 2025; Swallow MSc 2023; Yeldan–Karabey 2026; Gorishniy et al. 2025 TabM; Usman PhD 2024; Wüthrich 2017; Xu et al. 2019 CTGAN; Yu–Tomasi 2019; Ye et al. 2025; Zelený MSc 2026 |
| `HP-M02` | Inherited from a prior paper, companion paper or textbook | I. No search | S2 | 43 | Al-Mudafer et al. 2021; Andersen–Roed-Sørensen MSc 2021; Avanzi et al. 2025; Bücher–Rosenstock 2022; Cai MSc 2021; Cai et al. 2025; Cai PhD 2025; Côté et al. 2025; Dong et al. 2020; Fang et al. 2022; Ferrario et al. 2020; Gabrielli et al. 2018; Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Graziani–Xibilia (eds.) 2021; Gridin 2021; Gueye et al. 2023; Guo 2026; Härkönen MSc 2021; Kuo 2020 BMDN; Kuo 2020 generative; Richman–Wüthrich 2021 LocalGLMnet; Lindholm et al. 2020; Nicholas MSc 2026; Noordhoek MSc 2025; Pittarello et al. 2022; Qiu MSc 2019; Ramos-Pérez et al. 2020; Ramos-Pérez et al. 2022; Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Rügamer et al. 2023; Spedicato–Richman 2025; Schneider–Schwab 2025; Schwab PhD 2025; Swallow MSc 2023; Gorishniy et al. 2025 TabM; Usman PhD 2024; Wüthrich 2017; Xu et al. 2019 CTGAN; Yu–Tomasi 2019; Ye et al. 2025 |
| `HP-M03` | Library default (stated, or visible only in code) | I. No search | S3 | 28 | Andersen–Roed-Sørensen MSc 2021; Cai MSc 2021; Cai et al. 2025; Côté et al. 2025; Ferrario et al. 2020; Gabrielli et al. 2018; Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Graziani–Xibilia (eds.) 2021; Gridin 2021; Gueye et al. 2023; Guo 2026; Härkönen MSc 2021; Kuo 2020 generative; Richman–Wüthrich 2021 LocalGLMnet; Lindholm et al. 2020; Mulquiney 2006; Qiu MSc 2019; Ramos-Pérez et al. 2020; Ramos-Pérez et al. 2022; Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Rügamer et al. 2023; Schneider–Schwab 2025; Usman PhD 2024; Ye et al. 2025; Zelený MSc 2026 |
| `HP-M04` | Reasoned a-priori argument (no experiment) | I. No search | S21 (new) | 12 | Wüthrich 2017; Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Härkönen MSc 2021; Avanzi et al. 2026; Cai et al. 2025; Cai PhD 2025; Zelený MSc 2026; Guo 2026; Bücher–Rosenstock 2022; Ferrario et al. 2020 |
| `HP-M05` | Rule of thumb / heuristic formula | I. No search | S5 | 12 | Gabrielli 2019; Gabrielli 2020; Ferrario et al. 2020; Cai et al. 2025; Cai PhD 2025; Spedicato–Richman 2025; Guo 2026; Usman PhD 2024; Cai MSc 2021; Gorishniy et al. 2025 TabM; Avanzi et al. 2026; Rügamer et al. 2023 |
| `HP-M06` | Manual tuning, trial and error, "preliminary experiments" | I. No search | S4 | 16 | Gabrielli et al. 2018; Gabrielli PhD 2020; Al-Mudafer et al. 2021; Avanzi et al. 2025; Andersen–Roed-Sørensen MSc 2021; Kuo 2020 BMDN; Ferrario et al. 2020; Swallow MSc 2023; Usman PhD 2024; Pittarello et al. 2022; Côté et al. 2025; Fang et al. 2022; Zelený MSc 2026; Graziani–Xibilia (eds.) 2021; Yu–Tomasi 2019; Bücher–Rosenstock 2022 |
| `HP-M07` | Grid search | II. Explicit search | S6 | 15 | Wüthrich 2017; Gabrielli 2019; Gabrielli PhD 2020; Ramos-Pérez et al. 2020; Yeldan–Karabey 2026; Avanzi et al. 2025; Al-Mudafer et al. 2021; Nicholas MSc 2026; Schwab PhD 2025; Usman PhD 2024; Pittarello et al. 2022; Cai et al. 2025; Cai PhD 2025; Hiabu et al. 2025; Graziani–Xibilia (eds.) 2021<br>*Also (no network, or described only):* Balona–Richman 2020; Jin MSc 2021; Lindholm et al. 2020 (GBMs) |
| `HP-M08` | Random search | II. Explicit search | S7 | 4 | Schneider–Schwab 2025; Schwab PhD 2025; Guo 2026; Côté et al. 2025<br>*Also (no network, or described only):* Gridin 2021 (described) |
| `HP-M09` | Bayesian / model-based optimisation (GP, TPE, Optuna) | II. Explicit search | S8 | 7 | Hiabu et al. 2025; Schneider–Schwab 2025; Schwab PhD 2025; Usman PhD 2024; Gorishniy et al. 2025 TabM; Ye et al. 2025; Spedicato–Richman 2025<br>*Also (no network, or described only):* Tavares MSc 2023 (trees only); Gridin 2021 (described) |
| `HP-M10` | Sequential / one-at-a-time / staged search | II. Explicit search | S9 | 7 | Al-Mudafer et al. 2021; Gabrielli 2019; Gabrielli PhD 2020; Ferrario et al. 2020; Usman PhD 2024; Schneider–Schwab 2025; Schwab PhD 2025<br>*Also (no network, or described only):* Balona–Richman 2020 (proposed two-step); Lindholm et al. 2020 (GBMs) |
| `HP-M11` | Multi-fidelity or staged screening (cheap runs first) | II. Explicit search | S10 | 3 | Guo 2026; Côté et al. 2025; Hiabu et al. 2025<br>*Also (no network, or described only):* Ye et al. 2025 (proposed learning-curve pruning) |
| `HP-M12` | Evolutionary / population-based search | II. Explicit search | S11 | 1 | Gridin 2021<br>*Also (no network, or described only):* Avanzi et al. 2026 (mentioned as an option) |
| `HP-M13` | Early stopping (number of epochs/steps chosen on a validation signal) | III. Set during training | S12 | 30 | Gabrielli et al. 2018; Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Richman–Wüthrich 2021 LocalGLMnet; Al-Mudafer et al. 2021; Avanzi et al. 2025; Avanzi et al. 2026; Hiabu et al. 2025; Cai et al. 2025; Cai MSc 2021; Cai PhD 2025; Nicholas MSc 2026; Kuo 2020 BMDN; Schneider–Schwab 2025; Schwab PhD 2025; Härkönen MSc 2021; Zelený MSc 2026; Guo 2026; Lindholm et al. 2020; Ferrario et al. 2020; Spedicato–Richman 2025; Rügamer et al. 2023; Gorishniy et al. 2025 TabM; Ye et al. 2025; Usman PhD 2024; Andersen–Roed-Sørensen MSc 2021; Gridin 2021 |
| `HP-M14` | Learning-rate adaptation during training (plateau, step, cosine, range test) | III. Set during training | S13 | 11 | Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Kuo 2020 BMDN; Côté et al. 2025; Schneider–Schwab 2025; Yu–Tomasi 2019; Dong et al. 2020; Gridin 2021; Graziani–Xibilia (eds.) 2021; Andersen–Roed-Sørensen MSc 2021; Qiu MSc 2019 |
| `HP-M15` | Constructive growth / architecture search | III. Set during training | S16 | 3 | Dong et al. 2020; Gridin 2021; Fang et al. 2022<br>*Also (no network, or described only):* Mienye et al. 2024 (NAS mentioned) |
| `HP-M16` | Ensembling over seeds or resamples (nagging, bagging, deep ensembles) | IV. Average instead of choose | S15 | 14 | Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Kuo 2020 BMDN; Yeldan–Karabey 2026; Al-Mudafer et al. 2021; Ramos-Pérez et al. 2022; Zelený MSc 2026; Härkönen MSc 2021; Cai MSc 2021; Guo 2026; Gorishniy et al. 2025 TabM; Ferrario et al. 2020; Schneider–Schwab 2025; Ye et al. 2025 |
| `HP-M17` | Snapshot / epoch averaging | IV. Average instead of choose | S15 (variant) | 3 | Gabrielli 2019; Gabrielli PhD 2020; Gabrielli 2020 |
| `HP-M18` | Bayesian treatment of weights or hyperparameters | IV. Average instead of choose | S14 | 3 | Kuo 2020 BMDN; Pittarello et al. 2022; Andersen–Roed-Sørensen MSc 2021<br>*Also (no network, or described only):* Wüthrich 2017 (proposed) |
| `HP-M19` | Best-of-N seeds or restarts (select, not average) | IV. Average instead of choose | S23 (new) | 3 | Rügamer et al. 2023; Usman PhD 2024; Côté et al. 2025 |
| `HP-M20` | Initialisation at a fitted classical model (skip / CANN start) | V. Structural device | S20 (new) | 8 | Gabrielli et al. 2018; Gabrielli 2019; Gabrielli PhD 2020; Gabrielli 2020; Härkönen MSc 2021; Noordhoek MSc 2025; Al-Mudafer et al. 2021; Bücher–Rosenstock 2022 |
| `HP-M21` | Warm start, fine-tuning and transfer of tuned values | V. Structural device | S22, S24 (new) | 6 | Cai et al. 2025; Cai PhD 2025; Côté et al. 2025; Gorishniy et al. 2025 TabM; Al-Mudafer et al. 2021; Avanzi et al. 2025 |
| `HP-M22` | Empirical-null (random control variable) input selection | V. Structural device | S25 (new) | 1 | Richman–Wüthrich 2021 LocalGLMnet |
| `HP-M23` | Information criteria / regularisation path | V. Structural device | S17 | 1 | Rügamer et al. 2023<br>*Also (no network, or described only):* Cai PhD 2025 (non-network model) |
| `HP-M24` | Sensitivity analysis or ablation after the fact | VI. Assessment / reporting | S18 | 16 | Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Ramos-Pérez et al. 2020; Ramos-Pérez et al. 2022; Xu et al. 2019 CTGAN; Ferrario et al. 2020; Härkönen MSc 2021; Guo 2026; Yu–Tomasi 2019; Nicholas MSc 2026; Gorishniy et al. 2025 TabM; Ye et al. 2025; Rügamer et al. 2023; Graziani–Xibilia (eds.) 2021; Andersen–Roed-Sørensen MSc 2021 |
| `HP-M25` | Post-hoc importance / pattern analysis of the search results | VI. Assessment / reporting | S27 (new), S18 | 2 | Guo 2026; Gridin 2021 |
| `HP-M26` | Visual reading of loss curves | VI. Assessment / reporting | S26 (new) | 5 | Gabrielli et al. 2018; Gabrielli 2020; Côté et al. 2025; Graziani–Xibilia (eds.) 2021; Ferrario et al. 2020 |
| `HP-M27` | Not stated | VI. Assessment / reporting | S19 | 44 | Al-Mudafer et al. 2021; Avanzi et al. 2025; Avanzi et al. 2026; Belabed et al. 2025; Bücher–Rosenstock 2022; Cai MSc 2021; Cai et al. 2025; Cai PhD 2025; Côté et al. 2025; Fang et al. 2022; Ferrario et al. 2020; Gabrielli et al. 2018; Gabrielli 2019; Gabrielli 2020; Gabrielli PhD 2020; Graziani–Xibilia (eds.) 2021; Gueye et al. 2023; Guo 2026; Härkönen MSc 2021; Hiabu et al. 2025; Kuo 2020 BMDN; Kuo 2020 generative; Richman–Wüthrich 2021 LocalGLMnet; Lindholm et al. 2020; Mahohoho et al. 2023; Mulquiney 2006; Nicholas MSc 2026; Noordhoek MSc 2025; Pittarello et al. 2022; Qiu MSc 2019; Ramos-Pérez et al. 2020; Ramos-Pérez et al. 2022; Richman–Wüthrich 2026a; Richman–Wüthrich 2026b; Spedicato–Richman 2025; Schneider–Schwab 2025; Schwab PhD 2025; Swallow MSc 2023; Yeldan–Karabey 2026; Usman PhD 2024; Wüthrich 2017; Xu et al. 2019 CTGAN; Yu–Tomasi 2019; Zelený MSc 2026 |

**Table 2.2 – Where each textbook stands on each method** (printed pages; the quotations are in Sections 3 and 6). "–" means the book does not discuss the method.

| Label | [WM] Wüthrich–Merz | [AIT] AI Tools for Actuaries | [GBC] Goodfellow–Bengio–Courville | [H] Hindley |
|---|---|---|---|---|
| `HP-M01`–`M03` fiat, inherited, default | uses one standard architecture, (20, 15, 10) tanh, throughout (p. 295); keras optimisers come with "pre-defined" rates (p. 287) | same standard architecture (p. 106); optimiser software comes "ready-to-use" (p. 100) | copy the best-known model for a similar task (p. 426); Adam's suggested defaults (p. 311); manual tuning works when "others having worked on the same type of application" give a starting point (p. 432) | practitioners have "their preferences" (p. 2); parameters set by judgement throughout |
| `HP-M04` reasoned argument | prefers tanh for anti-symmetry and boundedness (p. 270); stay above a "minimal complexity" rather than shrink the network (p. 293) | "always work with deep FNNs" (p. 95) | ReLU is "an excellent default" (p. 191); little specific architecture advice possible (p. 202) | – |
| `HP-M05` rules of thumb | $K=10$ folds (p. 101); embedding $b$ 50–300 for words (p. 433); 20 networks suffice for nagging (p. 493) | depth 3–6, 15–30 neurons (p. 106); batch 2,000–5,000 (p. 105); validation 10–20 % (pp. 103, 105); $M=10$ or 20 (p. 109) | 80/20 train/validation (p. 121); batch 32–256 (p. 279); inclusion probabilities 0.8/0.5 (p. 259); 5–10 ensemble members (p. 258); final learning rate ≈ 1 % of initial (p. 295); momentum .5/.9/.99 (p. 298) | CSA / CSA-recent estimators (p. 47); GCC decay 0.75 in the worked example (p. 132) |
| `HP-M06` manual tuning | λ path "rather brute force" (p. 224) | activation choice is "part of hyper-parameter tuning" (p. 92) | §11.4.1 manual search (pp. 427–431): "If you have time to tune only one hyperparameter, tune the learning rate" (p. 429); Table 11.1 (p. 431) | judgement, graphs and diagnostics for every parameter; anchoring bias (p. 326) |
| `HP-M07` grid search | λ by cross-validation (pp. 211, 216) | GBM chapter: grid search with (cross-)validation (p. 140); credibility-transformer $\alpha$ by grid (p. 185) | ≤ 3 hyperparameters, log-scale values, repeat and zoom (pp. 432, 434) | – |
| `HP-M08` random search | – | GBM chapter: "randomized grid search" (p. 140), randomized 5-fold CV search (p. 135) | recommended over grid; log-uniform marginals (pp. 433–435) | – |
| `HP-M09` Bayesian optimisation | – | Optuna named in the GBM chapter (p. 141) | "cannot unambiguously recommend" (p. 436) | – |
| `HP-M10` sequential | – | GBM hyperparameters "cannot be chosen in isolation" (p. 140) | grid search "performed repeatedly", shifting and zooming (p. 434) | – |
| `HP-M11` multi-fidelity | – | – | drawback of needing runs "to completion"; freeze–thaw pointer (p. 436) | – |
| `HP-M12` evolutionary | – | – | – | – |
| `HP-M13` early stopping | U/V/T partition, "five times in a row" (pp. 290–291); callback restores best weights (p. 297) | the central device; callback; validation 10–20 % (pp. 100–103, 105) | Algorithm 7.1 (patience) p. 247; retrain strategies Algorithms 7.2 and 7.3 (pp. 249–250); equivalent to $L^2$ (p. 252) | – (closest analogue: remove the last diagonal and compare, p. 314) |
| `HP-M14` learning-rate adaptation | "tempered learning rates" (p. 279); $\nu_t=t/(t+3)$ (p. 287) | standard values of momentum optimisers (p. 100) | linear decay to $\tau$, $\epsilon_\tau\approx 1\%\,\epsilon_0$ (p. 295); adaptive methods §8.5 (pp. 306–311) | – |
| `HP-M15` constructive / NAS | Graph HyperNetworks mentioned (p. 290) | – | random-feature screening of CNN architectures (p. 363) | – |
| `HP-M16` nagging / ensembles | $M=1{,}600$ for a single policy (p. 323), 10–20 for the portfolio (p. 328), 20 suffice (p. 493) | "always consider the nagging" predictor, "with M = 10 or M = 20" (p. 109) | model averaging "extremely powerful and reliable" (p. 258); 5–10 members (p. 258) | simple or weighted averaging of methods (p. 334) |
| `HP-M17` snapshot averaging | – | – | Polyak (exponential) averaging of iterates (p. 322) | – |
| `HP-M18` Bayesian | Bayesian networks only as an outlook (§11.6.3) | penalty = Gaussian prior (p. 54) | MAP with Gaussian prior = weight decay (p. 139) | – |
| `HP-M19` best-of-N | argues against: an improvement from a lucky seed "should not be overstated" (p. 300) | "no (absolute) best selection" (p. 96) | – | – |
| `HP-M20` start at classical model | skip connection with the GLM, network part starts at zero (pp. 316–318) | "precisely starts in the MLE fitted GLM" (p. 114) | skip connections only as an optimisation aid (p. 201) | – |
| `HP-M21` transfer / warm start | – | – | copy the settings of a similar task (p. 426) | – |
| `HP-M22` empirical-null test | random control covariate (p. 498) | "add a purely random covariate component" (p. 113) | – | – |
| `HP-M23` information criteria | AIC "not supported by any theory" for networks (pp. 338, 464); GCV for λ (p. 193) | AIC/BIC "may not be valid" for networks (p. 31) | capacity bounds "rarely used in practice" (p. 114) | AIC and BIC as goodness-of-fit tests (p. 190) |
| `HP-M24` sensitivity | seed spread of network predictions (pp. 321–323) | fold standard deviations (p. 30) | – | sensitivity to alternative models (p. 150) |
| `HP-M26` visual curves | continue past the minimum to be sure (p. 297) | early-stopping figure (p. 103) | choose the learning rate by monitoring learning curves (p. 295) | graphs throughout |

Two tensions run through the whole document and are worth stating now:

* **Search versus a sufficiently large default.** [GBC] treats architecture, learning rate, dropout and weight decay as capacity hyperparameters to be searched (Chapter 11). [WM] and [AIT] advise *against* optimising the architecture: pick a network above a minimal complexity, early-stop it, and average over seeds. The actuarial papers follow [WM]/[AIT] far more often than [GBC] (Table 2.1: `HP-M02` and `HP-M13` against `HP-M07`–`HP-M12`).
* **What the test sample may be used for.** [GBC] forbids using test examples "in any way to make choices about the model, including its hyperparameters" (p. 121). [AIT] uses its test sample $\mathcal T$ to compare and select *between model classes* (p. 28). Neither book discusses a time-ordered (reserving) design. Section 4.5 shows that 10 of the 50 network documents used the test data or the known lower triangle to choose or confirm at least one in-scope hyperparameter, and that 3 more leave it possible.

# The methods, one by one

Notation used throughout. A network with parameters $\vartheta$ and hyperparameters $\lambda=(\lambda_1,\dots,\lambda_d)$ is fitted by minimising a training loss; call the result $\hat\vartheta(\lambda)$. A **selection signal** is a loss $\widehat{\mathcal L}_{\mathcal V}(\lambda)=\frac{1}{|\mathcal V|}\sum_{i\in\mathcal V}L\big(Y_i,\mu_{\hat\vartheta(\lambda)}(\boldsymbol x_i)\big)$ evaluated on a set $\mathcal V$ that the fit did not use. Every search method in Family II solves, approximately,
$$\lambda^\star=\arg\min_{\lambda\in\Lambda}\ \widehat{\mathcal L}_{\mathcal V}(\lambda),$$
and they differ only in how $\Lambda$ is explored. Family III chooses one hyperparameter (the number of steps, or the learning rate) *inside* a single fit. Family IV avoids choosing between random fits at all. Which $\mathcal V$ is used, and whether it is really unseen, is the subject of Section 4.

## Family I: no search (the value is fixed before any comparison)

### `HP-M01` Fiat

**What it is.** The value is written down with at most a statement of purpose ("to avoid overfitting"), never a reason for the number. By the extraction tables it is the single most common way a network hyperparameter was set in your folder: 46 of the 50 network documents fix at least one in-scope value this way (Table 2.1).

**Typical cases.**

* Mack-Net: "In order to avoid overfitting, the level of dropout regularization 𝜃 (Srivastava, Hinton, Krizhevsky, Sutskever, & Salakhutdinov, 2014) is set to 5%." (Ramos-Pérez et al. 2022, PDF p. 5, §3.2) Nothing in the paper says why 5 % rather than 0 % or 20 %, and the same value is used for all 200 Schedule P triangles.
* Andersen & Roed-Sørensen: "Early stopping ran 255 epochs with patience 10 and δmin = 0.1. For weight decay on all networks we select α = 0.3 as the regularization constant." (Andersen–Roed-Sørensen MSc 2021, PDF p. 85, Table 5.2 caption) The thesis's own theory section says the constant should be chosen by cross-validation ("This approach is also useful for choosing hyperparameters like regularization constants α covered in section 2.5." (Andersen–Roed-Sørensen MSc 2021, PDF p. 27, §2.3.1)).
* Noordhoek: "A constant learning rate of η = 0.001 is used throughout the training process." (Noordhoek MSc 2025, PDF p. 40, §3.3) followed by "This moderately small learning rate allows for suﬀiciently stable convergence while still enabling the network to make meaningful parameter updates during training." (Noordhoek MSc 2025, PDF p. 40, §3.3) (a description of what a moderate rate does, not a reason for 0.001).

**What the textbooks say.** None of the four books endorses an unexplained value; the nearest thing is the reproducibility requirement in [AIT]: "To be able to replicate results, the fitting procedure has to be designed very carefully and seeds of random number generators need to be stored to be able to track and replicate the specific solutions" ([AIT] p. 96) A fixed value is at least reproducible; an unreported one (`HP-M27`) is not.

### `HP-M02` Inherited from earlier work

**What it is.** The value is copied from a companion paper, a textbook listing or the original authors of the method. It is legitimate when the data and task are close to the source; it silently transports a tuning decision when they are not.

**Typical cases.**

* Richman & Wüthrich (2026a) take their architecture from the textbook: "with 3 hidden layers with number of neurons given by (20, 15, 10) in the 3 hidden layers." (Richman–Wüthrich 2026a, PDF p. 13, §4.2.1) and "For an explicit implementation of this architecture we refer to Wüthrich–Merz \[24, Listing 7.1\], only the part involving the volume in that reference needs to be dropped because here we only have unit exposures." (Richman–Wüthrich 2026a, PDF p. 13, §4.2.1)
* Härkönen follows Gabrielli (2019): "We follow \[4\] and choose q1 = 30 and q2 = 25 neurons for the two hidden layers. Since neural networks are easily overfitted we use a dropout rate of 20 % at every layer h to prevent this. Moreover, we include L2-regularisation for each hidden layer with regularisation parameter λ = 0.001." (Härkönen MSc 2021, PDF p. 19, §2.3.4.2)
* Lindholm et al. take the whole network from Gabrielli, Richman & Wüthrich: "will look at tunings of these algorithms that are, in some sense, standard. For the neural networks, we use the architecture of \[11\]. Their code, see Listing 4 in \[11\], can be used without modiﬁcation for the model of the number of reported claims." (Lindholm et al. 2020, PDF p. 86, §4)
* Nicholas re-uses the settings of Chaoubi et al. across 17 new simulation scenarios: "The following parameter settings are those which were used by Chaoubi et al. \[1\] in the micro-level reserving study." (Nicholas MSc 2026, PDF p. 43, Ch. 4) The thesis concludes: "The study was only successfully reproduced using the trained weight file that was created during the micro-level reserving study by Chaoubi et al \[1\]. This indicates that as time progresses and as packages are deprecated and/or become unavailable, different learning rates or network architecture parameters may be required as what gave reasonable results in the past may no longer provide realistic results." (Nicholas MSc 2026, PDF p. 46, Ch. 4)
* Cai (MSc) re-uses Kuo's DeepTriangle settings (128 GRU units, dropout 0.2; Appendix A) on a single company's triangle, although the thesis itself describes Kuo's model as built for many companies: "More recently, Kuo (2019) proposed to apply machine learning techniques on a large triangle dataset of multilpe P&C companies." (Cai MSc 2021, PDF p. 61, Ch. 5)
* Swallow's GAN settings: "Table 5: Training hyperparameters selected from research" (Swallow MSc 2023, PDF p. 32, Table 5)
* Kuo (2020, generative): "For both examples, we use the default hyperparameters specified in the CTGAN paper." (Kuo 2020 generative, PDF p. 4, §3.1)

**What the textbooks say.** [GBC] recommends exactly this as a *starting point*: "If your task is similar to another task that has been studied extensively, you will probably do well by first copying the model and algorithm that is already known to perform best on the previously studied task." ([GBC] p. 426) and, for manual search, "Manual hyperparameter tuning can work very well when the user has a good starting point, such as one determined by others having worked on the same type of application and architecture, or when the user has months or years of experience in exploring hyperparameter values for neural networks applied to similar tasks." ([GBC] p. 432) Neither book recommends stopping there.

### `HP-M03` Library default

**What it is.** The argument is not passed, so the software's default applies. In the papers this is often visible only in the code listing.

**Typical cases.**

* The whole Gabrielli–Richman–Wüthrich line uses Keras RMSprop with its default learning rate. The thesis version shows it in the listing: "model %>% compile ( optimizer = optimizer\_rmsprop (), loss = ’poisson ’)" (Gabrielli PhD 2020, PDF p. 171, Paper C Listing 4) Gabrielli (2019) says so in the text: "We choose the optimizer rmsprop within the Keras library, see line 2 of Listing 6; for theoretical background we refer to Section 8.5.2 of \[7\]." (Gabrielli 2019, PDF p. 16, §3.1.5)
* Ramos-Pérez et al. (2020): "The default calibration proposed by the authors for the ADAM parameters is applied as β1 = 0.9 and β2 = 0.999." (Ramos-Pérez et al. 2020, PDF p. 12, §3.3)
* Schneider & Schwab: "Specifically, we use the default settings and apply a learning rate decay every 10 epochs, using a multiplicative factor set to 0.1." (Schneider–Schwab 2025, PDF p. 32, Appendix B)
* Ferrario et al.: "In general, we always use the standard initialization provided by “glorot uniform” for all weights" (Ferrario et al. 2020, PDF p. 29, §4.5)
* Qiu passes the backpropagation defaults of `RSNNS` to the scaled-conjugate-gradient learner (Appendix A).
* In the shipped code, Manai (2026) declares every network hyperparameter "fixed a priori" in a YAML file, but the feed-forward learning rate (0.003) is a dataclass default that the YAML never sets (Section 7).

**What the textbooks say.** [AIT] accepts defaults for the optimiser: "this software often comes with suitable standard values for these hyper-parameters, i.e., they are ready-to-use." ([AIT] p. 100) [WM] likewise: "This library has a couple of standard momentum-based gradient descent methods implemented which use pre-defined learning rates and momentum coefficients." ([WM] p. 287) [GBC] gives Adam's suggested defaults, "Require: Step size ε (Suggested default: 0.001)" ([GBC] p. 311) and "Require: Exponential decay rates for moment estimates, ρ1 and ρ2 in \[0, 1). (Suggested defaults: 0.9 and 0.999 respectively)" ([GBC] p. 311), but warns that "Adam is generally regarded as being fairly robust to the choice of hyperparameters, though the learning rate sometimes needs to be changed from the suggested default." ([GBC] p. 309)

### `HP-M04` Reasoned a-priori argument

**What it is.** A value justified by a general argument (approximation theory, gradient behaviour, run time), with no comparison on the data. The extraction introduced a separate code for it (`S21`) because it is neither a bare fiat nor a search.

**Typical cases.**

* Depth: "The choice of two hidden layers seems to be rather arbitrary. However, this subjective choice provides a balance between model accuracy (two hidden layers often provide better results than one hidden layer) and complexity in calibration (more than two hidden layers are rather difficult to calibrate)." (Wüthrich 2017, PDF p. 6, §3.1) Gabrielli (2019) gives the same argument against one hidden layer: "However, K = 1 hidden layer may require an excessively large number of neurons, which makes the model difficult to calibrate. Moreover, an additional hidden layer may facilitate learning of interactions between the input features. Therefore, we choose K = 2 hidden layers in our model." (Gabrielli 2019, PDF p. 9, §3.1.2)
* Activation: "The reasons for choosing the hyperbolic tangent activation function are twofold. On the one hand, the property φ0 = 1 − φ2 , where φ0 denotes the derivative of φ, allows to efficiently calculate gradients. On the other hand, the property φ ∈ (−1, 1) prevents the activations in the neurons from exploding." (Gabrielli 2019, PDF p. 9, §3.1.2) and Härkönen: "We have chosen the hyperbolic tangent activation function f = tanh since it will allow us to compute the gradients efficiently" (Härkönen MSc 2021, PDF p. 17, §2.3.3.3)
* Cell type: "GRUs are preferred over Long Short-Term Memory (LSTM) networks due to their fewer training parameters and faster execution (Goodfellow et al., 2016)." (Cai et al. 2025, PDF p. 5, §2.1)
* Attention heads: "We used a single attention head to minimize parameter overhead for our short 9-timestep sequences." (Guo 2026, PDF p. 11, §4.2 Architecture 2)
* Algorithm: "Given that we are working with potentially limited data for reserving purposes, we decided to use the SAC algorithm." (Avanzi et al. 2026, PDF p. 16, §4.3)
* Size of the first layer: "As a general strategy, we believe that the first hidden layer should be sufficiently large, otherwise already in the first compression to the first hidden layer too much information gets lost." (Ferrario et al. 2020, PDF p. 45, §6.2.2)
* Compactness as a design goal: "The architecture is deliberately compact relative to the number of training observations." (Zelený MSc 2026, PDF p. 44, §4.4.1) and "The purpose of this specification is not to exhaustively optimise neural network architecture, but to evaluate a practically implementable claim-level DL reserving pipeline with the same rolling-origin design as the other models." (Zelený MSc 2026, PDF p. 44, §4.4.1)

**What the textbooks say.** [WM] argues the two choices the actuarial papers make most often. On activation: "This anti-symmetry and boundedness is an advantage in fitting deep FN network architectures. For this reason we usually prefer the hyperbolic tangent over other activation functions." ([WM] p. 270) and, on ReLU, "This is the preferred choice in the machine learning community. However, typically, we will not use it because in our experience it is less robust in fitting compared to the hyperbolic tangent activation function." ([WM] p. 270) On size: "At this stage, one could be tempted to choose a smaller network to prevent from over-fitting. In general, this is not a sensible thing to do because the network needs sufficient flexibility to be able to be fitted to the data." ([WM] p. 293) "Thus, the chosen network architecture should be above the bound of a necessary minimal complexity, and different architectures above this bound will provide similar accuracy (without a clear winner)." ([WM] p. 293) [AIT] agrees ("In practical applications, one should always work with deep FNNs, because composing layers facilitates interaction modeling." ([AIT] p. 95); "In general, aiming for a minimal or overly parsimonious FNN is not advisable." ([AIT] p. 105)). [GBC] recommends the opposite activation, "Rectified linear units are an excellent default choice of hidden unit." ([GBC] p. 191) and is candid that "In this chapter, it is difficult to give much more specific advice concerning the architecture of a generic neural network." ([GBC] p. 202) The tanh-versus-ReLU split in the literature follows the book the authors come from: the ETH line (Wüthrich, Gabrielli, Härkönen, Noordhoek) uses tanh; the DeepTriangle line (Kuo, Cai, Guo) and the tabular benchmarks use ReLU.

### `HP-M05` Rules of thumb and heuristic formulas

**What it is.** A formula or a range that depends on the problem size but not on a validation score. The ones found:

| Hyperparameter | Rule | Source |
|---|---|---|
| Embedding dimension | $b=C-1$ for $C$ companies | "fixed-length vector, where the length is a predetermined hyperparameter. In our implementation, we set the length as C − 1, the number of companies minus one." (Cai et al. 2025, PDF p. 7, §2.1) |
| Embedding dimension | $b=\lceil K^{1/4}\rceil$ for $K$ levels | "the target dimension can be chosen heuristically as the fourth root of the number of distinct categories" (Spedicato–Richman 2025, PDF p. 6, §3.2) |
| Embedding dimension | "$\lvert G\rvert-1$", then lowered by hand | "starting from the \|G\| − 1 rule but lowering the dimension to de = 50 to match the scale used in Kuo (2019) and to keep the embedding dimension substantially smaller than the category cardinality, which helped prevent overfitting." (Guo 2026, PDF p. 10, §4.2) |
| Embedding dimension | $b\ll K$; for words 50–300 | "Select an embedding dimension b ∈ N, this is a hyper-parameter that needs to be selected by the modeler, typically b ≪ K." ([AIT] p. 48); "Typical choices of b vary between 50 and 300." ([WM] p. 433) |
| Widths | decreasing pyramid $q_1>q_2>\dots$ | "We consider q1 , q2 ∈ {20, 25, 30, 35, 40, 45, 50} neurons in the K = 2 hidden layers, with q1 > q2 , which reflects the idea that information should be condensed through the hidden layers until reaching the output. For all these 21 models we train the neural network for 1’000 epochs using" (Gabrielli 2019, PDF p. 17, §3.2.1); "Following the guideline q1 > q2 > q3 + q4 , reflecting the idea that information processed through the hidden layers should be condensed until it reaches the output, we decide to use" (Gabrielli 2020, PDF p. 13, §4.2.5) |
| Widths | $q_1>q_0$ (more neurons than inputs) | "Often a good choice is q1 > q0" (Ferrario et al. 2020, PDF p. 44, §6.2.1) |
| Widths | 70–90 % of the input size | "Buyrukoglu et al. (2021) suggested that ml should be 70% to 90% of m0 , the size of the input layer, and less than 2m0 (Boger and Guterman 1997; Berry and Linoff 2004)." (Usman PhD 2024, PDF p. 156, §4.2.8) |
| Widths | equal width in every layer | "However, it is typical in practice to assume the same number of nodes in every hidden layer to reduce the complexity of hyperparameter tuning." (Avanzi et al. 2026, PDF p. 36, App. B.2); "The number of neurons is equal for all hidden layers." (Al-Mudafer et al. 2021, PDF p. 11, §3.2) |
| Depth | 3–6 layers of 15–30 neurons | "it has turned out that FNN architectures of depth d ∈ {3, . . . , 6} with approximately 15 to 30 neurons in each hidden layer work well." ([AIT] p. 106) |
| Depth | 3–5 layers for high-dimensional inputs | "If the data have large dimensions or features, L is suggested to be 3 to 5." (Usman PhD 2024, PDF p. 155, §4.2.8) |
| Batch size | powers of 2, 32–256 | "Especially when using GPUs, it is common for power of 2 batch sizes to offer better runtime. Typical power of 2 batch sizes range from 32 to 256, with 16 sometimes being attempted for large models." ([GBC] p. 279); "Common batch sizes B are powers of 2 (e.g., 32, 64, 128) for efficiency reasons and generally, B = 32 is a good initial choice." (Usman PhD 2024, PDF p. 156, §4.2.8) |
| Batch size | 2,000–5,000 for insurance frequency | "For insurance frequency problems, often, reasonable batch sizes s are in the range of 2000 to 5000" ([AIT] p. 105) |
| Learning-rate schedule | final rate ≈ 1 % of the initial one | "ετ should be set to roughly 1% the value of ε0. The main question is how to set ε0." ([GBC] p. 295) |
| Dropout | keep 0.8 of inputs and 0.5 of hidden units | "Typically, an input unit is included with probability 0.8 and a hidden unit is included with probability 0.5." ([GBC] p. 259) |
| Ensemble size | $k=32$ implicit members | "Hyperparameters. Compared to MLP, the only new hyperparameter of TabM is k — the number of implicit submodels. We heuristically set k = 32 and do not tune this value." (Gorishniy et al. 2025 TabM, PDF p. 6, §3.3) |
| Ensemble size | 10 or 20 networks | "a good value for M is in the range of 10 to 20" ([AIT] p. 109) |
| Validation share | 80/20 | "Typically, one uses about 80% of the training data for training and 20% for validation." ([GBC] p. 121) |
| Validation share | 10–20 % | "The validation sample is typically 10% to 20% of the entire learning sample L" ([AIT] p. 105) |
| Smoothing penalty | common degrees of freedom $\mathrm{df}=9$ | "Setting this shared df value to a moderate number, e.g., df = 9, proved to be a well-working prior assumption for each smooth term and circumvents expensive tuning schemes by fixing all 𝜆l values a priori." (Rügamer et al. 2023, PDF p. 11, §3.3.1) |

A rule is only as good as the similarity between the problem it was calibrated on and yours. The [AIT] depth/width and batch-size ranges were calibrated on large MTPL frequency data; a claims triangle has 55–78 cells, and none of the four books gives a rule for that regime.

### `HP-M06` Manual tuning, trial and error, "preliminary experiments"

**What it is.** Several settings were tried and one was kept, but the candidates, the number of trials and the score are not reported. It is the second-most-common *data-driven* method after early stopping (16 documents).

**Typical cases.**

* "Via experimentation, the Adam optimiser (Kingma and Ba, 2014), with a learning rate of 0.001 provided the most stable training compared with other optimisers like RMSProp and Stochastic Gradient Descent." (Al-Mudafer et al. 2021, PDF p. 16, §4)
* "Non-zero dropout rates were initially tested, however the results were not compelling. Consequently, a dropout rate of 0 was adopted for all models." (Avanzi et al. 2025, PDF p. 26, App. D) and, for early stopping, "After some initial testing, we decided to use a maximum of 200 epochs with a patience of 10 epochs. Once training stops, the weights are ‘restored’ to those that produced the smallest observed loss on the validation set." (Avanzi et al. 2025, PDF p. 26, App. D)
* Gabrielli's thesis version of the bCCNN paper: "In a preliminary analysis dropout rates of 10% have provided stable predictive models over several runs of the gradient descent algorithm, therefore we fix the dropout rate at 10% for all hidden neurons (see lines 39, 41 and 43 of Listing 4 in the appendix)." (Gabrielli PhD 2020, PDF p. 150, Paper C §3.3.2, thesis-only wording) The SSRN version says only "Finally, we remark that we have also been trying different network architectures, for instance, choosing other numbers of hidden neurons or different dropout rates. Although all these alternatives have provided similar results, there were some configurations that have lead to a slightly bigger decrease in out-of-sample validation loss at the price of more gradient descent steps. The architecture chosen for Figure 2 is a compromise between accuracy and run-time." (Gabrielli et al. 2018, PDF p. 13, §3.3.2)
* "In our model, for both of the sequence input encoders and the decoder, we utilize a single layer of LSTM with 3 hidden units. We found that these relatively small modules provided reasonable results but did not perform comprehensive tuning to test deeper and larger architectures." (Kuo 2020 BMDN, PDF p. 15, Long Short-Term Memory)
* "In neural network applications, cross-validation is not a feasible solution because of computational times. Therefore, we just did some trial and error on a few selected values, and we come up with a choice of η = 10−5 which seems to work well in our example." (Ferrario et al. 2020, PDF p. 32, §5.2)
* "Training GANs is notoriously difficult and finding a good model often requires trying out various hyperparameter configurations by brute force." (Swallow MSc 2023, PDF p. 24, §2.3)
* "When fitting the model (see Section 3.3), we also experimented with gdense,j (v) := ReLU(Av + b) but found results to be worse than with the smooth softplus activation function." (Bücher–Rosenstock 2022, PDF p. 3, Appendix A)
* Yu & Tomasi change the learning rate of one network only, judged on the training loss: "The initial learning rate was 10−3 for the depth-44 plain network, and 10−2 for the other 5 networks. The reason for the exception is that the training loss for the depth-44 plain network does not decrease with larger learning rates. The learning rate was divided by 10 after epochs 120 and 160 for all networks. The parameter λ of weight decay is 10−4 ." (Yu–Tomasi 2019, PDF p. 7, Table 1 caption)
* Pittarello et al. compare candidate sets by eye in TensorBoard: "In order to select the correct architecture the hyperparameter sets where compared by using the Tensorboard powered by Tensorflow, see \[9\]. Using the Tensorboard allows to select the most appropriate parameters combination in a compact way." (Pittarello et al. 2022, PDF p. 10, §6.1) The chosen values are never reported (Section 8).

**What the textbooks say.** [GBC] §11.4.1 is the only textbook treatment of manual search as a *method*: "There are two basic approaches to choosing these hyperparameters: choosing them manually and choosing them automatically." ([GBC] p. 427) "The primary goal of manual hyperparameter search is to adjust the effective capacity of the model to match the complexity of the task." ([GBC] p. 428) "The learning rate is perhaps the most important hyperparameter. If you have time to tune only one hyperparameter, tune the learning rate." ([GBC] p. 429) "Most hyperparameters can be set by reasoning about whether they increase or decrease model capacity. Some examples are included in Table 11.1." ([GBC] p. 430) Its Table 11.1 (p. 431) lists, for each common hyperparameter, whether increasing it raises or lowers capacity. [H] is the reserving counterpart: every parameter in the book (averaging period, tail curve, BF prior, GCC decay) is set by judgement, and the book warns about the behavioural side: "An example is so-called “anchoring”, which refers to the tendency to place too much reliance on one piece of information, leading to possibly biased results." ([H] p. 326)

**The problem for a thesis.** Manual tuning is defensible when the candidates and the score are reported; "preliminary experiments" that are not are indistinguishable from `HP-M01`. And if the preliminary runs were scored on the same validation data that later drives early stopping, the validation score is no longer an unbiased estimate (Section 4).

## Family II: explicit search over configurations

### `HP-M07` Grid search

**What it is.** $\Lambda=\Lambda_1\times\dots\times\Lambda_d$ with a short list of values per hyperparameter; every combination is trained and the best $\widehat{\mathcal L}_{\mathcal V}$ is kept. The cost is $\prod_h|\Lambda_h|$ trainings (times the number of seeds, if any).

**What the textbooks say.** [GBC]: "When there are three or fewer hyperparameters, the common practice is to perform grid search." ([GBC] p. 432) "Typically, a grid search involves picking values approximately on a logarithmic scale, e.g., a learning rate taken within the set {.1, .01, 10−3 , 10−4, 10−5}, or a number of hidden units taken with the set {50, 100, 200, 500, 1000, 2000}." ([GBC] p. 434) "the smallest and largest element of each list is chosen conservatively, based on prior experience with similar experiments, to make sure that the optimal value is very likely to be in the selected range." ([GBC] p. 434) "The obvious problem with grid search is that its computational cost grows exponentially with the number of hyperparameters." ([GBC] p. 434) [AIT] mentions grid search only in the boosting chapter, "In most cases, these hyper-parameters are selected by a grid search with (cross-)validation or by a randomized grid search." ([AIT] p. 140) and for one network hyperparameter, the credibility transformer's $\alpha$: "The probability α is treated as a hyper-parameter, and it can be optimized via grid search." ([AIT] p. 185) [WM] uses grids only for GLM penalties, chosen by cross-validation: "the regularization parameter λ > 0 which acts as a hyper-parameter. Optimal hyper-parameters are determined by cross-validation." ([WM] p. 211)

**Who used it, over what.**

* Wüthrich (2017), widths per development period: "Firstly, we have split the corresponding claims into a learning data set and a test data set. For the test data set we have chosen at random 10% of the individual claims and the remaining 90% of the individual claims were allocated to the learning data set." (Wüthrich 2017, PDF p. 8, §3.3) "These estimated model parameters were then used to calculate the out-of-sample loss on the test data set, and the hidden neuron combination with the smallest out-of-sample loss was chosen as the best model." (Wüthrich 2017, PDF p. 8, §3.3) The grid is $q_1,q_2\in\{2,\dots,10\}$ (81 networks per period), and the selection is followed by a refit on all data: "We have then used these optimal neural networks of Table 1 and we have calibrated the model parameter α once more but on the entire data set, i.e., simultaneously on the learning and test data sets. Note that we are allowed to do this because the split of the data has only been used for model selection (which fully determines the complexity of the model)." (Wüthrich 2017, PDF p. 8, §3.3)
* Gabrielli (2019), widths: "We consider q1 , q2 ∈ {20, 25, 30, 35, 40, 45, 50} neurons in the K = 2 hidden layers, with q1 > q2 , which reflects the idea that information should be condensed through the hidden layers until reaching the output. For all these 21 models we train the neural network for 1’000 epochs using" (Gabrielli 2019, PDF p. 17, §3.2.1) Result: "The three combinations (q1 , q2 ) with the smallest average validation loss observed over 1’000 epochs are presented in Table 6. We get the best result for combination (q1 , q2 ) = (30, 25)." (Gabrielli 2019, PDF p. 17, §3.2.1) The multi-LoB model repeats this over a larger grid (78 networks, Table 10): "We get the best result for the combination (q1 , q2 ) = (40, 30)." (Gabrielli 2019, PDF p. 25, §4.2.1)
* Ramos-Pérez et al. (2020), dropout per triangle: "The percentage of dropout regularization θ is the hyperparameter to be optimized by applying a grid search and measuring the test error." (Ramos-Pérez et al. 2020, PDF p. 10, §3.2)
* Yeldan & Karabey, four hyperparameters jointly: "Grid search and five-fold cross-validation are used in together to determine the hyperparameters." (Yeldan–Karabey 2026, PDF p. 12, §3.2) with grids for widths "(25, 20, 15), (25, 15, 5), (20, 15, 10), (15, 10, 5)" (Yeldan–Karabey 2026, PDF p. 12, Table 1, "Number of neurons"), batch size "750, 1000, 1250, 1500" (Yeldan–Karabey 2026, PDF p. 12, Table 1, "Batch size") and epochs "50, 100, 150, 200" (Yeldan–Karabey 2026, PDF p. 12, Table 1, "Epoch number") (64 settings, separately for the mean and the dispersion network: "Since the mean and dispersion have different distributions, the learning dynamics of the two networks are differ­ ent, requiring separate optimization processes." (Yeldan–Karabey 2026, PDF p. 12, §3.2)).
* Avanzi et al. (2025): "We perform a grid search over a modest selection of hyperparameter combinations. We tested 16 hyperparameter combinations for the LSTM and LSTM+, and 24 combinations for the FNN and FNN+." (Avanzi et al. 2025, PDF p. 13, §3.4) with "Consequently, we train the model with each hyperparameter combination once, and evaluate its performance on the validation set." (Avanzi et al. 2025, PDF p. 13, §3.4)
* Schwab (PhD, Ch. 3–4): "To find the hyperparameters, we perform a grid search, following the guidelines provided by Devlin et al. (2019). This grid search explores different configurations of the learning rate, the batch size, and the number of epochs to determine the combination that delivers the best performance on the validation set." (Schwab PhD 2025, PDF p. 87, §3.4.1) and "We tune all baseline models and our proposed IMoE model using a light grid search over relevant hyperparameters. Tuning is performed separately for the credit scoring and insurance frequency tasks, with model selection based on validation performance (AUC for classification, Poisson deviance for count regression). Early stopping is applied in all cases based on validation loss, with a patience of 100 epochs." (Schwab PhD 2025, PDF p. 159, Appendix C.3)
* Nicholas, the learning rate only: "The learning rates of 0.0001, 0.0005, 0.001, 0.01, and 0.05 were experimented with in the study. These learning rates are the step sizes with which the stochastic gradient descent algorithm moves in optimization of the objective function." (Nicholas MSc 2026, PDF p. 35, Ch. 4)
* Cai et al., the input sequence length: "As shown in Figure 6, the cross-validation error was evaluated across different sequence lengths, with a length of nine identified as optimal for the DT model." (Cai et al. 2025, PDF p. 17, §4)
* Hiabu et al. demonstrate a grid before switching to Bayesian optimisation: "To perform the grid search, we need to specify the hyperparameter\_grid on which we optimize." (Hiabu et al. 2025, PDF p. 15, §2.4.1)

**Two reserving templates without a network.** Balona & Richman grid-search the options of the chain ladder, Bornhuetter–Ferguson and generalised Cape Cod, scoring each option on the **next diagonal** it has not seen: "based on the next diagonal of experience. Note that, at this stage, this next diagonal has not been used to fit the reserving model, i.e. it is out of sample data." (Balona–Richman 2020, PDF p. 13, §3) "We show these variations on the CL model in Table 1, which results in 36 unique combinations of parameters." (Balona–Richman 2020, PDF p. 17, §4.1) "which expands the total search space, shown in Table 5, to 756 unique parameter sets." (Balona–Richman 2020, PDF p. 22, §4.2) Jin (2021) grid-searches tree ensembles per development period, scoring on held-out reserves: "The model with the lowest RMSE is the optimal model and therefore the parameter set corresponding to this model is the optimal hyper parameter set." (Jin MSc 2021, PDF p. 16, §3.3) Both scoring rules transfer directly to network hyperparameters (Section 4.4).

**What goes wrong.** Optima on the edge of the grid: Wüthrich's widths for $j\ge3$ are $(2,2)$, the lower corner of $\{2,\dots,10\}^2$; Yeldan & Karabey pick the smallest epoch count (50) and the smallest architecture for the mean network; Avanzi et al. pick the largest learning rate (0.01) for all four models (Appendix A). By [GBC]'s own rule (the range is chosen so that the optimum is "very likely" inside it) each of these grids should have been extended.

### `HP-M08` Random search

**What it is.** Draw $T$ configurations independently, $\lambda^{(t)}\sim\prod_h p_h$, with continuous hyperparameters drawn on a log scale, for example $\log_{10}\eta\sim\mathcal U(-5,-1)$, and keep the best.

**What the textbooks say.** [GBC] prefers it to grid search: "Fortunately, there is an alternative to grid search that is as simple to program, more convenient to use, and converges much faster to good values of the hyperparameters: random search (Bergstra and Bengio, 2012)." ([GBC] p. 434) "First we define a marginal distribution for each hyperparameter, e.g., a Bernoulli or multinoulli for binary or discrete hyperparameters, or a uniform distribution on a log-scale for positive real-valued hyperparameters." ([GBC] p. 434) "Unlike in the case of a grid search, one should not discretize or bin the values of the hyperparameters." ([GBC] p. 435) "In fact, as illustrated in figure 11.2, a random search can be exponentially more efficient than a grid search, when there are several hyperparameters that do not strongly affect the performance measure." ([GBC] p. 435) [AIT] names a "randomized" search once, for boosting: "this has been determined by a randomized 5-fold cross-validation optimal hyper-parameter search." ([AIT] p. 135)

**Who used it.**

* Schneider & Schwab: "We start our search process by using Random Search to explore the hyperparameter space rapidly and broadly (Bergstra & Bengio, 2012). The search space for our model's hyperparameters is guided by general recommendations from Bengio (2012) and Greff et al. (2017) and is configured for both data sets as follows:" (Schneider–Schwab 2025, PDF p. 33, Appendix B) with "The learning rate is sampled from a log‐uniform distribution, defined over the interval \[1e − 5, 0.1\]." (Schneider–Schwab 2025, PDF p. 33, Appendix B), "The hidden sizes qstatic , qlstm , and qcomb are sampled from the discrete set {32, 64, 128, 256}." (Schneider–Schwab 2025, PDF p. 33, Appendix B), "The batch size is sampled from the discrete set {1024, 2048} ." (Schneider–Schwab 2025, PDF p. 33, Appendix B) and "The dropout rate is uniformly sampled from the interval \[0.1, 0.5\]." (Schneider–Schwab 2025, PDF p. 33, Appendix B)
* Guo: "In the WC screening stage, 100 hyperparameter configurations were drawn uniformly from:" (Guo 2026, PDF p. 15, §4.4) "Learning rate: log-uniform on \[10−4 , 5 × 10−3 \]; Dropout rate: log-uniform on \[0.01, 0.30\]; GRU units: uniform in {64, 128, 256}; Dense units: uniform in {32, 64, 128}; Batch size: uniform in {256, 512, 1024}; Maximum epochs: uniform in {500, 1000}." (Guo 2026, PDF p. 15, §4.4)
* Côté et al.: "We used a random search to explore the settings and decided on the values in Table A.1." (Côté et al. 2025, PDF p. 15, App. A) and "In a random search, each combination of hyperparameters tested was randomly selected from the chosen grid. The number of search iterations was set based on a time/resources compromise. The strategy was to run multiple searches instead of a single big search. Each time, the search space was narrowed for more fine-tuning." (Côté et al. 2025, PDF p. 16, App. B.3)

**What goes wrong.** A random search is only as reliable as the score of each draw. Guo trained each of the 100 configurations once, and the ranking did not survive re-running: "The screening-stage winner (Config 2, screening MAPE 8.26%) dropped to rank 5 after multiseed validation (mean 8.66%, σ = 0.198%), confirming that single-seed rankings can be misleading. The validated winner was Config 99 (mean 8.39%, σ = 0.000%), with 256 GRU units, low dropout (1.5%), and a conservative learning rate (1.07 × 10−4 )." (Guo 2026, PDF p. 17, §5.2) This is the "winner's curse" of any single-seed search, and the reason for `HP-M11`.

### `HP-M09` Bayesian (model-based) optimisation

**What it is.** A surrogate model $f(\lambda)\approx\widehat{\mathcal L}_{\mathcal V}(\lambda)$ is fitted to the configurations tried so far, and the next configuration maximises an acquisition function, for example the expected improvement
$$\lambda_{t+1}=\arg\max_{\lambda}\ \mathbb E\big[\max\{f^\star_t-f(\lambda),0\}\big],\qquad f^\star_t=\min_{s\le t}\widehat{\mathcal L}_{\mathcal V}(\lambda_s).$$
With a Gaussian-process surrogate this is the `ParBayesianOptimization`/`bayes_opt` approach; the Tree-structured Parzen Estimator (TPE, Optuna's default sampler) models $p(\lambda\mid\text{good})/p(\lambda\mid\text{bad})$ instead.

**What the textbooks say.** [GBC] is cautious: "Most model-based algorithms for hyperparameter search use a Bayesian regression model to estimate both the expected value of the validation set error for each hyperparameter and the uncertainty around this expectation." ([GBC] p. 435) "Currently, we cannot unambiguously recommend Bayesian hyperparameter optimization as an established tool for achieving better deep learning results or for obtaining those results with less effort." ([GBC] p. 436) "Bayesian hyperparameter optimization sometimes performs comparably to human experts, sometimes better, but fails catastrophically on other problems." ([GBC] p. 436) [AIT] names a tool, again only in the boosting chapter: "There are specialized tools like Optuna that are designed for hyper-parameter optimization; see Akiba et al. \[5\]." ([AIT] p. 141) [WM] and [H] do not discuss it.

**Who used it.**

* Hiabu et al. (ReSurv): "bayes\_out &lt;- bayesOpt(FUN = obj\_func, bounds = bounds, initPoints = 50, iters.n = 1000, iters.k = 50, otherHalting = list(timeLimit = 18000))" (Hiabu et al. 2025, PDF p. 18, §2.5.1; the same call for XGB on PDF p. 20) over "bounds &lt;- list(num\_layers = c(2L, 10L), num\_nodes = c(2L, 10L), optim = c(1L, 2L), activation = c(1L, 2L), lr = c(0.005, 0.5), xi = c(0, 0.5), eps = c(0, 0.5))" (Hiabu et al. 2025, PDF p. 17, §2.5.1) with the score "The score metric we inspect is the negative (partial) likelihood. The likelihood is returned with a negative sign as Wilson (2022) is maximizing the objective function." (Hiabu et al. 2025, PDF p. 17, §2.5.1) Two selected values sit on the bounds (10 nodes, $\epsilon=0$; Appendix A).
* Schneider & Schwab, as the second stage after random search: "After running the Random Search process with a total of 32 configurations, we refined our hyperparameter tuning using Bayesian Opimization (Snoek et al., 2012). Based on the outcomes of the Random Search, we identified the top three configurations and used their parameter ranges to define the search space for Bayesian Search." (Schneider–Schwab 2025, PDF p. 33, Appendix B) "The upper and lower bounds for each parameter in the Bayesian search space were set based on the extremities of these ranges, ensuring a focused yet comprehensive exploration in the subsequent optimization phase. To thoroughly explore the refined search space, we evaluated 32 further configurations." (Schneider–Schwab 2025, PDF p. 33, Appendix B)
* Usman, after a manual search: "Guided by the manual exploration, the BO search is conducted for the hyperparameter spaces:" (Usman PhD 2024, PDF p. 159, §4.2.9) over "E ∈ \[250, 450\], B ∈ \[75, 120\], ζ ∈ \[0.0097, 0.01\], p = 0.05, 0.10, 0.20," (Usman PhD 2024, PDF p. 159, eq. 4.24) The learning-rate range $[0.0097,0.01]$ is so narrow that the rate is effectively fixed by the manual stage.
* Gorishniy et al. (TabM): "Hyperparameter tuning. In most cases, hyperparameter tuning is performed with the TPE sampler (typically, 50-100 iterations) from the Optuna package (Akiba et al., 2019)." (Gorishniy et al. 2025 TabM, PDF p. 18, §D.2)
* Ye et al.: "We use Optuna (Akiba et al., 2019) with a fixed budget of 100 trials per method–dataset pair. After selecting the best configuration, we retrain and evaluate each model with 15 random seeds and report the mean across seeds." (Ye et al. 2025, PDF p. 14, §4.3)
* Spedicato & Richman, for the MLP only (no budget, sampler or space reported): "The Optuna hyperparameter optimization framework (Akiba et al. 2019) is used to tune the hyperparameters, when appropriate." (Spedicato–Richman 2025, PDF p. 10, §4.3) The transformer that wins their comparison was not tuned: "However, the TRF approach consistently surpassed both" (Spedicato–Richman 2025, PDF p. 17, §6) … "the MLP and GBT approaches, even without hyperparameter tuning." (Spedicato–Richman 2025, PDF p. 20)
* Tavares uses Bayesian optimisation for tree ensembles only: "Bayesian optimization is a more efﬁcient way of searching the hyperparameter space compared to grid search or random search \[36\]." (Tavares MSc 2023, PDF p. 50, §4.1.2)

### `HP-M10` Sequential, one-at-a-time and staged search

**What it is.** Hyperparameters are tuned in a fixed order, each with the others held at their current values:
$$\lambda_h^\star=\arg\min_{\lambda_h\in\Lambda_h}\widehat{\mathcal L}_{\mathcal V}\big(\lambda_1^\star,\dots,\lambda_{h-1}^\star,\lambda_h,\lambda_{h+1}^{(0)},\dots,\lambda_d^{(0)}\big),\qquad h=1,\dots,d.$$
It costs $\sum_h|\Lambda_h|$ rather than $\prod_h|\Lambda_h|$ trainings, but the answer depends on the order and on the starting values $\lambda^{(0)}$, and interactions are never explored.

**What the textbooks say.** [AIT], about boosting: "These hyper-parameters highly interact, and they cannot be chosen in isolation." ([AIT] p. 140) [GBC]'s repeated grid refinement is the only related device it describes: "Grid search usually performs best when it is performed repeatedly." ([GBC] p. 434)

**Who used it.**

* Al-Mudafer et al. is the clearest case in the reserving literature: "The MDN’s architecture was selected using an algorithm that successively optimised one hyper-parameter at a time. The number of components in the density is increased so long as the test error decreases, which allows the algorithm to consider fitting densities of infinite flexibility." (Al-Mudafer et al. 2021, PDF p. 11, §3.2) It starts from "a set of initial hyper-parameters deemed suitable through judgement. Setting θ initial = {0, 0, 0, 60, 2, 2} worked well in this paper, as allowing the algorithm to explore unregularised models vastly improved the fit in some instances." (Al-Mudafer et al. 2021, PDF p. 12, §3.2 step 1) then "Using θ initial and keeping all other hyper-parameters fixed, use Grid Search to test all desired values of λw , the weight penalty coefficient. Select the coefficient with the lowest test error, λ̂w , and update" (Al-Mudafer et al. 2021, PDF p. 12, §3.2 step 2) … "Using θ 3 and keeping all other hyper-parameters fixed, use Grid Search to test all desired values of h, the number of hidden layers." (Al-Mudafer et al. 2021, PDF p. 12, §3.2 step 5) … "Using θ 4 and keeping all other hyper-parameters fixed, fine-tune the number of neurons and components. This process tests an increasing number of components until the test error ceases to improve." (Al-Mudafer et al. 2021, PDF p. 12, §3.2 step 6) The order is: weight penalty $\lambda_w$ → sigma penalty $\lambda_\sigma$ → dropout $p$ → depth $h$ → (width $n$, components $K$), with grids $\lambda\in\{0,10^{-4},10^{-3},10^{-2},10^{-1}\}$, $p\in\{0,0.1,0.2\}$, $h\in\{1,2,3,4\}$, $n\in\{20,40,60,80,100\}$ ("λw , the L2 weight penalty. The values \[0, 0.0001, 0.001, 0.01, 0.1\] were tested." (Al-Mudafer et al. 2021, PDF p. 11, §3.2); "p, the dropout rate (See Srivastava, Hinton, Krizhevsky, Sutskever and Salakhutdinov (2014) for details). The values \[0, 0.1, 0.2\] were tested." (Al-Mudafer et al. 2021, PDF p. 11, §3.2); "h, the number of hidden layers. The values \[1, 2, 3, 4\] were tested." (Al-Mudafer et al. 2021, PDF p. 11, §3.2); "n, the number of neurons in each hidden layer. The values \[20, 40, 60, 80, 100\] were tested." (Al-Mudafer et al. 2021, PDF p. 11, §3.2)). The authors present it as an extension of the Gabrielli line: "This algorithm extends the methodology implemented by Gabrielli, Richman and Wüthrich (2020) by also searching for the best-performing regularisation coefficients." (Al-Mudafer et al. 2021, PDF p. 3, §1.2.2)
* Gabrielli (2019) is a two-step version: widths first, each at its own best (smoothed) epoch, then one epoch count for all lines of business: "We need to determine the numbers of neurons in the K = 2 hidden layers of the two feed-forward neural networks of the single NNDODP model, and the number of epochs to be used during training. To this end, we split our 1’198’888 individual claims into a training set and a validation set with equal numbers of claims (on a line of business and an accident year level)." (Gabrielli 2019, PDF p. 17, §3.2.1)
* Ferrario et al. compare optimiser, batch size, initialisation, early stopping, penalty, dropout and architecture one after another, each with the rest fixed ("For each optimizer we use the same initial parameter for θ, the same batch size and the same number of epochs." (Ferrario et al. 2020, PDF p. 19, §4.1)).
* Usman: manual search, then Bayesian optimisation inside ranges chosen from it ("In this method, manual (MAN) search is combined with the guidelines in Section 4.2.8 to set L = 5 and m = (45, 30, 15, 10, 5). Activation functions are set as f1:4 = fLinear , f5 = fELU to ensure the output neurons are non-negative." (Usman PhD 2024, PDF p. 158, §4.2.9); "Guided by the manual exploration, the BO search is conducted for the hyperparameter spaces:" (Usman PhD 2024, PDF p. 159, §4.2.9)).
* Schneider & Schwab: random search, then Bayesian optimisation in the box spanned by the top three random-search configurations ("The upper and lower bounds for each parameter in the Bayesian search space were set based on the extremities of these ranges, ensuring a focused yet comprehensive exploration in the subsequent optimization phase. To thoroughly explore the refined search space, we evaluated 32 further configurations." (Schneider–Schwab 2025, PDF p. 33, Appendix B)). One reported optimum lies outside that box (Section 8).
* Without a network, Balona & Richman propose the same two-step idea for reserving parameters: "Following this two-step procedure would have produced the same model as that selected using the CDR score, but at much lower computational cost." (Balona–Richman 2020, PDF p. 24, §4.2)

### `HP-M11` Multi-fidelity and staged screening

**What it is.** Many configurations are screened cheaply (few epochs, few iterations, one seed) and only the best are evaluated expensively. Successive halving is the formal version: evaluate $n$ configurations at budget $b$, keep the best $n/\eta$ at budget $\eta b$, repeat.

**What the textbooks say.** [GBC] notes the cost that multi-fidelity methods address, most algorithms need each training run "to run to completion before they are able to extract any information from the experiment" ([GBC] p. 436) and mentions freeze–thaw as a response (same page). The other three books are silent.

**Who used it.**

* Guo, with the number of **seeds** as the fidelity: "In the validation stage, the top 20 configurations by screening MAPE were retrained with 5 additional independent seeds each (100 validation runs). The training, evaluation, and benchmark protocols carried over verbatim from Phase 1, except that the hyperparameter values listed above replaced the fixed Phase 1 settings." (Guo 2026, PDF p. 15, §4.4) "Each configuration was trained once (single seed) in the screening stage. A Random Forest regressor (Breiman 2001) was fitted to predict MAPE from the 6 hyperparameters, and its impurity-based feature importance was used as a descriptive ranking of the hyperparameters within the Phase 2 search space." (Guo 2026, PDF p. 15, §4.4)
* Côté et al., with the number of **iterations** as the fidelity: "Hence, to reduce computation time, we limited the number of iterations for each combination to 100,000." (Côté et al. 2025, PDF p. 16, App. B.3) "Once we identified a couple of potentially good combinations in this manner, we conducted a full training with over 2 million iterations for each one." (Côté et al. 2025, PDF p. 16, App. B.3)
* Hiabu et al. do it implicitly: the tuning runs use `epochs = 300` and `patience = 20` ("patience = 20), epochs = as.integer(300), num\_workers = 0, verbose = FALSE, verbose.cv = TRUE, folds = 3, parallel = FALSE, random\_seed = as.integer(Sys.time()))" (Hiabu et al. 2025, PDF p. 17, §2.4.2; identical code again on PDF p. 18, §2.5.1)), the final fit 5,500 epochs and patience 350 ("num\_layers = 2, early\_stopping = TRUE, patience = 350, verbose = FALSE, network\_structure = NULL, num\_nodes = 10, activation = "LeakyReLU", optim = "SGD", lr = 0.02226655, xi = 0.4678993, epsilon = 0, batch\_size = 5000L, epochs = 5500L," (Hiabu et al. 2025, PDF p. 22, §2.6)). The selected values are therefore optimal for a different training budget than the one used.
* Ye et al. propose forecasting the final score from the first epochs in order to prune runs: "Since deep tabular training is often expensive and hyperparameter-sensitive, forecasting later performance from early epochs allows us to prune poor runs." (Ye et al. 2025, PDF p. 50, App. C.5)

### `HP-M12` Evolutionary and population-based search

**What it is.** A population of configurations is mutated and the best survive. Only Gridin uses it, through Microsoft NNI: "Naive Evolution: Naive evolution (or genetic algorithm) randomly initializes a population based on the search space. It selects the best ones for each generation and does some hyper-parameter mutation on them to get the next generation. I prefer using this tuner in most cases." (Gridin 2021, §17, Ch. 6 > Tuner; idx p. 176) with "search.config.tuner.class\_args\['population\_size'\] = 8" (Gridin 2021, §17, Ch. 6 > NNI search > Search configuration). Avanzi et al. mention population-based training as an option they did not pursue: "There are also some other novel approaches like population-based training (Jaderberg et al., 2017), and meta-gradient approaches (Xu et al., 2018) that could be explored, but we have decided to leave this for potential future work, as this is not the central focus of this paper." (Avanzi et al. 2026, PDF p. 18, §5.2.1) None of the four textbooks describes it.

## Family III: set during training

### `HP-M13` Early stopping (the number of epochs or gradient steps)

**What it is.** Train, record the validation loss $V(t)=\widehat{\mathcal L}_{\mathcal V}\big(\hat\vartheta^{(t)}\big)$ after each epoch $t$, and choose
$$t^\star=\arg\min_{t\le t_{\max}}V(t).$$
It is the one data-driven method used by a majority of the network documents (30 of 50), and the only one that [WM] and [AIT] recommend for networks. It comes in six variants in your folder; they differ in *how* $t^\star$ is read and *what is done after* it is found.

**What the textbooks say.**

* [GBC] frames it as hyperparameter selection: "One way to think of early stopping is as a very efficient hyperparameter selection algorithm. In this view, the number of training steps is just another hyperparameter." ([GBC] p. 247) The stopping rule is Algorithm 7.1 with a patience $p$: "Let p be the “patience,” the number of times to observe worsening validation set error before giving up." ([GBC] p. 247) The book then gives two ways to use all the data afterwards, Algorithm 7.2: "One strategy (algorithm 7.2) is to initialize the model again and retrain on all" ([GBC] p. 248) "of the data. In this second training pass, we train for the same number of steps as the early stopping procedure determined was optimal in the first pass." ([GBC] p. 249) and Algorithm 7.3 (p. 250), which keeps the early-stopped parameters, continues training on all the data and monitors the validation loss, to "continue training until it falls below the value of the training set objective at which the early stopping procedure halted" ([GBC] p. 249) About Algorithm 7.2 it adds "For example, there is not a good way of knowing whether to retrain for the same number of parameter updates or the same number of passes through the dataset." ([GBC] p. 249) and about Algorithm 7.3 "This strategy avoids the high cost of retraining the model from scratch, but is not as well-behaved. For example, there is not any guarantee that the objective on the validation set will ever reach the target value, so this strategy is not even guaranteed to terminate." ([GBC] p. 249) It also shows that for a quadratic loss the number of steps plays the role of an $L^2$ penalty, with $\tau\approx 1/(\epsilon\alpha)$ (p. 252): "Early stopping therefore has the advantage over weight decay that early stopping automatically determines the correct amount of regularization while weight decay requires many training experiments with different values of its hyperparameter." ([GBC] p. 252)
* [WM] builds the three-way partition into the method: "This early stopping point is determined by doing an out-of-sample analysis. This requires the learning data L to be further split into training data U and validation data V." ([WM] p. 290) "the latter only being used in the final step for comparing different statistical models (e.g., a GLM vs. a FN network)." ([WM] p. 290) It recommends a patience-type rule for noisy curves, "In such cases we should use more sophisticated stopping criteria than (7.27), for instance, early stop if the validation loss increases five times in a row." ([WM] p. 291) and a callback that returns the best weights, "we retrieve the network with the lowest validation loss using a callback." ([WM] p. 297) with the warning "of course, in practice we need to continue beyond this minimal validation loss to ensure that we have really found the minimum." ([WM] p. 297)
* [AIT] makes it the central device: "The key to this problem is early stopping, some scholars call early stopping a regularization method, however, technically, it is different because it has an essential temporal component related to algorithmic time." ([AIT] p. 101) "Of course, the validation sample V should be sufficiently large to obtain a credible stopping rule (that itself is not dominated by the noise in V)." ([AIT] p. 103) "Often one takes 20% or 10% of the learning data L as validation sample V, depending on the sample size n." ([AIT] p. 103) "Technically, for gradient descent training, one installs a so-called callback." ([AIT] p. 103)
* [H] has no early stopping. Its nearest analogue is the removed-diagonal test (Section 4.4).

**The six variants found in the papers.**

| Variant | Rule | Papers (evidence) |
|---|---|---|
| (a) Patience rule on the validation loss (best weights restored where stated) | stop when $V$ has not improved for $p$ epochs; return $\hat\vartheta^{(t^\star)}$ | Avanzi et al. 2025 ("After some initial testing, we decided to use a maximum of 200 epochs with a patience of 10 epochs. Once training stops, the weights are ‘restored’ to those that produced the smallest observed loss on the validation set." (Avanzi et al. 2025, PDF p. 26, App. D)); Kuo 2020 ("Training is stopped early when the validation loss does not improve for ten epochs; we cap the maximum number of epochs at 100." (Kuo 2020 BMDN, PDF p. 19, Training and Scoring)); Cai et al. 2025 ("We train the DT model for a maximum of 1000 epochs, employing an early stopping scheme. If the loss on the validation set does not improve over a 100-epoch window, we stop training and keep the weights on the epoch with the lowest validation loss." (Cai et al. 2025, PDF p. 7, §2.2)); Guo 2026 ("Optimizer: Adam with AMSGrad (Reddi et al. 2018), learning rate 5 × 10−4 ; Batch size: 512; Maximum epochs: 1000; Early stopping: patience 200 epochs, minimum improvement δ = 0.001, monitoring validation loss;" (Guo 2026, PDF p. 12, §4.3)); Gorishniy et al. 2025 ("We continue training until there are patience consecutive epochs without improvements on the validation set; we set patience = 16 for the DL models." (Gorishniy et al. 2025 TabM, PDF p. 18, §D.2)); Rügamer et al. 2023 ("mixdistreg is optimized using Adam with a learning rate 1e-3, batch size of 32, early stopping on a 10% validation data set and a patience of 250 epochs." (Rügamer et al. 2023, PDF p. 22, App. B)); Zelený 2026 ("A maximum of 280 training epochs is allowed, with early stopping based on a 10% held-out validation split and a patience of 20 epochs." (Zelený MSc 2026, PDF p. 44, §4.4.1)); Nicholas 2026 ("With regard to regularization, early stopping \[4\] is implemented with a patience of 15 epochs. That is, if the validation error has not improved further for 15 epochs then training is halted. This early stopping criterion comes into effect after the learning rate performance scheduling patience of 10 has been exceeded \[13\]. Learning rate performance scheduling refers to the reduction by a factor of 0.1 in the training learning rate after ten epochs, with no further improvement in the validation error. The maximum number of epochs is 500." (Nicholas MSc 2026, PDF p. 27, §3.1)); Ferrario et al. 2020 ("Installing a callback we retrieve the model with the lowest validation loss; the corresponding code is shown in Listing 5, and Table 9 provides the results." (Ferrario et al. 2020, PDF p. 30, §5.1)); Richman & Wüthrich 2021 ("We fit this FFN network using the nadam version of SGD on batches of size 5,000 over 100 epochs, and we retrieve the network calibration that provides the smallest validation loss on a training-validation partition U and V of the learning data L." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 15, §3.4)); Al-Mudafer et al. 2021 ("The validation loss rarely decreased steadily, hence training was only stopped when it did not hit new lows in the last 1000 epochs. This is referred to as the patience measure in the Keras interface; a lower patience than 1000 would sometimes prematurely stop training." (Al-Mudafer et al. 2021, PDF p. 16, §4)) |
| (b) Read $t^\star$ on a split, then refit on all data for $t^\star$ steps (GBC Algorithm 7.2) | $t^\star$ from a training/validation split; final model trained on $\mathcal U\cup\mathcal V$ for $t^\star$ steps from the same start | Gabrielli et al. 2018 ("For this reason, we decide to run the gradient descent algorithm on the full data DI\|m for 300 iterations (for exactly this network architecture). Note that, for simplicity, we use 300 iterations for all LoBs." (Gabrielli et al. 2018, PDF p. 13, §3.3.2)); Gabrielli 2020 ("After this training/validation analysis, we train the neural network using all n individual claims for the chosen number of epochs." (Gabrielli 2020, PDF p. 19, §5.4)); Härkönen 2021 ("Hence, the models are fitted again on the entire upper triangle (training and validation data) and predictions are made on the lower triangle." (Härkönen MSc 2021, PDF p. 35, §3.2)); Schneider & Schwab 2025 ("Finally, we trained the model with the best hyperparameters on both the training and validation sets to predict the test set." (Schneider–Schwab 2025, PDF p. 35, Appendix B)); Avanzi et al. 2026 ("Following standard practice, after the best set of hyperparameters is obtained, we fix them and do one last training pass through the full training set to obtain the final model to use for testing." (Avanzi et al. 2026, PDF p. 23, §7.3)) |
| (c) Smoothed curve | $t^\star=\arg\min_t \bar V_w(t)$ with a moving average $\bar V_w(t)=\frac1w\sum_{s} V(s)$ over a window of $w$ epochs | Härkönen ("The number of epochs is then chosen by a simple central moving average with window size 100." (Härkönen MSc 2021, PDF p. 34, §3.2), $w=100$); Lindholm et al. 2020 (window 100; Appendix A); Gabrielli 2019 (21-epoch centred moving average; Appendix A) |
| (d) One $t^\star$ pooled over sub-portfolios | per-LoB optima $t^\star_m$ averaged, $t^\star=\frac1M\sum_m t^\star_m$, or one value "for simplicity" | Gabrielli 2019 ("The average of the ideal numbers of epochs for the M = 6 lines of business is 400, see the black dotted lines in Figure 2 and the last column of Table 7. Therefore, we decide to use 400 epochs of training for every line of business in our single NNDODP model. Note that one could choose line of business dependent numbers of epochs according to Table 7." (Gabrielli 2019, PDF p. 18, §3.2.1); per-LoB optima 1,000/500/0/500/300/100); Gabrielli et al. 2018 ("For this reason, we decide to run the gradient descent algorithm on the full data DI\|m for 300 iterations (for exactly this network architecture). Note that, for simplicity, we use 300 iterations for all LoBs." (Gabrielli et al. 2018, PDF p. 13, §3.3.2)) |
| (e) Epochs as one dimension of a grid or Bayesian search | $t$ fixed per configuration, chosen with the other hyperparameters | Yeldan & Karabey ("50, 100, 150, 200" (Yeldan–Karabey 2026, PDF p. 12, Table 1, "Epoch number")); Guo (epochs $\in\{500,1000\}$ as a cap; Appendix A); Usman ("E ∈ \[250, 450\], B ∈ \[75, 120\], ζ ∈ \[0.0097, 0.01\], p = 0.05, 0.10, 0.20," (Usman PhD 2024, PDF p. 159, eq. 4.24)) |
| (f) No early stopping: a fixed number of epochs | $t$ set by fiat or by "convergence" | Ramos-Pérez et al. 2020 ("The number of epochs is 10,000, and the batch size is equal to the length of the data used for training the ANN." (Ramos-Pérez et al. 2020, PDF p. 12, §3.3)); Noordhoek 2025 ("All networks are trained for 500 epochs, with a single iteration per epoch." (Noordhoek MSc 2025, PDF p. 40, §3.3)); Belabed et al. 2025 ("To make sure the model’s improved accuracy wasn’t just a fluke or caused by overfitting, we kept an eye on the training process for 500 full epochs." (Belabed et al. 2025, PDF p. 6, §IV.B.2)); Xu et al. 2019 ("We trained each model with a batch size of 500. Each model is trained for 300 epochs. Each epoch contains N/batch\_size steps where N is the number of rows in the training set." (Xu et al. 2019 CTGAN, PDF p. 8, §5.3)); Côté et al. 2025 ("We conducted the GAN training over 2 million iterations. This value was empirically determined based on obtained results. However, because of the known difficulty of training GANs (e.g., no stability guarantees), it could be adjusted depending on the configuration and the hyperparameters." (Côté et al. 2025, PDF p. 15, App. B.2)) |

**The reserving versions in detail.**

* *Gabrielli, Richman & Wüthrich (2018).* The problem is stated first: "A crucial question that has not been touched, yet, is how many iterations of the gradient descent algorithm we should perform." (Gabrielli et al. 2018, PDF p. 11, §3.3.1) "one of the reasons being that we only have (I + 1)I/2 = 78 observations in the upper triangle" (Gabrielli et al. 2018, PDF p. 11, §3.3.1) The answer is a split of the **claims** into two synthetic portfolios, "Therefore, we need to solve this problem in a more sophisticated way, namely, we choose training and validation sets by partitioning on the individual claims level such that both sets have (approximately) the same size (on a LoB level and on an accident year level)." (Gabrielli et al. 2018, PDF p. 11, §3.3.1) from which: "If we focus on the out-of-sample losses (red color), we notice that they seem to have a minimum after roughly 300 iterations (dotted vertical line). This suggests that the first 300 steps of the algorithm improve the predictive power of the bCCNN model, and \[...\] after that the algorithm starts to over-fit to the observations." (Gabrielli et al. 2018, PDF pp. 12–13, §3.3.2; "\[...\]" marks only the page break) The same count is then used on the full data and for every line of business, including one where validation showed no gain (Table 2 of the paper; Section 8).
* *Gabrielli (2019).* "The green vertical dotted lines indicate the ideal numbers of epochs for every line of business. The black vertical dotted lines indicate the average ideal number of epochs." (Gabrielli 2019, PDF p. 18, Figure 2 caption) then "The average of the ideal numbers of epochs for the M = 6 lines of business is 400, see the black dotted lines in Figure 2 and the last column of Table 7. Therefore, we decide to use 400 epochs of training for every line of business in our single NNDODP model. Note that one could choose line of business dependent numbers of epochs according to Table 7." (Gabrielli 2019, PDF p. 18, §3.2.1) with the argument "Hence, we assume that the average ideal number of epochs for the upper triangles is a good reference point for the lower triangles. Note that in the single NNDODP model the lines of business are modeled individually, but for the choice of the number of epochs all lines of business are considered simultaneously." (Gabrielli 2019, PDF p. 19, §3.2.1) Reserves are then averaged over the epochs around 400 (`HP-M17`).
* *Gabrielli (2020).* "In order to determine the numbers of epochs for the first training step, we randomly allocate 80% of the n individual claims to a training set and the remaining 20% to a validation set. We then train the neural network only using the training set. After every epoch, we calculate the value of the loss function (5.3) on the training set and the validation set." (Gabrielli 2020, PDF p. 18, §5.4) "The chosen numbers of epochs for the six LoBs are given on line (i) of Table 2, see also the green lines in Figure 4. Note that for simplicity we only consider numbers of epochs in {k · 10 \| k ∈ N}." (Gabrielli 2020, PDF p. 19, §5.4) and, because the curves are noisy, "In Figures 4 and 5 we observe that training and validation losses are rather erratic. In order to stabilize the results, we train the neural network for E + 2 epochs and determine the probability functions {pj (·)}j=0,...,J and the regression functions {µj (·)}j=0,...,J for all 5 numbers of epochs {E − 2, E − 1, E, E + 1, E + 2}." (Gabrielli 2020, PDF p. 19, §5.5)
* *Härkönen (2021).* "The only tuning parameter we consider here is the number of epochs. Models are fitted for 10 000 epochs and the training and validation losses are illustrated in Figure 8." (Härkönen MSc 2021, PDF p. 34, §3.2) "The number of epochs is then chosen by a simple central moving average with window size 100." (Härkönen MSc 2021, PDF p. 34, §3.2) "For most of the LoBs (except for 3 and 6) we choose number of epochs around 7 000." (Härkönen MSc 2021, PDF p. 35, §3.2)
* *Lindholm et al. (2020)* follow the same design, with a cap that binds: "For the number of epochs in training the neural networks, we set an upper limit at 10,000." (Lindholm et al. 2020, PDF p. 86, §4) "Almost all LoBs need close to the maximum of 10,000 epochs and allowing for more epochs may yield better results than those we will acquire. For the payment part of the model, the minimum losses are reached much earlier for most LoBs." (Lindholm et al. 2020, PDF p. 90, §4) They also say what the design lacks: "Still, given a sufficient amount of data you can always split your data set into three parts: one part used for training, one part used for determining the number of steps that the optimization procedure should be run, corresponding to a pseudo-validation data set, and a ﬁnal third sub-set used for proper out-of-sample validation once the model has been properly trained (without any prior peeking!)." (Lindholm et al. 2020, PDF p. 75, §3.2)
* *Al-Mudafer et al. (2021)* stop on a rolling-origin validation set (Section 4.4) with a very long patience: "The validation loss rarely decreased steadily, hence training was only stopped when it did not hit new lows in the last 1000 epochs. This is referred to as the patience measure in the Keras interface; a lower patience than 1000 would sometimes prematurely stop training." (Al-Mudafer et al. 2021, PDF p. 16, §4) "Training would usually last for several thousand epochs, with higher dropout rates and larger networks often requiring up to 10-15 thousand iterations. A 10000 epoch limit was set when running the hyper-parameter optimisation algorithm, in order to increase efficiency." (Al-Mudafer et al. 2021, PDF p. 16, §4)

**What goes wrong.**

1. *Transfer of $t^\star$ to more data.* Variants (b)–(d) find $t^\star$ on half (or 80 %) of the claims and then train on all of them. With full-batch training on a triangle, the loss surface changes with the data volume; with mini-batches of fixed size, the number of gradient steps per epoch changes too. [GBC] names exactly this ambiguity ("For example, there is not a good way of knowing whether to retrain for the same number of parameter updates or the same number of passes through the dataset." ([GBC] p. 249)). None of the papers checks it (Section 8).
2. *Pooling over lines of business.* An average $t^\star$ is optimal for none of the lines it averages; Gabrielli (2019) trains LoB 3, whose own optimum is 0 epochs, for 400.
3. *Binding caps.* When $t^\star$ equals $t_{\max}$ (Lindholm et al.: 9,357–9,950 of 10,000 in five of six LoBs; Gabrielli 2019: LoB 1 at the 1,000-epoch search limit), the "optimum" is the computing budget.
4. *Early stopping is not optional in [WM]/[AIT].* Variant (f) is a deliberate departure from both books, which say that minimising the training loss of a large network "is not a sensible problem that we should try to solve." ([AIT] p. 100)

### `HP-M14` Learning-rate adaptation during training

**What it is.** The learning rate $\eta_t$ changes with the training history instead of being tuned once. The forms found:

* *Reduce on plateau:* $\eta\leftarrow f\,\eta$ when $V$ has not improved for $p$ epochs. Richman & Wüthrich (2026a, b): "reduce learning rate on plateau, factor 0.9, patience 5" (Richman–Wüthrich 2026a, PDF p. 14, Table 4; the row label "Early stopping", batch size/epochs "4,096 and 1,000" and learning-validation split "9 : 1" are confirmed from the table image, PDF p. 14) (factor $f=0.9$, $p=5$). Kuo (2020): "For optimizing the neural network, we use stochastic gradient descent with an initial learning rate of 0.01 and a minibatch size of 100,000, and we halve the learning rate when there is no improvement in the validation loss for five epochs." (Kuo 2020 BMDN, PDF p. 19, Training and Scoring) Côté et al.'s autoencoder: "During the AE training, the learning rate was reduced by a factor 0.2 when the validation loss reached a plateau (tolerance of ) for 1,000 iterations (i.e., the patience)." (Côté et al. 2025, PDF p. 16, App. B.4)
* *Step decay:* $\eta_t=\eta_0\,\gamma^{\lfloor t/s\rfloor}$. Schneider & Schwab: "Specifically, we use the default settings and apply a learning rate decay every 10 epochs, using a multiplicative factor set to 0.1." (Schneider–Schwab 2025, PDF p. 32, Appendix B) Yu & Tomasi: "The initial learning rate was 10−2 , and the rate was divided by 10 after epoch 120 and 160. The parameter λ of weight decay is 10−4 ." (Yu–Tomasi 2019, PDF p. 8, Table 2 caption) Several chapters of Graziani & Xibilia, for example "In the ﬁrst step, we train the DCNet use the ship data set, we set the initial learning rates as 0.01 and decrease by one tenth per 10,000 iterations; after 50,000 iterations, the losses tend to stabilize." (Graziani–Xibilia (eds.) 2021, PDF p. 92, Ch. 5 §3.3)
* *Cosine annealing with restarts at each growth step:* "After each growth, the cycle in a standard cosine learning rate scheduler is reset as the number of epochs left" (Dong et al. 2020, PDF p. 6, §4.4)
* *Learning-rate range test:* Gridin uses PyTorch Forecasting's finder: "PyTorch Forecasting package defines the optimal learning rate for the current dataset:" (Gridin 2021, §19, Ch. 8 > A complete example)
* *Adaptive optimisers used instead of tuning the rate.* Andersen & Roed-Sørensen state the rationale, "Another upside to this approach, besides faster convergence, is that we do not need to manually tune the learning rate as it is now adapted." (Andersen–Roed-Sørensen MSc 2021, PDF p. 34, §2.6.4) and Qiu chooses a conjugate-gradient learner for the same reason: "Comparing SCG with the BA algorithm, we see that SCG outperforms BA because it does not need to adjust the learning rate continually." (Qiu MSc 2019, PDF p. 46, §3.2)

**What the textbooks say.** [GBC] gives the only concrete schedule: "In practice, it is common to decay the learning rate linearly until iteration τ:" ([GBC] p. 295) with $\epsilon_k=(1-k/\tau)\,\epsilon_0+(k/\tau)\,\epsilon_\tau$ for $k\le\tau$ (eq. 8.14), and "Usually τ may be set to the number of iterations required to make a few hundred passes through the training set." ([GBC] p. 295) "ετ should be set to roughly 1% the value of ε0. The main question is how to set ε0." ([GBC] p. 295) It chooses $\epsilon_0$ from the learning curves: "The learning rate may be chosen by trial and error, but it is usually best to choose it by monitoring learning curves that plot the objective function as a function of time. This is more of an art than a science, and most guidance on this subject should be regarded with some skepticism." ([GBC] p. 295) "Therefore, it is usually best to monitor the first several iterations and use a learning rate that is higher than the best-performing learning rate at this time, but not so high that it causes severe instability." ([GBC] p. 295) For the adaptive methods it concludes "Unfortunately, there is currently no consensus on this point." ([GBC] p. 309) [WM] asks only for "Under suitably tempered learning rates" ([WM] p. 279) and gives a momentum schedule: "Typically, one chooses the momentum coefficient ν in (7.24) time-dependent by setting νt = t/(t + 3)." ([WM] p. 287) [AIT]: "The learning rate and the momentum parameter are hyper-parameters that need to be fine-tuned by the modeler." ([AIT] p. 100)

**Note on a mislabelled table.** In both Richman & Wüthrich papers the table row headed "Early stopping" contains this plateau schedule. The plateau rule changes the learning rate; it does not stop training. In the second paper the stopping is done by a best-weights checkpoint visible only in Listing 5 (Appendix A).

### `HP-M15` Constructive growth and architecture search

**What it is.** The architecture itself is changed during or by an algorithm. Dong et al. grow a ResNet when a Lipschitz criterion fires: "After each epoch, it calculates the Lipschitz constant of the residual blocks and then decides whether it is the right timing to increase the depth. Such process is completely automated and requires no excessive and meticulous parameter tuning." (Dong et al. 2020, PDF p. 1, §1) with a single threshold "In our adaptive growing strategy, the tolerance rtol is the only hyper-parameter that needs to be tuned. It is typically chosen around 1.4, with only a marginal dependence on dataset8 ." (Dong et al. 2020, PDF p. 7, §5.2) ("1.4 for CIFAR and 1.3 for Tiny-Imagenet" (Dong et al. 2020, PDF p. 7, footnote 8)). Gridin reduces architecture search to hyperparameter search: "We can reduce neural network search to hyper-parameter optimization. Hyper-parameter can directly affect neural network topology." (Gridin 2021, §17, Ch. 6 > Neural Architecture Search) Fang et al. prune and regrow weights (dense–sparse–dense): "During training, we also use Dense-Sparse-Dense \[7\] to prune the weights of the neural network. As described in the original paper, a snapshot is taken at the end of the initial dense phase in which a minority selection of the smallest weights are frozen and zeroed." (Fang et al. 2022, PDF p. 3, §IV)

**What the textbooks say.** [WM] only points to the idea: "Recent research promotes the so-called Graph HyperNetwork (GHN) that is a (hyper-)network which tries to find the optimal network architecture and its parametrization by an additional network" ([WM] p. 290) [GBC] describes cheap screening of convolutional architectures with untrained features: "They argue that this provides an inexpensive way to choose the architecture of a convolutional network: first evaluate the performance of several convolutional network architectures by training only the last layer, then take the best of these architectures and train the entire architecture using a more expensive approach." ([GBC] p. 363) No reserving paper in the folder uses architecture search.

## Family IV: average instead of choosing (or choose the best run)

### `HP-M16` Ensembling over seeds or resamples (nagging, bagging, deep ensembles)

**What it is.** Fit the same configuration $M$ times with different seeds (nagging) or on resampled data (bagging) and average the predictions,
$$\bar\mu^{(M)}(\boldsymbol x)=\frac1M\sum_{m=1}^M\hat\mu^{(m)}(\boldsymbol x).$$
It turns the seed from a hyperparameter into a nuisance to be averaged out, and it introduces a new hyperparameter, $M$.

**What the textbooks say.**

* [WM] proves that averaging helps, "Proposition 7.25 says that aggregation works, i.e., aggregating i.i.d. predictors leads to monotonically decreasing expected deviance GLs." ([WM] p. 327) "Thus, at this stage, aggregating is a variance reduction technique." ([WM] p. 327) and gives three answers for $M$ depending on the target: "This now explains why we choose M = 1" ([WM] p. 323) (the sentence continues with ",600 SGD runs": $M=1{,}600$ brings one policy's coefficient of variation from 40 % to 1 %); "After the first 10 steps the picture starts to stabilize which indicates that for this size of portfolio (and this type of problem) we need to average over roughly 10–20 FN networks to receive optimal predictive models on the portfolio level." ([WM] p. 328) and, in Chapter 11, "The nagging predictors over 100 seeds are roughly the same as over 20 seeds (see Table 11.3), which indicates that 20 different network fits suffice, here." ([WM] p. 493)
* [AIT]: "the nagging predictor robustifies the best-estimate prediction" ([AIT] p. 108) "a good value for M is in the range of 10 to 20" ([AIT] p. 109) "with M = 10 or M = 20, this will significantly improve the predictive model." ([AIT] p. 109)
* [GBC]: "Neural networks reach a wide enough variety of solution points that they can often benefit from model averaging even if all of the models are trained on the same dataset." ([GBC] p. 257) "Model averaging is an extremely powerful and reliable method for reducing generalization error. Its use is usually discouraged when benchmarking algorithms for scientific papers, because any machine learning algorithm can benefit substantially from model averaging at the price of increased computation and memory." ([GBC] p. 258) "It is common to use ensembles of five to ten neural networks—Szegedy et al. (2014a) used six to win the ILSVRC— but more than this rapidly becomes unwieldy." ([GBC] p. 258)
* [H] has only the reserving analogue, averaging across methods: "some practitioners combine the results produced by the different methods using some form of simple or weighted averaging to produce the selected ultimate." ([H] p. 334)

**Who used it, and how $M$ was chosen.**

| Paper | $M$ | How $M$ was chosen |
|---|---|---|
| Richman & Wüthrich 2026a, b | 10 | fixed ("10 network fits with different seeds" (Richman–Wüthrich 2026a, PDF p. 14, Table 4); "Because network fitting involves many elements of randomness, e.g., the initialization of the SGD algorithm, we always ensemble over 10 balance corrected predictors (4.2) being received from the same SGD algorithm but with different seeds for initialization; see Richman–Wüthrich \[16\]." (Richman–Wüthrich 2026a, PDF p. 14, §4.2.3)) |
| Richman et al. 2025 PIN (code) | 10 | fixed (seeds 100–109; Section 7) |
| Kuo 2020 | 10 | fixed ("Since there is randomness in the neural network weight initialization, we instantiate and train the model 10 times, and take the average of the predicted future paid losses across the 10-model ensemble." (Kuo 2020 BMDN, PDF p. 22, Aggregate estimates)) |
| Ramos-Pérez et al. 2022 | 20 | fixed ("As shown in Fig. 1, once the model inputs are prepared, 20 Recurrent Neural Networks composed of several Fully Connected (FC) and Long–Short Term Memory (LSTM) layers (Fig. 2) are fitted. The number of Recurrent Neural Networks fitted is high enough to obtain the average model prediction regardless their initial weights. This strategy was also applied by Kuo (2018)." (Ramos-Pérez et al. 2022, PDF p. 4, §3.2)) |
| Zelený 2026 | 20 | fixed ("In the implementation, K = 20 seeds are used for both the claim-level NN pipeline and the triangle-based NN." (Zelený MSc 2026, PDF p. 48, §4.6)) |
| Härkönen 2021 | 20 | side check only ("neural network model for 20 different seeds to get a more stable prediction by taking the mean of the predicted reserves." (Härkönen MSc 2021, PDF p. 39, §3.2)) |
| Cai 2021 | 100 | fixed ("We run the DeepTriangle 100 times and use the average as the predicted reserve." (Cai MSc 2021, PDF p. 15, §1)) |
| Al-Mudafer et al. 2021 | 5 | fixed ("MDN with hyper-parameters θ min is fit 5 times on the training data of Partition 3, under different weight initialisations. The 5 fitted distributions are ensembled to produce the final forecast." (Al-Mudafer et al. 2021, PDF p. 17, §4.3)) |
| Yeldan & Karabey 2026 | up to 50 | shown to stabilise on the **test** set, not selected ("Overall, the testing loss curves gradually converge to stable values as M increases, indicating that the nagging approach reduces the variability caused by random initialization and leads to more robust predictive performance." (Yeldan–Karabey 2026, PDF p. 14, §3.3)) |
| Guo 2026 | 10–20 | Kuo replication ("Neural-network ensembles can also reduce point-estimate variance—in our Kuo replication, ensembling 10–20 models lowered MAPE from 9.13% to 8.32%" (Guo 2026, PDF p. 21, §6.2)) |
| Gorishniy et al. 2025 (TabM) | $k=32$ implicit members | heuristic ("Hyperparameters. Compared to MLP, the only new hyperparameter of TabM is k — the number of implicit submodels. We heuristically set k = 32 and do not tune this value." (Gorishniy et al. 2025 TabM, PDF p. 6, §3.3)); studied after the fact ("Second, too high values of k can be detrimental." (Gorishniy et al. 2025 TabM, PDF p. 10, §5.3)) |
| Ferrario et al. 2020 | several architectures blended | "In fact, this averaging/blending seems a fairly efficient way to improve network models and to eliminate the variability introduced by different seeds and early stopping of gradient descent algorithms" (Ferrario et al. 2020, PDF p. 54, §6.6) |
| Schneider & Schwab 2025 | 100 bootstrap refits | bagging ("We first generate 100 bootstrapped datasets from our original training and validation dataset." (Schneider–Schwab 2025, PDF p. 21, §6.2)) |

No paper chooses $M$ from a stability criterion of the kind [WM] uses. The one that plots it (Yeldan & Karabey) plots it on test data.

### `HP-M17` Snapshot (epoch) averaging

**What it is.** Average the predictions of *one* training run over neighbouring epochs instead of choosing a single $t^\star$:
$$\hat R=\frac{1}{2k+1}\sum_{e=t^\star-k}^{t^\star+k}\hat R^{(e)}.$$
It is used only in the Gabrielli line, as a response to dropout-induced noise in the validation curve: "Similarly as in the single NNDODP model, in order to get meaningful and stable results, we calculate the multiple NNDODP reserves given in (4.1) for all numbers of epochs in {390, . . . , 400, . . . , 410}, and then we take the average of these 21 values." (Gabrielli 2019, PDF p. 26, §4.2.2) (epochs 390–410, $k=10$), and "In Figures 4 and 5 we observe that training and validation losses are rather erratic. In order to stabilize the results, we train the neural network for E + 2 epochs and determine the probability functions {pj (·)}j=0,...,J and the regression functions {µj (·)}j=0,...,J for all 5 numbers of epochs {E − 2, E − 1, E, E + 1, E + 2}." (Gabrielli 2020, PDF p. 19, §5.5) ($k=2$). The thesis makes the link to ensembling explicit: "Note that this strategy is similar in spirit to neural network ensembles, where one trains multiple neural networks and considers the average predictions in order to reduce the variance and increase the stability of the neural network predictions, see \[27\]." (Gabrielli PhD 2020, PDF p. 195, Paper D §3.2.2, thesis-only) The closest textbook device is Polyak averaging of the parameter iterates: "As a result, when applying Polyak averaging to non-convex problems, it is typical to use an exponentially decaying running average:" ([GBC] p. 322)

### `HP-M18` Bayesian treatment of weights or hyperparameters

**What it is.** Put a prior on the weights (and possibly on its scale) and average over the posterior, so that the regularisation strength is part of the model rather than a tuned constant. With a Gaussian prior $\vartheta\sim\mathcal N(0,\sigma_w^2 I)$ the MAP estimate is ridge regression with penalty weight proportional to $1/\sigma_w^2$: "MAP Bayesian inference with a Gaussian prior on the weights thus corresponds to weight decay." ([GBC] p. 139); in [AIT], "the penalty term in (2.24) can be interpreted as a Gaussian prior distribution on the parameter" ([AIT] p. 54)

**Who used it.**

* Kuo (BMDN): "We choose Gaussians for both the prior and surrogate posterior distributions over the weights of the dense layers. The prior distribution is constrained to have zero mean and" (Kuo 2020 BMDN, PDF p. 15, Dense Variational Layer; the sentence continues on p. 16) "unit variance while for the surrogate posterior both the mean and variance are trainable." (Kuo 2020 BMDN, PDF p. 16, Dense Variational Layer) Only the two output layers are variational (Appendix A).
* Pittarello et al.: "In a first place, we choose a variational inference approach to quantify uncertainty over the model weights. Indeed, the Bayes by Backprop algorithm presented in \[1\], will be adapted to our framework." (Pittarello et al. 2022, PDF p. 6, §4.2) The prior is never specified numerically (Appendix A).
* Andersen & Roed-Sørensen, with hyperpriors: "We may then wish to treat these values as unknown hyperparameters, giving them a higher-level broad prior distribution, which we call a hyper-prior." (Andersen–Roed-Sørensen MSc 2021, PDF p. 78, §4.6) "One benefit of such models is that the appropriate degree of regularization for the task can be determined automatically from the data, see MacKay (1991) and MacKay (1992)." (Andersen–Roed-Sørensen MSc 2021, PDF p. 79, §4.6) Their hyperprior values were themselves chosen by trying: "After experimenting with different choices of parameters for the hyper-prior, we choose α = 0, β = 1 and ν = 1. All BNN models have 10 hidden neurons and use ReLU in the hidden layer for ease of comparison" (Andersen–Roed-Sørensen MSc 2021, PDF p. 88, §5.1.2)
* Wüthrich (2017) names it as the route not taken: "A straightforward idea is to use Bayesian methods, however, also here we face the curse of dimensionality which may result in Markov chain Monte Carlo simulations that are far too time consuming." (Wüthrich 2017, PDF p. 15, §6)

### `HP-M19` Best-of-N seeds or restarts

**What it is.** Train $N$ runs and keep the one with the best score. It is the opposite of `HP-M16` and, if the score is a validation score, it selects on noise.

**Who used it.** Rügamer et al.: "While we test gamlss.mx with a fixed budget of 20 restarts, we compare these results to NMDR using 1 and 3 random initializations to assess the effect of multiple restarts. Each experimental configuration is replicated 10 times." (Rügamer et al. 2023, PDF p. 13, §4.3) and "Note that the best model for NMDR with multiple restarts is chosen based" (Rügamer et al. 2023, PDF p. 14, §4.3.1) … "on the in-sample log score which does not necessarily imply better out-of-sample performance compared to a single optimization run." (Rügamer et al. 2023, PDF p. 15) Usman: "Each grid search model is repeated 10 times, and the best model is selected if the epoch history shows convergence and the PM MSE is minimum, highlighted in yellow." (Usman PhD 2024, PDF p. 166, Table 4.2 caption) Côté et al.: "Because of the GANs’ lack of stability (even for the same hyperparameters and configuration), this best combination of hyperparameters was trained at least two more times with different seeds for the random number generator. We saved the model of whichever run gave the best results and used it for the final results." (Côté et al. 2025, PDF p. 16, App. B.3)

**What the textbooks say.** [WM] argues against: "However, this slight improvement in the performance should not be overstated" ([WM] p. 300) "and choosing a different seed may change the results." ([WM] p. 300) "Firstly, we have seen that there is no best network regression model even if the architecture and the hyper-parameters are fully specified." ([WM] p. 492) So does [AIT]: "Based on a finite sample there is no (absolute) best selection, we can only distinguish clearly better from clearly worse models." ([AIT] p. 96) Guo's multi-seed check shows the effect in reserving data (`HP-M08`).

## Family V: structural devices that pin or remove a hyperparameter

### `HP-M20` Initialisation at a fitted classical model

**What it is.** The network is written as a classical model plus a correction, and the correction's output weights start at zero, so that gradient descent starts *exactly* in the classical model:
$$\mu(\boldsymbol x)=\exp\big\{\langle\hat{\boldsymbol\beta}^{\mathrm{GLM}},\boldsymbol x\rangle+\langle\boldsymbol w,\boldsymbol z^{(d:1)}(\boldsymbol x)\rangle\big\},\qquad \boldsymbol w^{(0)}=\boldsymbol 0 .$$
It fixes the initialisation by construction (no seed-dependent start for the output layer), and it changes what early stopping does: by [GBC]'s equivalence (p. 252), stopping after $\tau$ steps shrinks the fit towards the *starting point*, i.e. towards the chain ladder / GLM rather than towards zero.

**What the textbooks say.** [WM] describes the start, in which the network part is switched off, "that is, initially, no signals traverse the FN network part because we set" ([WM] p. 317) $\boldsymbol w=\boldsymbol 0$; if gradient descent then cannot improve on the start, "otherwise the GLM is already good (enough)." ([WM] p. 318) The practical benefit: "A first observation is that using model Poisson GLM3 as an offset reduces the run time of gradient descent fitting because we start the algorithm already in a reasonable model." ([WM] p. 318) [AIT]: "We recommend to initialize the network weights so that the SGD algorithm precisely starts in the MLE fitted GLM (5.25)." ([AIT] p. 114)

**Who used it.**

* Gabrielli, Richman & Wüthrich: "Namely, we choose it such that the optimization algorithm exactly starts in the ccODP regression model." (Gabrielli et al. 2018, PDF p. 10, §3.2) "If the ccODP model is close to optimal, then we expect fast (near) convergence of the gradient descent algorithm because only a few gradient steps are necessary." (Gabrielli et al. 2018, PDF p. 10, §3.2)
* Gabrielli (2019): "In our case the skip connections ensure (together with the initialization of the neural network parameters) that the single NNDODP model exactly starts in the ccODP" (Gabrielli 2019, PDF p. 14, §3.1.4) and in the abstract "Moreover, this choice of neural network initialization guarantees stability and accelerates representation learning." (Gabrielli 2019, PDF p. 1, Abstract)
* Gabrielli (2020), at the homogeneous model: "This initialization implies that we start from the homogeneous model not considering any covariate information." (Gabrielli 2020, PDF p. 15, §5.1)
* Härkönen: "We want the model to start exactly at the ODP reserving model and thus choose the initial value Θ̂0 as follows:" (Härkönen MSc 2021, PDF p. 17, §2.3.3.4)
* Al-Mudafer et al.'s ResMDN: "These parameters, representing the weights in the final hidden layer, are initialised at 0" (Al-Mudafer et al. 2021, PDF p. 9, §2.4.2) "This initialisation follows the methodology of Gabrielli, Richman and Wüthrich (2020) closely." (Al-Mudafer et al. 2021, PDF p. 9, §2.4.2)
* Bücher & Rosenstock, at a global estimate: "This is useful for choice of initial values based on a global estimate θ̂ during neural network initialization." (Bücher–Rosenstock 2022, PDF p. 4, Appendix A)
* Noordhoek turns the degree of initialisation into a hyperparameter $\omega\in[0,1]$: "Here, the GLM parameters are partially included in the initialization, with a fixed weight ω ∈ (0, 1) determining the relative influence of the GLM parameters." (Noordhoek MSc 2025, PDF p. 39, §3.2) and chooses $\omega_{\mathrm{start}}=0.5$ in-sample ("The best performance is achieved when the initialization weight is set to ωstart = 0.5, again with minimal difference between the trainable and nontrainable settings." (Noordhoek MSc 2025, PDF p. 56, §4.2)). Without the classical start the network did not learn the pattern: "We conclude that in the absence of a prior structure, the Neural Network fails to learn the intricate claims development pattern in the data." (Noordhoek MSc 2025, PDF p. 43, §4.1)

### `HP-M21` Warm start, fine-tuning and transfer of tuned values

**What it is.** A network (or a set of tuned hyperparameters) obtained on one data set is reused on another: bootstrap or synthetic replicates, a private version of the model, a larger version of the data, or other triangles from the same environment.

**Who used it.**

* Warm start of replicates: "To reduce training costs, we pre-train DT on observed incremental paid losses and fine-tune the model weights on synthetic incremental paid losses, significantly improving computational efficiency." (Cai et al. 2025, PDF p. 3, §1) and "To reduce the computational expense associated with EDT, stemming from training numerous DTs for GAN samples, we leverage the trained model on observed data to fine-tune weights for new samples." (Cai et al. 2025, PDF p. 12, §3.3)
* Gabrielli et al.'s bootstrap reuses the tuned architecture and step count for every replicate: "That is, we choose the same network architecture as above, we initialize the gradient descent algorithm with the ccODP model estimates from the bootstrap samples, and then we run 300 gradient descent steps." (Gabrielli et al. 2018, PDF p. 15, §3.3.4)
* Transfer to a related configuration: "In all cases, we conducted tuning in a nonprivate way" (Côté et al. 2025, PDF p. 16, App. B.3) and "Note that, except for the types of features, the baseline and all\_cat configurations share the same hyperparameters, because using the values of the first on the second gave good results." (Côté et al. 2025, PDF p. 16, App. B.4)
* Transfer to larger data: "When running models on the large versions of the datasets, we reused the hyperparameters tuned for their small versions." (Gorishniy et al. 2025 TabM, PDF p. 19, §D.4)
* Transfer across triangles: "The hyper-parameter selection algorithm was only run on a single triangle from each environment. The chosen model for that triangle was used to fit all 50 triangles of that environment. This was done to increase the efficiency of modelling." (Al-Mudafer et al. 2021, PDF p. 36, App. D) and "Once a hyperparameter combination has been chosen, that combination is then used for training and evaluating the model on each of the fifty datasets." (Avanzi et al. 2025, PDF p. 14, §4) with the reason "Firstly, there would be significant runtime challenges if tuning were to be conducted on each of the fifty datasets independently." (Avanzi et al. 2025, PDF p. 14, §4)
* Guo, by contrast, *declines* to transfer across lines of business: "The best values differed materially across the LOBs, so hyperparameters should be tuned per business line." (Guo 2026, PDF p. 20, §6.2)

**What the textbooks say.** Only [GBC], for pretraining: "The most principled approach is to use validation set error in the supervised phase in order to select the hyperparameters of the pretraining phase, as discussed in Larochelle et al. (2009)." ([GBC] p. 535)

### `HP-M22` Empirical-null input selection (LocalGLMnet)

**What it is.** The number and identity of inputs (and hence the input dimension $q_0$) is chosen by a significance test against a purely random control variable. Add $x_{q+1}$ independent of everything, fit, estimate the spread $\hat s$ of its attention weights $\hat\beta_{q+1}(\boldsymbol x_i)$, and keep variable $j$ only if its attention weights leave the interval $I_\alpha=[\,q_N(\alpha/2)\,\hat s,\ q_N(1-\alpha/2)\,\hat s\,]$ often enough.

**Who used it.** Richman & Wüthrich (2021): "If we are given a statistical problem with features x = (x1 , . . . , xq )> ∈ Rq , we propose to extend these features by an additional variable xq+1 which is completely random, independent of x and which, of course, does not enter the true (unknown) regression function µ(x) but is only included within the network." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 11, §3.2) "We choose significance level α = 0.1% which provides us with qN (0.05%) = 3.2905." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 11, §3.2) The test is followed by a refit: "In a final step, the model with dropped components should be re-fitted and the out-of-sample loss should not substantially change, this re-fitting step verifies that the dropped components also do not play a significant role in the regression attentions βbj (x) of the remaining feature components j, i.e., contribute by interacting with other variables." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 11, §3.2) Its outcome was overridden once: "For these two variables, Iα provides a coverage ratio of 97.1% and 98.1%, thus, strictly speaking these numbers are below 1 − α = 99.9% and we should keep these variables in the model." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 17, §3.4) followed by "Thus, we drop the variables Area Code and VehPower, and we also drop the control variables RandU and RandN, because these are no longer needed." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 17, §3.4)

**What the textbooks say.** [WM]: "Since this additional component is independent of all other components it cannot have any predictive power for the response under consideration" ([WM] p. 498) [AIT]: "For this, we add a purely random covariate component" ([AIT] p. 113)

### `HP-M23` Information criteria and regularisation paths

**What it is.** Choose by $\mathrm{AIC}=-2\ell(\hat\vartheta)+2p$ or $\mathrm{BIC}=-2\ell(\hat\vartheta)+p\log n$, or along a path of penalty values. **No network paper in the folder selects a network hyperparameter by AIC or BIC**, and both actuarial textbooks say why not: "Remark that AIC values within FN networks are not supported by any theory as we neither use the MLE nor do we have a reasonable evaluation of the number of parameters involved in networks." ([WM] p. 338) "In networks we should not use AIC as we neither have a parsimonious network parameter nor do we use the MLE." ([WM] p. 464) "Remark that these model selection criteria may not be valid in machine learning models, such as neural networks, as these models do not use MLE for model fitting." ([AIT] p. 31) "Therefore, AIC and BIC are mainly useful tools for model selection among GLMs supposed they were fitted with MLE." ([AIT] p. 31) [H] uses AIC and BIC for GLM reserving models only: "standard statistical goodness-of-fit tests such as Akaike Information Criterion and Bayesian Information Criterion." ([H] p. 190)

The only path-type device is Rügamer et al.'s entropy penalty $\xi$ on the mixture weights: "In practice, an appropriate amount of penalization can be found by running cross-validation along a grid of different 𝜉 values as, e.g., done for the Lasso (Tibshirani 1996)." (Rügamer et al. 2023, PDF p. 18, §4.5.1) Their "best" value is judged against the known truth of a simulated example (Section 4.5).

## Family VI: assessment and reporting after the fact

### `HP-M24` Sensitivity analysis and ablation

**What it is.** Hyperparameters are varied after the model is chosen, to show robustness or the contribution of a component. It does not select anything, but it is the only evidence many papers give that the chosen values do not matter much.

**Examples.**

* Seeds: "the results of the single NNDODP model in Table 8 were calculated using a (random) Keras seed, see Listing 1. We wonder what happens if we choose a different seed. Therefore, we apply the single NNDODP model to the 100 randomly chosen Keras seeds given in Listing 7." (Gabrielli 2019, PDF p. 20, §3.2.2) then "We see that for almost all seeds we stay within the blue lines, thus, improving the CL results. For most seeds we even observe a substantial improvement, even though we did not perform separate seed-dependent model selections as in Section 3.2.1." (Gabrielli 2019, PDF p. 20, §3.2.2) Gabrielli (2020): "As a second stability check we repeat the second training step for 100 different seeds, always using the number of epochs E given on line (i) of Table 3 and averaging over {E −2, E −1, E, E +1, E +2}." (Gabrielli 2020, PDF p. 23, §6.1) Ferrario et al.: "From this plot we conclude that there are quite some differences between different seeds, and it is worth to explore different initial configurations." (Ferrario et al. 2020, PDF p. 28, §4.5)
* Ablation with re-tuning per variant (the correct design): "When designing a complex neural network model one is well advised to perform an ablation study in order to check the contribution of individual model parts." (Gabrielli PhD 2020, PDF p. 198, Paper D §3.2.4, thesis-only) "In particular, for all of these four models we separately select the numbers of neurons in the K “ 2 hidden layers and the number of epochs using the procedure described in Section 3.2.1" (Gabrielli PhD 2020, PDF p. 198, Paper D §3.2.4, thesis-only)
* Depth: "Thus, Table 7 compares the configuration selected for the Stacked-ANN model in this paper with two alternative configurations: ANNs composed of one and three hidden layers with five neurons each." (Ramos-Pérez et al. 2020, PDF p. 20, §4.3) (judged against the true reserves, Section 4.5).
* Trial budget: "Results show that compared with our standard setting of 100 tuning trials, 50 trials are insufficient for effective tuning, whereas increasing the number of trials beyond 100 does not yield further improvement." (Ye et al. 2025, PDF p. 40, Table 4 caption)
* Optimiser benchmark: "In order to provide insights into the various optimizers’ performance, we conduct a small benchmark study to assess the influence of the choice of an optimizer and to find a good default." (Rügamer et al. 2023, PDF p. 20, App. A)

**What the textbooks say.** [WM] quantifies seed sensitivity for a whole portfolio (p. 323): "The average coefficient of variation is roughly 10% (orange horizontal line, lhs)." ([WM] p. 323) [H], for reserving models generally: "Approaches to determining the potential impact of model error include reviewing the sensitivity of results to alternative underlying models, taking weighted results from different models" ([H] p. 150)

### `HP-M25` Post-hoc importance and pattern analysis of a search

**What it is.** After a search, the results are themselves modelled or inspected to learn which hyperparameters matter. Guo fits a random forest to the search results: "Each configuration was trained once (single seed) in the screening stage. A Random Forest regressor (Breiman 2001) was fitted to predict MAPE from the 6 hyperparameters, and its impurity-based feature importance was used as a descriptive ranking of the hyperparameters within the Phase 2 search space." (Guo 2026, PDF p. 15, §4.4) "Figure 5 shows that learning rate (46.4%) and dropout rate (26.7%) were the two dominant features, together accounting for over 73% of the impurity-based feature importance." (Guo 2026, PDF p. 17, §5.2) with the caveat "These feature-importance values should be read as a descriptive decomposition from the fitted Random Forest surrogate, not as causal effects of the hyperparameters." (Guo 2026, PDF p. 18, §5.2) Gridin reads the top trials: "The top 10 results are very close to each other, and it would be reasonable to analyze what the best trials have in common." (Gridin 2021, §17, Ch. 6 > Hybrid models > Hybrid model architecture search) No textbook describes this; it is the natural companion of `HP-M08` and `HP-M09`.

### `HP-M26` Visual reading of loss curves

**What it is.** $t^\star$, or a set of finalists, is read off a plot by eye. In early stopping: "If we focus on the out-of-sample losses (red color), we notice that they seem to have a minimum after roughly 300 iterations (dotted vertical line). This suggests that the first 300 steps of the algorithm improve the predictive power of the bCCNN model, and \[...\] after that the algorithm starts to over-fit to the observations." (Gabrielli et al. 2018, PDF pp. 12–13, §3.3.2; "\[...\]" marks only the page break); "The validation losses (in red) in Figure 5 are rather erratic, and slightly smaller or bigger numbers of epochs can also be justified." (Gabrielli 2020, PDF p. 22, §6.1); Ferrario et al. read the range off a *test* curve, "Thus, in view of Figure 14 (lhs), the GDM should be early stopped after roughly 150 to 200 epochs, because in later epochs the GDM learns the noisy part in the learning data D, and not real model structure." (Ferrario et al. 2020, PDF p. 29, §5.1) For GANs, where no validation likelihood exists, Côté et al. screen by the shape of the curves: "The performance evaluation of the GAN was not as straightforward as that of the AE. The losses of both the discriminator and the generator were plotted." (Côté et al. 2025, PDF p. 16, App. B.3) "For the generator, a loss oscillating rather slowly around 0 (going positive for many thousands of iterations and then going negative, and so on) appeared a good indicator of performance." (Côté et al. 2025, PDF p. 16, App. B.3)

**What the textbooks say.** [GBC] uses learning curves for exactly one decision, the initial learning rate: "If it is too large, the learning curve will show violent oscillations, with the cost function often increasing significantly. Gentle oscillations are fine, especially if training with a stochastic cost function such as the cost function arising from the use of dropout." ([GBC] p. 295)

### `HP-M27` Not stated

**What it is.** The value, or the way it was chosen, is not in the document. 44 of the 50 network documents leave at least one in-scope hyperparameter unreported (Table 2.1). The most frequent gaps: the learning rate (often hidden in a library default), the batch size, the number of epochs when early stopping is used, the seed, and the final values after a search. Some documents report nothing reproducible at all: Avanzi et al. (2026) name the hyperparameters they tuned, "The FNN hyperparameters that we tune are: the number of hidden layers and how many nodes are in each hidden layer, the batch size, the dropout rate, and the learning rate. The validation procedure for tuning hyperparameters is described in section 5.2." (Avanzi et al. 2026, PDF p. 36, App. B.2) but give no values or search method; Belabed et al. report only the number of spline layers and epochs; Mahohoho et al. report no network hyperparameter at all; Pittarello et al. list candidates but not the selected values (Appendix A).

# Selection signals: what score, on what data

A method (Section 3) says how candidate values are generated; a **signal** says what they are compared on. For reserving the signal matters more than the method, because the quantity of interest (the lower triangle) lies in calendar years that no split of the upper triangle contains.

**Table 4.1 – Selection signals.** Counts are network documents in which the signal drives at least one in-scope choice (a document can use several).

| Code | Signal | Network documents (examples) | Textbook position |
|---|---|---|---|
| `HP-V1` | random hold-out **inside** the observed data (claims, records or cells) | Wüthrich 2017; Gabrielli et al. 2018; Gabrielli 2019, 2020; Härkönen; Lindholm et al.; Kuo 2020; Cai et al.; Schneider & Schwab; Nicholas; Ferrario et al.; Richman & Wüthrich 2021; Rügamer et al.; Ye et al.; Gorishniy et al.; Côté et al. | the default in [GBC] (80/20, p. 121), [WM] (U/V/T, p. 290) and [AIT] (10–20 %, p. 103) |
| `HP-V2` | hold-out **by time** (latest calendar periods or settlement dates) | Avanzi et al. 2025; Guo 2026 (for early stopping); Ramos-Pérez et al. 2020 (last observed diagonal); Zelený 2026 (by Keras row order, Section 7) | none of the four books discusses it for networks |
| `HP-V3` | $K$-fold cross-validation | Yeldan & Karabey (5-fold); Hiabu et al. (3-fold); Usman (5-fold); Mulquiney (unspecified) | $K=10$ in [WM] (p. 101) and [AIT] (p. 29); Algorithm 5.1 in [GBC] (p. 123); [AIT] restricts it to smaller problems (p. 33); [WM] never applies it to networks |
| `HP-V4` | rolling origin / back-test over several calendar periods | Al-Mudafer et al.; Avanzi et al. 2026; Zelený (pipeline settings) | [H]: remove a diagonal (p. 314), back-testing (pp. 318–319), A vs E (pp. 353–355) |
| `HP-V5` | the **test set or the known truth** | 10 documents confirmed, 3 possible (Section 4.5) | forbidden in [GBC] (p. 121); [AIT] selects between model classes on $\mathcal T$ (p. 28) |
| `HP-V6` | in-sample (training) loss only | Noordhoek; Rügamer et al. (restarts); Yu & Tomasi (one learning rate); Swallow | – |
| `HP-V7` | reserve-level criterion (total OCL, AvE, CDR) | Avanzi et al. 2026; Nicholas (evaluation); without a network: Balona & Richman, Mayr, Jin | [H] A vs E (pp. 353–355) |
| `HP-V8` | probabilistic score (NLL, log score, partial likelihood) | Al-Mudafer et al.; Hiabu et al.; Kuo 2020; Yeldan & Karabey (nagging display); without a network: Avanzi et al. 2024 | [AIT]: use a strictly consistent loss (p. 23) |
| `HP-V9` | other (sample fidelity for GANs, Lipschitz constant, validation–training gap) | Côté et al.; Swallow; Xu et al.; Dong et al.; Yeldan & Karabey | [GBC]: update-to-parameter ratio ≈ 1 % (p. 440) |
| `HP-VX` | not stated | Belabed et al.; Mahohoho et al.; Gueye et al.; Pittarello et al. (candidates only) | – |

## `HP-V1` Random hold-out inside the upper triangle

**The textbook default.** [GBC]: "Typically, one uses about 80% of the training data for training and 20% for validation." ([GBC] p. 121) and "Since the validation set is used to “train” the hyperparameters, the validation set error will underestimate the generalization error, though typically by a smaller amount than the training error. After all hyperparameter optimization is complete, the generalization error may be estimated using the test set." ([GBC] p. 121) [WM]: "Thus, for FN network fitting with early stopping we need a reasonable amount of data that can be split into 3 sufficiently large data sets so that each is suitable for its purpose." ([WM] p. 290) [AIT]: "Often one takes 20% or 10% of the learning data L as validation sample V, depending on the sample size n." ([AIT] p. 103) All three assume the observations are exchangeable. [AIT] says so explicitly about its learning and test samples: "These two samples should be mutually independent, and contain i.i.d. data" ([AIT] p. 28)

**The reserving version: split the claims, not the cells.** A triangle has 55–78 cells, too few to hold any out. The ETH line therefore splits the *individual claims* into two portfolios, builds a triangle from each, and uses one for training and the other for validation: "Therefore, we need to solve this problem in a more sophisticated way, namely, we choose training and validation sets by partitioning on the individual claims level such that both sets have (approximately) the same size (on a LoB level and on an accident year level)." (Gabrielli et al. 2018, PDF p. 11, §3.3.1) Gabrielli (2019) adds why the halves must be equal: "We remark that the training data and the validation data need to be chosen of the same size since the ccODP model parameters implicitly consider the volumes of the underlying portfolio" (Gabrielli 2019, PDF p. 17, §3.2.1) The thesis acknowledges the limitation: "We recognize that actuaries often only see aggregate triangles and, thus, this approach of splitting the claims on an individual level can present a practical difficulty." (Gabrielli PhD 2020, PDF p. 192, Paper D §3.2.1, thesis-only) Lindholm et al. use the same design and add a caution: "It is important that the mechanism used for splitting the original data sets into sub-sets does not create severe imbalances in terms of overall exposures per accident year." (Lindholm et al. 2020, PDF p. 76, Remark 5(c))

**Why it is an interpolation signal.** Both halves contain the same accident and development years. The validation loss therefore measures how well the network fits the *upper* triangle of an independent portfolio with the same claims process; it does not measure extrapolation to later calendar years. Gabrielli, Richman & Wüthrich found exactly this gap, in the favourable direction: "Thus, the neural network boosting improvement has been successful in all LoBs here, even though the initial out-of-sample validation analysis in the upper triangles of Section 3.3.2 has not been suggesting this for the LoBs 3 and 6." (Gabrielli et al. 2018, PDF p. 14, §3.3.3) Other random splits in the folder: "Firstly, we have split the corresponding claims into a learning data set and a test data set. For the test data set we have chosen at random 10% of the individual claims and the remaining 90% of the individual claims were allocated to the learning data set." (Wüthrich 2017, PDF p. 8, §3.3) "We use a random subset of the training set consisting of 5% of the records as the validation set for determining early stopping and scheduling the learning rate." (Kuo 2020 BMDN, PDF p. 19, Training and Scoring) "The training data is randomly split into training and validation sets using an 80-20 split. When splitting, the training data corresponding to the same accident year and development year from different companies stay in the same training or validation sets." (Cai et al. 2025, PDF p. 7, §2.2) "Further, we split the claims inside the training data randomly into the final training and validation sets.7 To be more precise, 80% of these data are used for model training, while the remaining 20% are used for model validation to evaluate the model's performance and generalizability." (Schneider–Schwab 2025, PDF p. 10, §3.2)

**The Keras trap.** `fit(..., validation_split = v)` does **not** draw a random subset: Keras takes the *last* fraction $v$ of the rows supplied, before any shuffling. Whether that is a random, a temporal or an arbitrary hold-out depends on how the rows happen to be sorted. Richman & Wüthrich (2026b) state a 9:1 learning–validation split, and their Listing 5 implements it as `validation_split = 0.1` (PDF p. 37); Zelený's triangle network does the same on data sorted by accident year, which makes it a quasi-temporal hold-out of the latest accident years (Section 7); Ferrario et al.'s listings use the same argument. None of the three says which rows are held out.

## `HP-V2` Hold-out by time

Only Avanzi et al. (2025) design a temporal validation set on purpose, for individual claims: "The training set contains all observations from claims that are finalised before calendar quarter 36, the validation set is for those that are finalised between calendar quarters 36 and 40, while the test set contains" (Avanzi et al. 2025, PDF p. 10, §3.2.1) They reject the cheaper alternative explicitly, "When it comes to the latter, K-Fold Cross Validation (Kohavi, 1995) is a common method. However, it is not appropriate for forecasting problems." (Avanzi et al. 2025, PDF p. 13, §3.4) and consider rolling origins too expensive: "Fixed origin and rolling origin cross-validation (Tashman, 2000) are two potential mitigants. However, relative to a singular validation set, these methods would increase the runtime costs by a factor equal to the number of windows, or splits." (Avanzi et al. 2025, PDF p. 11, §3.2.2) Their fix for the fact that recent claims are short: "Our solution is to randomly move 20% of the validation set into the training set." (Avanzi et al. 2025, PDF p. 11, §3.2.2)

Guo (2026) uses a calendar split for early stopping, "Training: calendar year ≤ 2008 (WC: 17,669 samples; PPA: 25,618 samples); Validation: calendar years 2009–2010 (WC: 3417; PPA: 4236); Test: calendar year = 2011 (WC: 1828; PPA: 2233)." (Guo 2026, PDF p. 8, §4.1) but ranks the configurations on the test year (Section 4.5).

Ramos-Pérez et al. (2020) hold out the **last observed diagonal**, "Accordingly, the last diagonal is selected as a test set because it contains the most updated information, while the rest of the triangle is used for fitting the algorithms (Figure 2)." (Ramos-Pérez et al. 2020, PDF p. 9, §3.1) and choose dropout on it for each triangle, "During the optimization process, different configurations of the algorithms are fitted with the training data. To obtain the best configuration, the test set is predicted, and the root mean squared error of every option is computed. Finally, the configuration that minimizes the former test error is selected." (Ramos-Pérez et al. 2020, PDF p. 9, §3.1) This is a legitimate one-step-ahead validation set, although the paper calls it a test set and does not say whether the model is refitted afterwards.

Among the non-network papers, Avanzi et al. (2024) put the latest calendar periods in the validation set on purpose: "We allocate the latest calendar periods to the validation set to better validate the projection accuracy of models, which is also common practice in the actuarial literature." (Avanzi et al. 2024, PDF p. 10, §3.4)

## `HP-V3` $K$-fold cross-validation

[WM]: "Typically, in applications, one uses K-fold cross-validation with K = 10." ([WM] p. 101) [AIT]: "K is a hyper-parameter that is usually selected as K = 10, but for small sample sizes n we may also select a smaller K to receive reliable results" ([AIT] p. 29) and "K-fold cross-validation is only feasible on smaller problems and models." ([AIT] p. 33) [GBC] gives the algorithm (Algorithm 5.1, p. 123) and the caveat "One problem is that there exist no unbiased estimators of the variance of such average error estimators (Bengio and Grandvalet, 2004), but approximations are typically used." ([GBC] p. 122) In the folder: Yeldan & Karabey ("Grid search and five-fold cross-validation are used in together to determine the hyperparameters." (Yeldan–Karabey 2026, PDF p. 12, §3.2)), Hiabu et al. (`folds = 3` in "patience = 20), epochs = as.integer(300), num\_workers = 0, verbose = FALSE, verbose.cv = TRUE, folds = 3, parallel = FALSE, random\_seed = as.integer(Sys.time()))" (Hiabu et al. 2025, PDF p. 17, §2.4.2; identical code again on PDF p. 18, §2.5.1)), Usman ("This BO search is executed in each of the five folds cross-validation (CV) each repeated 3 times so that 15 distinct combinations are extracted, and the best set of hyperparameters is selected with a minimum score of custom PM MSE from the initial random sampling list of 15 with iterations 10" (Usman PhD 2024, PDF p. 159, §4.2.9)) and Mulquiney ("The tuning parameters were determined using cross-validation and the final neural network consisted of a single hidden layer with 20 units and a weight decay of 0.05." (Mulquiney 2006, PDF p. 2, §2.3), with no details). None of the four describes blocking the folds by time. Gridin rejects cross-validation for time series outright: "Cross-validation technique does not perform well for time series forecasting problems." (Gridin 2021, §14, Ch. 3 > Points to remember)

## `HP-V4` Rolling origin and back-testing: the reserving-specific signals

These are the only signals in the folder that test what a reserve does, namely forecast later calendar periods. In general form: for a set of past valuation dates $c\in\mathcal C$, fit on the diagonals up to $c-1$ with hyperparameters $\lambda$, predict diagonal $c$ (or the next $h$ diagonals), and average a loss
$$S(\lambda)=\frac{1}{|\mathcal C|}\sum_{c\in\mathcal C}\ \sum_{i+j=c} w_{ij}\,L\big(Y_{ij},\ \hat\mu^{(c-1)}_{ij}(\lambda)\big),\qquad \lambda^\star=\arg\min_\lambda S(\lambda).$$

* **Al-Mudafer et al. (2021)** build the partitions inside the upper triangle: "In the first partition, the data is assumed to comprise a 30×30 triangle, which leaves the latest 10 calendar periods for the testing set." (Al-Mudafer et al. 2021, PDF p. 10, §3.1) "The second partition works with a 36×36 triangle, leaving 4 calendar periods for testing." (Al-Mudafer et al. 2021, PDF p. 10, §3.1) "For all partitions, the validation set included the 4 latest non-testing calendar periods, excluding the first 3 accident and development periods." (Al-Mudafer et al. 2021, PDF p. 10, §3.1) with the rationale "That way, when combined with Early Stopping (see Section 4), the MDN stops training when short term projection accuracy is maximised." (Al-Mudafer et al. 2021, PDF p. 10, §3.1) and averaging over initialisations: "Hence, the MDN is trained 2T times for each set of hyper-parameters θ, as each run has a different weight initialisation and hence a different fit. Averaging the error of these runs reduces the impact of random weight initialisations on the performance of the hyper-parameter set θ." (Al-Mudafer et al. 2021, PDF p. 16, §4.1)
* **Avanzi et al. (2026), "rolling settlement validation"**: "We introduce a “rolling settlement” tuning procedure, whereby temporal splitting of data is carefully performed to prevent data leakage during training and validation." (Avanzi et al. 2026, PDF p. 4, §1.3) "We can partition the training time interval \[0, M \] into k equal length time intervals S1 , ..., Sk ." (Avanzi et al. 2026, PDF p. 20, §5.2.3) "Therefore, for each hyperparameter combination, we train on S1 to predict the OCL for development periods of claims that settle in S2 , then train on S1 + S2 and predict for S3 , and so on. The k results are averaged to compare across all hyperparameter combinations." (Avanzi et al. 2026, PDF p. 20, §5.2.3) "For simplicity and because we are working with a small dataset, we choose k = 3 (Figure 5.1 depicts k = 2)." (Avanzi et al. 2026, PDF p. 20, §5.2.3) The criterion is reserve-level (`HP-V7`): "Another option (which we decided to implement here) is to focus on the aggregate performance measured by the ratio (7.1); more specifically, to choose the set of hyperparameters that leads to a predicted (overall) OCL that is the closest to its actual value." (Avanzi et al. 2026, PDF p. 23, §7.3)
* **Balona & Richman (2020)**, next-diagonal actual-versus-expected and claims development result, averaged over 13 calendar years: "based on the next diagonal of experience. Note that, at this stage, this next diagonal has not been used to fit the reserving model, i.e. it is out of sample data." (Balona–Richman 2020, PDF p. 13, §3) "Select Mopt = argminM ∈M (S M )." (Balona–Richman 2020, PDF p. 13, §3) "The AvEscore and CDRscore were calculated across 13 calendar years from 1984 to 1996 for each parameter set." (Balona–Richman 2020, PDF p. 16, §4) The CDR version adds a stability penalty: "As noted in Section 2.2, the CDR can be thought of as a regularized actual versus expected score where the penalty term added to the AvE result is the change in the ultimate reserve estimate between calendar years." (Balona–Richman 2020, PDF p. 13, §3) Mayr (2025) applies the CDR score to chain-ladder configurations: "By systematically comparing the average CDR scores of all models, the optimal model is identiﬁed as the one with the lowest average CDR score, since the overall average score provides a strong indicator of overall model performance." (Mayr MSc 2025, PDF p. 45, §5)
* **Zelený (2026)** evaluates on rolling valuation years, "The training sample for valuation year v is formed solely from earlier valuation views, preserving the temporal ordering of information and ensuring that the empirical design remains consistent across model classes." (Zelený MSc 2026, PDF p. 34, §4.1) and uses the same rolling-origin results to fix pipeline settings: "Alternative cutoff specifications were checked against the rolling-origin performance, and the final configuration was then kept fixed for the reported comparison." (Zelený MSc 2026, PDF p. 41, §4.3) (Section 4.5).
* **[H]** gives the classical versions, as diagnostics rather than tuning criteria: "The idea, based on an approach often used in time series applications, is to remove a diagonal from the data triangle, apply the stochastic method, and then compare the actual and fitted data on that diagonal" ([H] p. 314) "These one-step-ahead prediction errors or validation residuals can sometimes show patterns that are not evident in the other types of residual plots, and hence can be a useful part of overall method validation." ([H] p. 314) and, for monitoring, "First, it can be compared with the actual claims development in the same period, to help determine whether the estimated ultimate claims at the previous valuation date need revising and, if so, in what direction and by what order of magnitude." ([H] p. 353)

Lindholm et al. state the principle that all of these implement: "Still, given a sufficient amount of data you can always split your data set into three parts: one part used for training, one part used for determining the number of steps that the optimization procedure should be run, corresponding to a pseudo-validation data set, and a ﬁnal third sub-set used for proper out-of-sample validation once the model has been properly trained (without any prior peeking!)." (Lindholm et al. 2020, PDF p. 75, §3.2)

## `HP-V5` The test set or the known truth

**The rule.** [GBC]: "It is important that the test examples are not used in any way to make choices about the model, including its hyperparameters. For this reason, no example from the test set can be used in the validation set." ([GBC] p. 121) [WM] reserves the test set for comparing model classes: "the latter only being used in the final step for comparing different statistical models (e.g., a GLM vs. a FN network)." ([WM] p. 290) [AIT] likewise: "The selected model(s) are evaluated (compared to each other) on the hold-out sample" ([AIT] p. 28) Using the test data to choose a *hyperparameter* is excluded by all three; using it to choose *between model classes* is allowed by [WM] and [AIT] but not by [GBC].

**Confirmed cases** (an in-scope hyperparameter chosen or confirmed on test data or on the simulated truth):

| # | Document | What was chosen on the test data or truth | Evidence |
|---|---|---|---|
| 1 | Guo 2026 | the tuned configuration: the top-20 screen and the final ranking use MAPE on the calendar-2011 test diagonal; the 2009–2010 validation years only drive early stopping | "Training: calendar year ≤ 2008 (WC: 17,669 samples; PPA: 25,618 samples); Validation: calendar years 2009–2010 (WC: 3417; PPA: 4236); Test: calendar year = 2011 (WC: 1828; PPA: 2233)." (Guo 2026, PDF p. 8, §4.1); "In the validation stage, the top 20 configurations by screening MAPE were retrained with 5 additional independent seeds each (100 validation runs). The training, evaluation, and benchmark protocols carried over verbatim from Phase 1, except that the hyperparameter values listed above replaced the fixed Phase 1 settings." (Guo 2026, PDF p. 15, §4.4); "each validation run used a distinct random seed and a fresh initialization, but after early stopping on validation loss the runs converged to test MAPEs that differed only below the three-decimal precision shown here, on the small single-diagonal test set." (Guo 2026, PDF p. 17, §5.2) |
| 2 | Ramos-Pérez et al. 2020 | the number of hidden layers, confirmed against the lower-triangle reserves (Table 7) | "With regard to accuracy, it is worth mentioning that the proposed structure of the ANNs (two hidden layers) within the Stacked-ANN model seems to be the optimal configuration according to the empirical results." (Ramos-Pérez et al. 2020, PDF p. 22, §5) |
| 3 | Nicholas 2026 | the "best" learning rate, judged on reserve ratios against the true reserves | "This simulation study reveals that at the best learning rate of 0.001, the LSTM produced on average a 35% overestimation which exceeds the previously selected range of upper bounds for reserve misestimation." (Nicholas MSc 2026, PDF p. 47, Ch. 4) |
| 4 | Härkönen 2021 | trainable versus frozen embeddings, from the reserve results on real data | "The simple neural network model here is fitted with trainable weights as the results are much better than with non-trainable weights, especially for LoB 1." (Härkönen MSc 2021, PDF p. 49, §4.2) |
| 5 | Ferrario et al. 2020 | optimiser, batch size, dropout, penalty, architecture compared on the test set $\mathcal T$; the authors flag it | "Remark that the analysis in this section is not fully sound because Figure 15 should not show any out-of-sample losses on the test data, and appropriate regularization parameters η > 0 should either be chosen with cross-validation or with splitting the learning data D into training set and validation set, see Section 5.1." (Ferrario et al. 2020, PDF p. 33, §5.2); "Moreover, in a rigorous analysis we should not show the out-of-sample performance in Figure 16, but we should rather split the learning data D to training and validation set." (Ferrario et al. 2020, PDF p. 34, §5.3) |
| 6 | Usman 2024 | early stopping monitors the held-out split, which is also the evaluation split | "validation\_data =( X\_test , YY\_test ) , callbacks =\[ early\_stopping \])" (Usman PhD 2024, PDF p. 178, Code Listing 4.4) |
| 7 | Gridin 2021 | the NNI trial metric is the test loss | "A trial is a classical training-validating-testing script. And the testing loss function value is used as the trial metric for a given hyper-parameter combination." (Gridin 2021, §17, Ch. 6 > Hyper-parameter tuning > Trial; idx p. 175-176); "After some time, NNI returns the combination of hyper-parameters that showed the best results, i.e., the minimum loss function on the test dataset:" (Gridin 2021, §17, Ch. 6 > NNI search) |
| 8 | Graziani & Xibilia (eds.) 2021 | several chapters tune on the test split, e.g. Ch. 1 has no validation part left | "In our experiments, we use both training part and validation part as training dataset." (Graziani–Xibilia (eds.) 2021, PDF p. 23, Ch. 1 §4.2) |
| 9 | Swallow 2023 | GAN settings chosen on the same metrics that are then reported, with no separate validation sample | "The best models were found by varying the different hyperparameters for each GAN variant. The best GAN model for each variant was selected based on the training set results." (Swallow MSc 2023, PDF p. 37, §3.4.1); "This was the main basis for model selection as most other metrics were very similar across each variant." (Swallow MSc 2023, PDF p. 45, §3.4.2) |
| 10 | Rügamer et al. 2023 | the entropy penalty $\xi$ is judged against the true mixture probabilities of a simulated example | "Fig. 5 Coefficient path (estimated mixture probabilities) for different entropy penalties. A value of around 1e-02 yields the best trade-off between sparsity and estimation performance" (Rügamer et al. 2023, PDF p. 17, Fig. 5) |

**Possible cases** (the text leaves it open):

* Yeldan & Karabey: the text says the selection used the gap between validation and *training* loss, "In classical approaches, the selection of hyperparameters is often based only on the model with the lowest validation loss. In this study, in addition to the validation loss, the difference between the validation loss and the training loss is also taken into account." (Yeldan–Karabey 2026, PDF p. 12, §3.2) but Table 2 reports the gap between validation and *test* loss ("Difference between average validation and test loss" (Yeldan–Karabey 2026, PDF p. 12, Table 2 column header)).
* Zelený: the pipeline settings were checked on the rolling-origin years that are also the reported evaluation years ("Alternative cutoff specifications were checked against the rolling-origin performance, and the final configuration was then kept fixed for the reported comparison." (Zelený MSc 2026, PDF p. 41, §4.3)); the network "tuning" claimed in the code is not shipped (Section 7).
* Côté et al.: finalists are kept on fidelity to the real data, "We also compared the predictions on the target ClaimNb of a random forest regressor and a random forest classifier between the generated and real samples, and kept the combination giving the best overall results." (Côté et al. 2025, PDF p. 16, App. B.3) and the paper does not say whether "real" means the validation third or the data used in the reported comparison.

**Not counted but related.** Mahohoho et al. pick their "best model" (an algorithm, not a hyperparameter) from test results and by the size of the reserve rather than its accuracy ("Random forests have obtained the highest value of the ACAALR hence we regarded it as the best model since there is a large stake of reserves set aside for consideration towards actuarial risk premium pricing and actuarial underwriting respectively." (Mahohoho et al. 2023, PDF p. 24, §6.9)). Lindholm et al. tune their gradient-boosting benchmarks partly on the truth (Appendix A), but not the networks. Al-Mudafer et al. and Cai et al. make an out-of-scope loss choice with reference to forecast-region behaviour (Appendix A).

## `HP-V6` to `HP-V9`: other signals

* **In-sample only.** "Due to data constraints, a formal training/test split was not feasible, and all performance evaluations were performed in-sample." (Noordhoek MSc 2025, PDF p. 59, §5) Rügamer et al. choose among restarts on the in-sample log score (`HP-M19`). [AIT] explains why this cannot work for capacity hyperparameters: "always a more complex model would outperform a nested simpler one" ([AIT] p. 28) and [GBC]: "If learned on the training set, such hyperparameters would always choose the maximum possible model capacity, resulting in overfitting (refer to figure 5.3)." ([GBC] p. 121)
* **Reserve-level.** Avanzi et al. (2026), above; the CDR/AvE scores of Balona & Richman and Mayr. The hazard is that a reserve-level criterion rewards cancelling errors: a configuration can hit the total while being wrong cell by cell.
* **Probabilistic.** Al-Mudafer et al. average the negative log-likelihood over $2T$ runs; Hiabu et al. use the partial likelihood, "The score metric we inspect is the negative (partial) likelihood. The likelihood is returned with a negative sign as Wilson (2022) is maximizing the objective function." (Hiabu et al. 2025, PDF p. 17, §2.5.1) Avanzi et al. (2024, no network) the log score: "Remark 3.1: Here, the Log Score is chosen to calibrate model component weights in the validation sets (the latest diagonals)." (Avanzi et al. 2024, PDF p. 9, §3.1.2) On the choice of scoring rule, [AIT]: "if one fits regression models on conditional means, one should not use MAE figures to validate them." ([AIT] p. 23) and "Namely, the Gini score is not a strictly consistent model selection tool." ([AIT] p. 83)
* **Other.** For GANs there is no likelihood to validate on, so fidelity statistics or the shape of the loss curves are used (Côté et al., Swallow, Xu et al.). Yeldan & Karabey add a validation–training gap: "Instead of model selection based solely on the smallest validation loss, the difference between validation and train­ ing losses is evaluated as an additional criterion, reducing the risk of overfitting." (Yeldan–Karabey 2026, PDF p. 4, §1) [GBC]'s one numerical diagnostic: "As suggested by Bottou (2015), we would like the magnitude of parameter updates over a minibatch to represent something like 1% of the magnitude of the parameter, not 50% or 0.001% (which would make the parameters move too slowly)." ([GBC] p. 440)

## What a defensible reserving design looks like

Putting the textbooks and the best practice in the folder together (this is a synthesis, not a quotation):

1. **Outer evaluation that nothing touches.** The simulated lower triangle, or the last $h$ calendar years of real data, is used once, at the end (the [GBC] rule, p. 121; the "without any prior peeking" of Lindholm et al.).
2. **Inner signal by time, not at random.** A rolling-origin or next-diagonal score (`HP-V4`) on the upper triangle, as in Al-Mudafer et al., Avanzi et al. (2026) or Balona & Richman, with the loss chosen to be strictly consistent for the target ([AIT] p. 23), plus, if needed, a random claims split (`HP-V1`) for early stopping within each origin.
3. **Seeds averaged in the score.** Each configuration scored as the mean over several seeds (Al-Mudafer et al.'s $2T$ runs; [WM] p. 460: "To reduce the randomness coming from early stopping with different seeds, we average the deviance losses over 20 runs" ([WM] p. 460)), not by a single run.
4. **Refit rule stated.** Either retrain on all data for $t^\star$ steps (GBC Algorithm 7.2) with a check that $t^\star$ transfers to the larger volume, or keep the early-stopped weights.
5. **Report** the candidate set, the number of trials, the chosen values, and where the chosen values sit in the grid.

# Reference card: each hyperparameter, the values used, how they were chosen, and what the books advise

Values are as reported in the documents (Appendix A has the source page for each). "Chosen by" uses the `HP-M` labels of Section 3.

## Architecture

| Hyperparameter | Values found in the folder | Chosen by | Textbook guidance |
|---|---|---|---|
| **Depth** | 1 hidden layer (Mulquiney; Qiu; Zelený's triangle network; parts of Gabrielli's PhD Paper A); 2 (Wüthrich 2017; Gabrielli 2019; Ramos-Pérez et al. 2020; Hiabu et al. final); 3 (the (20, 15, 10) family: Gabrielli et al. 2018, Richman & Wüthrich 2021 and 2026a, Härkönen, Noordhoek, Ferrario et al.; Yeldan & Karabey; Zelený's claim-level network); 5 (Usman); 10 (Schwab PhD MLP) | `HP-M04`/`HP-M02` almost everywhere; searched only by Al-Mudafer et al. ($h\in\{1,2,3,4\}$, `HP-M10`), Avanzi et al. 2025 (2–4, `HP-M07`), Hiabu et al. ($[2,10]$, `HP-M09`); confirmed on the truth by Ramos-Pérez et al. 2020 (`HP-V5`) | [AIT] 3–6 layers (p. 106); [WM] deep rather than shallow for representation learning (p. 274); [GBC] "via experimentation guided by monitoring the validation set error" (p. 198) |
| **Width** | $(9,7)$ down to $(2,2)$ per development period (Wüthrich 2017); $(20,15,10)$ (see above); $(30,25)$ single and $(40,30)$ multi-LoB (Gabrielli 2019); 40/30/10/10 (Gabrielli 2020); 3 LSTM units (Kuo 2020); 128 GRU units (Cai MSc; Guo Phase 1); $\{32,\dots,256\}$ searched (Schneider & Schwab); 10 nodes, the upper bound (Hiabu et al.); $(45,30,15,10,5)$ (Usman) | grid by Wüthrich 2017 and Gabrielli 2019 (`HP-M07`); random/Bayesian by Schneider & Schwab, Guo, Hiabu et al.; otherwise inherited or argued | [AIT] 15–30 neurons per layer (p. 106); [WM] stay above a minimal complexity (p. 293); [GBC] width is a capacity hyperparameter on a U-shaped curve (§11.4.1) |
| **Activation** | tanh (the ETH line; Zelený's triangle network); ReLU (DeepTriangle line, Avanzi et al. 2025, TabM, Zelený's claim-level network); sigmoid (Al-Mudafer et al.; Ramos-Pérez et al. 2020); GELU (Richman & Wüthrich 2026b; Spedicato & Richman); softplus (Bücher & Rosenstock); LeakyReLU (Hiabu et al. final; GANs) | `HP-M04` (argument) or `HP-M02`; compared only by Ferrario et al. (tanh vs ReLU), Bücher & Rosenstock (softplus vs ReLU), Hiabu et al. (in the Bayesian search), Swallow | [WM] prefers tanh (p. 270); [GBC] ReLU default (p. 191), tanh better than logistic sigmoid (p. 195); [AIT] "part of hyper-parameter tuning" (p. 92) |
| **Embedding dimension** | 1, frozen at the ccODP estimates (Gabrielli et al. 2018; Härkönen; Noordhoek); 2 (Kuo 2020; Schneider & Schwab; Gabrielli 2020 except AY = 3); $C-1$ (Cai et al.); $\lceil K^{1/4}\rceil$ (Spedicato & Richman); 50 (Guo) | `HP-M05` rules or `HP-M02`; never searched | [AIT] $b\ll K$ (p. 48); [WM] $b$ is "a hyper-parameter that has to be selected by the modeler" (p. 298); [GBC] none |
| **Skip / CANN connection** | the classical model in a skip connection (Gabrielli line, Härkönen, Noordhoek, Al-Mudafer ResMDN, Yeldan & Karabey, Mack-Net's internal skip) | by design (`HP-M20`), except Noordhoek, who makes the degree of initialisation $\omega$ a hyperparameter | [WM] pp. 316–318; [AIT] p. 112, p. 114; [GBC] skip connections as an optimisation aid (p. 201) |

## Optimisation

| Hyperparameter | Values found | Chosen by | Textbook guidance |
|---|---|---|---|
| **Optimiser** | RMSprop (Gabrielli et al. 2018, Gabrielli 2019, Härkönen, Zelený's triangle network); Adam (Richman & Wüthrich 2026a, b; Al-Mudafer et al.; Ramos-Pérez et al.; Schneider & Schwab), AMSGrad variant (Cai et al.; Guo); Nadam (Gabrielli 2020; Richman & Wüthrich 2021; Ferrario et al.); AdamW (Avanzi et al. 2025; TabM; Ye et al.); SGD (Kuo 2020; Hiabu et al. final; Nicholas); AdaDelta (Usman); scaled conjugate gradient (Qiu) | mostly `HP-M03`/`HP-M02`; compared by Ferrario et al. ("Since fine-tuning the ’sgd’ for learning rates, etc., is too time-consuming we continue with the pre-specified optimizer ’nadam’ which outperforms the others in the analysis" (Ferrario et al. 2020, PDF p. 19, §4.1; sentence ends "of Table 5." on p. 20)), Al-Mudafer et al. (`HP-M06`), Rügamer et al. (benchmark), Hiabu et al. (searched) | [GBC]: no consensus (p. 309), choice "largely on the user's familiarity" (p. 310); [WM] relies on RMSprop and Nadam (p. 287); [AIT] rmsprop/adam standard (p. 100) |
| **Learning rate** | $10^{-3}$ (most Keras defaults; Richman & Wüthrich; Noordhoek; Zelený); $5\times10^{-4}$ (Guo Phase 1; Cai MSc); $10^{-2}$ (Ramos-Pérez et al.; Kuo 2020; Avanzi et al. 2025); searched log-uniformly over $[10^{-5},10^{-1}]$ (Schneider & Schwab), $[10^{-4},5\times10^{-3}]$ (Guo), a 25-point log grid over $[10^{-5},5\times10^{-3}]$ (TabM, in its study of $k$), $[0.005,0.5]$ (Hiabu et al., result 0.0223) | defaults (`HP-M03`) or searched (`HP-M07`–`HP-M09`); adapted during training (`HP-M14`) | [GBC] the most important hyperparameter (p. 429); choose $\epsilon_0$ from learning curves (p. 295); grid on a log scale (p. 434); [WM] "tempered" (p. 279); [AIT] fine-tuned by the modeller, standard values available (p. 100) |
| **Learning-rate schedule** | plateau ×0.9 after 5 epochs (Richman & Wüthrich); halve after a plateau (Kuo 2020); ×0.1 every 10 epochs (Schneider & Schwab); cosine with restarts (Dong et al.); none (TabM) | fiat (`HP-M01`) in every case | [GBC] linear decay to $\epsilon_\tau\approx 0.01\,\epsilon_0$ over a few hundred epochs (p. 295) |
| **Batch size** | full batch, i.e. the whole triangle (Gabrielli et al. 2018: 78 cells, 468 for six LoBs; Ramos-Pérez et al.; Manai code); 32 (Rügamer et al.); 512 (Guo); 2,048 (Nicholas); 4,096 and 8,192 (Richman & Wüthrich 2026a, b); ≈ 5,000–6,000 (Ferrario et al.; Richman & Wüthrich 2021); 10,000 (Gabrielli 2020; Kuo 2020 generative); 100,000 (Kuo 2020); searched: $\{256,512\}$ (Avanzi et al. 2025), $\{750,\dots,1500\}$ (Yeldan & Karabey), $\{1024,2048\}$ (Schneider & Schwab), $[75,120]$ (Usman) | mostly fiat; Ferrario et al. compare run time against loss ("From the table and the figures we see that the optimal batch size for our network architecture (in terms of run time versus out-of-sample loss) is roughly 6’000." (Ferrario et al. 2020, PDF p. 24, §4.3)) | [GBC] 32–256, smaller batches regularise (p. 279); [AIT] 2,000–5,000 for insurance frequency (p. 105); [WM] "batches should have a minimal size" (p. 285) |
| **Epochs / steps and patience** | patience 5 or 10 (Avanzi et al. 2025, text vs table), 10 (Kuo 2020; Andersen & Roed-Sørensen), 12 and 20 (Zelený), 15 (Nicholas), 16 (TabM), 20 in tuning and 350 in the final fit (Hiabu et al.), 35 (Manai code), 100 (Cai et al.), 200 (Guo; Cai MSc), 250 (Rügamer et al.), 1,000 (Al-Mudafer et al.); fixed step counts 300 and 200 (Gabrielli et al. 2018), 400 (Gabrielli 2019), about 7,000 (Härkönen), 10,000 (Ramos-Pérez et al. 2020) | `HP-M13` in its six variants | [GBC] Algorithm 7.1 (p. 247), no default patience; [WM] "five times in a row" (p. 291); [AIT] callback, no patience value (p. 103) |
| **Initialisation** | Glorot uniform (the Keras default; Ferrario et al., Mack-Net, Rügamer et al.); He (Cai et al.); Xavier (Noordhoek); at the classical model (`HP-M20`); pretrained weights (Cai et al. for replicates, `HP-M21`) | default, argued or structural | [GBC] the initial scale "as a hyperparameter" chosen by search (p. 304); [WM] random Glorot, output bias at the null model (p. 284); [AIT] start in the MLE-fitted GLM (p. 114) |
| **Seed** | 42 (Zelený), 75 (Härkönen), 101 (Qiu), clock-based (Hiabu et al.), a random draw (Gabrielli 2019), several (all ensembles) | fiat; averaged (`HP-M16`); or best-of-N (`HP-M19`) | [AIT] seeds must be stored (p. 96); [WM] average losses over 20 seeds before comparing (p. 460) |

## Regularisation and ensembles

| Hyperparameter | Values found | Chosen by | Textbook guidance |
|---|---|---|---|
| **Dropout rate** | 0 (Avanzi et al. 2025, after initial testing); 1–10 % compared (Ferrario et al.); 5 % (Mack-Net; Manai code; Usman's code, against 20 % in his text); 10 % (Gabrielli et al. 2018; Gabrielli 2020; Noordhoek; Guo Phase 1); 20 % (Gabrielli 2019; Härkönen; Cai MSc via Kuo); 30 % (Zelený's triangle network); searched: $\{0,0.1,0.2\}$ (Al-Mudafer et al.), per-triangle grid with means 0.07–0.13 by line (Ramos-Pérez et al. 2020), $\mathcal U[0.1,0.5]$ (Schneider & Schwab), log-uniform $[0.01,0.30]$ (Guo) | fiat, manual, or searched (Section 3) | [GBC] drop 20 % of inputs, 50 % of hidden units (p. 259, p. 261); enlarge the model when using dropout (p. 265); [WM] dropout ≈ ridge with $\lambda=\delta/(2(1-\delta))$ (p. 304); [AIT] "a hyper-parameter selected by the modeler" (p. 104) |
| **L2 / weight decay** | $10^{-3}$ (Gabrielli 2019; Härkönen; Manai code as AdamW decay); $10^{-5}$ by trial and error (Ferrario et al.); $2\times10^{-4}$ and $2\times10^{-3}$ (Zelený); 0.3 (Andersen & Roed-Sørensen); $\lambda_w\in\{0,10^{-4},10^{-3},10^{-2},10^{-1}\}$ searched and then overridden to 0 for one environment (Al-Mudafer et al.: "When running the ResMDN on environment 3, a positive L2 penalty on the weights led to almost no boosting. Hence, the penalty was manually adjusted to 0 to encourage network activity." (Al-Mudafer et al. 2021, PDF p. 36, App. D)) | mostly fiat or inherited | [GBC] one $\alpha$ for all layers to save search (p. 230); [WM] tuning $\lambda$ is hard for networks (p. 303); [AIT] "more regularization and drop-out is needed with increasing sizes" (p. 105) |
| **Normalisation layers** | batch normalisation on one layer (Gabrielli 2019; Härkönen); batch and layer normalisation (Avanzi et al. 2025); layer normalisation (Richman & Wüthrich 2026b transformer) | argued or inherited | [WM] "not been necessary" for their networks (p. 304); [GBC] batch normalisation mainly an optimisation aid (p. 268); [AIT] (p. 105, p. 176) |
| **Number of ensemble members** | see the table in `HP-M16`: 5, 10, 20, 32, 50, 100 | fixed in every case; never selected by a criterion | [WM] 10–20 (p. 328), 20 (p. 493), $M=1{,}600$ for one policy (p. 323); [AIT] 10 or 20 (p. 109); [GBC] 5–10 (p. 258) |

# What each textbook says, book by book

Each table gives the label, the place in the book (section and printed page), the quotation, and what it implies for choosing a network's hyperparameters in a reserving study.

## [WM] Wüthrich & Merz (2023), *Statistical Foundations of Actuarial Learning and its Applications*

The book's position in one sentence: use a network above a minimal complexity, early-stop it on a validation split carved from the learning data, correct its balance, and average over seeds; do not search the architecture and do not use AIC.

| Label | Where | Quotation | Implication |
|---|---|---|---|
| TB-WM-1 | §4.2.1, pp. 96–98 | "Note that L is only used for model fitting and T is only used for the deviance GL evaluation" ([WM] p. 96) "For this concept to be useful, the learning data L and the test data T have to be sufficiently similar, i.e., ideally coming from the same model." ([WM] p. 98) | The learning/test logic requires $\mathcal L$ and $\mathcal T$ to come from the same model. In reserving the lower triangle is *later* calendar time, so a random split of the upper triangle satisfies the letter but not the spirit of this condition (Section 4.1). |
| TB-WM-2 | §4.2.2, pp. 101–102 | "Typically, in applications, one uses K-fold cross-validation with K = 10." ([WM] p. 101) "If there is no test data set T available we perform (stratified) K-fold cross-validation." ([WM] p. 102) | Cross-validation is the book's tool for GLMs and penalties. It is never applied to network hyperparameters in the book. |
| TB-WM-3 | §4.2.3, p. 104; §7.4.4, p. 338 | "otherwise there is no mathematical justification why (4.37) should be a reasonable model selection tool." ([WM] p. 104) "Remark that AIC values within FN networks are not supported by any theory as we neither use the MLE nor do we have a reasonable evaluation of the number of parameters involved in networks." ([WM] p. 338) "Thus, such a value may serve at best as a rough rule of thumb." ([WM] p. 338) | Rules out AIC/BIC for choosing a network's size or its epochs (`HP-M23`). |
| TB-WM-4 | §5.6.2, p. 193; §6.2, p. 211 | "This also motivates to study the generalized cross-validation (GCV) loss which is an approximation to leave-one-out cross-validation" ([WM] p. 193) "the regularization parameter λ > 0 which acts as a hyper-parameter. Optimal hyper-parameters are determined by cross-validation." ([WM] p. 211) | GCV and CV for $\lambda$ are available for GLM penalties; for a network's $L^2$ weight the book only says tuning is hard (TB-WM-12). |
| TB-WM-5 | §7.2.1, p. 270 | "This anti-symmetry and boundedness is an advantage in fitting deep FN network architectures. For this reason we usually prefer the hyperbolic tangent over other activation functions." ([WM] p. 270) "This is the preferred choice in the machine learning community. However, typically, we will not use it because in our experience it is less robust in fitting compared to the hyperbolic tangent activation function." ([WM] p. 270) | The source of the tanh default in the ETH reserving papers (`HP-M04`). |
| TB-WM-6 | Remarks 7.9, p. 293 | "At this stage, one could be tempted to choose a smaller network to prevent from over-fitting. In general, this is not a sensible thing to do because the network needs sufficient flexibility to be able to be fitted to the data." ([WM] p. 293) "That is, we need some redundancy in the model to be able to successfully apply the SGD algorithm, otherwise the algorithm may get trapped in saddlepoints or bottlenecks." ([WM] p. 293) "Thus, the chosen network architecture should be above the bound of a necessary minimal complexity, and different architectures above this bound will provide similar accuracy (without a clear winner)." ([WM] p. 293) | The argument *against* a width/depth grid: above the bound, architectures differ little, and shrinking to fight over-fitting harms SGD. A grid that ends at $(2,2)$ (Wüthrich 2017) sits exactly where this remark says not to go. |
| TB-WM-7 | §7.2.3, p. 280; p. 287 | "between smaller and bigger learning rates: they need to be sufficiently small so that the first order Taylor expansion is still a valid approximation" ([WM] p. 280) "they should be sufficiently big otherwise the convergence of the algorithm will be very slow because it needs many iterations." ([WM] p. 280) "In our analysis we are mainly relying on the variants rmsprop and the" ([WM] p. 287) | Qualitative learning-rate advice only; no numbers (the Keras defaults do the work). |
| TB-WM-8 | §7.2.3, p. 285 | "On the other hand, batches should have a minimal size so that the gradient descent updates are not too erratic" ([WM] p. 285) "For this reason, optimal batch sizes should be chosen carefully." ([WM] p. 285) | Batch size matters and should be chosen; on a 78-cell triangle full batch is the natural choice. |
| TB-WM-9 | §7.2.3, pp. 290–291 | "This early stopping point is determined by doing an out-of-sample analysis. This requires the learning data L to be further split into training data U and validation data V." ([WM] p. 290) "Thus, for FN network fitting with early stopping we need a reasonable amount of data that can be split into 3 sufficiently large data sets so that each is suitable for its purpose." ([WM] p. 290) "In such cases we should use more sophisticated stopping criteria than (7.27), for instance, early stop if the validation loss increases five times in a row." ([WM] p. 291) | The U/V/T design and a patience rule. A triangle cannot be split three ways, which is why the reserving papers split *claims* instead (Section 4.1). |
| TB-WM-10 | §7.3.2, p. 297 | "we retrieve the network with the lowest validation loss using a callback." ([WM] p. 297) "of course, in practice we need to continue beyond this minimal validation loss to ensure that we have really found the minimum." ([WM] p. 297) | Early stopping as implemented in the labs: a checkpoint callback over a generous epoch budget, as in Richman & Wüthrich (2026b). |
| TB-WM-11 | Remarks 7.9, p. 293; §7.4.4, p. 321; §11.1.2, p. 460 | "All these random elements make the early stopped SGD solution non-unique." ([WM] p. 293) "Of course, this is very unsatisfactory in insurance pricing because it implies that the selection of a price for an insurance policy has a substantial element of subjectivity" ([WM] p. 321) "To reduce the randomness coming from early stopping with different seeds, we average the deviance losses over 20 runs" ([WM] p. 460) | Any comparison of two settings should average over seeds first; a one-seed grid (Wüthrich 2017; Gabrielli 2019) is noisier than it looks. |
| TB-WM-12 | §7.4.1, pp. 303–304 | "The difficulty with this approach is the tuning of the regularization parameter(s) λ: run time is one issue, suitable grouping is another issue" ([WM] p. 303) "This is ridge regression in the linear Gaussian case with a regularization parameter λ = δ/(2(1 − δ)) > 0 for δ ∈ (0, 1), see (6.9)." ([WM] p. 304) | Dropout rate and ridge weight are two parameterisations of the same shrinkage; tuning both at once (Gabrielli 2019: 20 % and 0.001) is partly redundant. |
| TB-WM-13 | §7.4.1, p. 298 | "This small dimension b is a hyper-parameter that has to be selected by the modeler, and which, typically, is selected much smaller than the total number of levels of the categorical feature." ([WM] p. 298) | Embedding dimension is a modeller's choice; the book gives no rule for tabular data. |
| TB-WM-14 | §7.3.2, p. 297; §7.4.2, p. 305 | "This is a major deficiency of this FN network fitting approach" ([WM] p. 297) "The straightforward correction is to adjust the intercept parameter β0 ∈ R accordingly." ([WM] p. 305) | Early stopping biases the portfolio level, so the number of epochs and the balance correction interact; reserves need the correction (Richman & Wüthrich 2026a, b apply it). |
| TB-WM-15 | §7.4.3, p. 317 | "The weight α can be interpreted as the credibility assigned to the GLM." ([WM] p. 317) "This is the approach used in Gabrielli et al. \[149\] to improve the chain-ladder reserving method by learning across different claims reserving triangles." ([WM] p. 317) | The CANN/bCCNN construction in the book, with the credibility weight as an extra (fixed) hyperparameter. |
| TB-WM-16 | §7.4.4, pp. 325, 328; §11.4, p. 493 | "Nagging always acts on the same sample L, and it only refits the model multiple times. Therefore, the latter will typically introduce less variation." ([WM] p. 325) "After the first 10 steps the picture starts to stabilize which indicates that for this size of portfolio (and this type of problem) we need to average over roughly 10–20 FN networks to receive optimal predictive models on the portfolio level." ([WM] p. 328) "The nagging predictors over 100 seeds are roughly the same as over 20 seeds (see Table 11.3), which indicates that 20 different network fits suffice, here." ([WM] p. 493) | The basis for `HP-M16` and for choosing $M$ by stabilisation rather than by fiat. |
| TB-WM-17 | Remark 7.8, p. 290 | "Recent research promotes the so-called Graph HyperNetwork (GHN) that is a (hyper-)network which tries to find the optimal network architecture and its parametrization by an additional network" ([WM] p. 290) | Architecture search exists but is outside the book. |
| TB-WM-18 | Ch. 8, pp. 396, 399; §9.3.3, p. 424 | "For the gradient descent fitting and the early stopping we choose a training to validation split of 8 : 2." ([WM] p. 399) "For Fig. 8.8 we did not explore any fine-tuning" ([WM] p. 396) "we have not really fine-tuned the network architectures, nor has the SGD fitting been perfected" ([WM] p. 424) | The book's own recurrent and convolutional examples are not tuned either. |
| TB-WM-19 | §11.6.1, p. 515 | "Moreover, early stopping will imply that the selected parameters must also be good on the validation data being disjoint (and independent) from the training data." ([WM] p. 515) | Early stopping is itself a use of the validation data; a validation score used for both stopping and selection is optimistic. |
| TB-WM-20 | §12.2, p. 543 | "These bounds allow for much freedom in the choice of the growth rates, and different choices may lead to different speeds of convergence." ([WM] p. 543) | Theory allows the width to grow with $n$ but does not pin the rate: no theoretical answer to "how wide". |

## [AIT] Wüthrich, Richman, Avanzi et al. (2026), *AI Tools for Actuaries*

The book's position: a six-step recipe with fixed defaults, early stopping on a 10–20 % validation sample, and nagging with $M=10$ or 20; grid/random search and Optuna appear only for boosting.

| Label | Where | Quotation | Implication |
|---|---|---|---|
| TB-AIT-1 | §1.5.2, p. 23; §4.3.1, p. 83 | "if one fits regression models on conditional means, one should not use MAE figures to validate them." ([AIT] p. 23) "Namely, the Gini score is not a strictly consistent model selection tool." ([AIT] p. 83) | The validation score must be a strictly consistent loss for the target (e.g. Poisson deviance for a mean); MAE or Gini are not valid selection signals. |
| TB-AIT-2 | §1.6.1, p. 28 | "Model fitting and model validation should not be done on the identical sample." ([AIT] p. 28) "This out-of-sample loss (1.16) is the main workhorse for model selection in machine learning models" ([AIT] p. 28) "These two samples should be mutually independent, and contain i.i.d. data" ([AIT] p. 28) | The book's selection logic assumes i.i.d. samples; it gives no time-ordered variant. |
| TB-AIT-3 | §1.6.2, pp. 29–30, 33 | "K is a hyper-parameter that is usually selected as K = 10, but for small sample sizes n we may also select a smaller K to receive reliable results" ([AIT] p. 29) "we can also quantify uncertainty by computing the empirical standard deviation on the K folds" ([AIT] p. 30) "K-fold cross-validation is only feasible on smaller problems and models." ([AIT] p. 33) | Fold standard deviations quantify selection noise; $K$-fold CV is not recommended for networks. |
| TB-AIT-4 | §1.6.3, p. 31 | "Remark that these model selection criteria may not be valid in machine learning models, such as neural networks, as these models do not use MLE for model fitting." ([AIT] p. 31) "AIC and BIC only give preference to a model, but they do not confirm that the selected model is suitable" ([AIT] p. 31) | As [WM]: no AIC/BIC for networks. |
| TB-AIT-5 | §5.3.5, pp. 100–103 | "is not a sensible problem that we should try to solve." ([AIT] p. 100) "decreases as long as we learn systematic effects, and it starts to increase" ([AIT] p. 102) "Of course, the validation sample V should be sufficiently large to obtain a credible stopping rule (that itself is not dominated by the noise in V)." ([AIT] p. 103) "Often one takes 20% or 10% of the learning data L as validation sample V, depending on the sample size n." ([AIT] p. 103) | Early stopping is the network's main capacity control; a small validation set gives a noisy $t^\star$ (relevant to a 50/50 split of a small portfolio). |
| TB-AIT-6 | §5.1, p. 94; §5.2, p. 96; §5.3.8, pp. 105–106 | "The choice of a good network architecture does not only depend on the predictive problem to be solved, but also on the selected model fitting algorithm" ([AIT] p. 94) "There is no hope to find a (best) parsimonious FNN (on finite samples)." ([AIT] p. 96) "is not a target that one should try to achieve, but one has to accommodate with the fact that the selected architectures should exceed a minimal complexity bound above parsimony for SGD training to be successful." ([AIT] p. 106) "we designed a standard FNN architecture of depth d = 3 with (q1, q2, q3) = (20, 15, 10) neurons in the three FNN layers." ([AIT] p. 106) | *Do not optimise the architecture* (our summary of these passages): the source of the (20, 15, 10) default and the reason actuarial papers rarely search depth or width. |
| TB-AIT-7 | §5.3.4, p. 100 | "The learning rate and the momentum parameter are hyper-parameters that need to be fine-tuned by the modeler." ([AIT] p. 100) "this software often comes with suitable standard values for these hyper-parameters, i.e., they are ready-to-use." ([AIT] p. 100) | The learning rate is acknowledged as a hyperparameter but left at the software's value. |
| TB-AIT-8 | §5.3.1, p. 97; §5.7, p. 114 | "should be selected at random to avoid that the gradient descent" ([AIT] p. 97) "We recommend to initialize the network weights so that the SGD algorithm precisely starts in the MLE fitted GLM (5.25)." ([AIT] p. 114) | Random initialisation for plain networks; a GLM start for CANN/LocalGLMnet (`HP-M20`). |
| TB-AIT-9 | §2.3.2, p. 48; §5.3.2, p. 99 | "Select an embedding dimension b ∈ N, this is a hyper-parameter that needs to be selected by the modeler, typically b ≪ K." ([AIT] p. 48) "one should regularize the entity embedding to receive a successful network training that prevents from over-fitting." ([AIT] p. 99) | Embeddings need a dimension and, the book adds, regularisation. |
| TB-AIT-10 | §5.3.6, pp. 103–105 | "Thus, gradient descent methods can only get the regularized network weights small, but then these small weights need to be set manually to (exactly) zero" ([AIT] p. 104) "Finally, SGD training can be improved by regularization and drop-out, this is part of hyper-parameter tuning and it needs to be checked case by case." ([AIT] p. 105) "Typically, more regularization and drop-out is needed with increasing sizes of the FNN architectures." ([AIT] p. 105) | Penalty weight and dropout rate are hyperparameters "to be checked case by case"; no values given. |
| TB-AIT-11 | §5.3.7, p. 105 | "suitable batch sizes s are of magnitude 2000 to 5000 instances for the FNN architectures studied." ([AIT] p. 105) | A batch-size range calibrated on frequency data with many thousands of policies; not transferable to a triangle. |
| TB-AIT-12 | §5.2, p. 96; §5.3.5, p. 103; §5.3.8, p. 106; §5.4.2, p. 108 | "To be able to replicate results, the fitting procedure has to be designed very carefully and seeds of random number generators need to be stored to be able to track and replicate the specific solutions" ([AIT] p. 96) "However, this may be reversed for other random partitions." ([AIT] p. 103) "All these items make the early stopped SGD solutions (highly) non-unique." ([AIT] p. 106) "there are less frequent covariate combinations where these fluctuations were up to 40%" ([AIT] p. 108) | Seeds and partitions change the answer; store them and do not compare configurations on one run. |
| TB-AIT-13 | §5.4, pp. 108–109 | "only the initialization and partitioning is done with a different random seed" ([AIT] p. 108) "a good value for M is in the range of 10 to 20" ([AIT] p. 109) "Moreover, computing the nagging predictor can be time-consuming because one needs to fit the network architecture M times." ([AIT] p. 109) | The rule for $M$ (10–20) and its cost. |
| TB-AIT-14 | §5.5, p. 110 | "Select a suitable FNN architecture, a momentum-based SGD algorithm, and a suitable batch size" ([AIT] p. 110) "Apply a balance correction method to comply with the balance property (4.4); see Remark 5.4." ([AIT] p. 110) "Repeat this M times to compute the nagging predictor (5.19)." ([AIT] p. 110) | The recipe: fixed architecture, early stopping, balance correction, nagging. Richman & Wüthrich (2026a, b) are the clearest reserving examples in the folder of all four steps. |
| TB-AIT-15 | §7.4, pp. 140–141 | "Successful GBM fitting is very sensitive to reasonably chosen hyper-parameters." ([AIT] p. 140) "In most cases, these hyper-parameters are selected by a grid search with (cross-)validation or by a randomized grid search." ([AIT] p. 140) "There are specialized tools like Optuna that are designed for hyper-parameter optimization; see Akiba et al. \[5\]." ([AIT] p. 141) "whereas FNNs more strongly suffer from over-fitting issues resulting in under-fitting (through a too early stopping)." ([AIT] p. 141) | The book's only search methodology is for boosting. The last sentence is a comparison: networks lose predictive power through early stopping that comes too early. |
| TB-AIT-16 | §8.5.4, p. 185 | "The probability α is treated as a hyper-parameter, and it can be optimized via grid search." ([AIT] p. 185) "the best results have been obtain by a choice of roughly α = 95%, in our CT notebook we used 90% which also gives excellent results." ([AIT] p. 185) | The one network hyperparameter the book tunes by grid. |
| TB-AIT-17 | §5.8, p. 116 | "this comes at the price of higher computational efforts and more hyper-parameter tuning." ([AIT] p. 116) "it is unclear whether these higher computational and hyper-parameter tuning efforts are justified" ([AIT] p. 116) | More flexible architectures (KANs) cost more tuning; the book doubts it pays. |

## [GBC] Goodfellow, Bengio & Courville (2016), *Deep Learning*

The book's position: hyperparameters are chosen on a validation set that is never the test set; choose them manually by reasoning about capacity, or automatically by grid, random or model-based search, with random search the recommended default; early stopping is itself hyperparameter selection.

| Label | Where | Quotation | Implication |
|---|---|---|---|
| TB-GBC-1 | §5.3, pp. 120–121 | "The values of hyperparameters are not adapted by the learning algorithm itself (though we can design a nested learning procedure where one learning algorithm learns the best hyperparameters for another learning algorithm)." ([GBC] p. 120) "If learned on the training set, such hyperparameters would always choose the maximum possible model capacity, resulting in overfitting (refer to figure 5.3)." ([GBC] p. 121) "Since the validation set is used to “train” the hyperparameters, the validation set error will underestimate the generalization error, though typically by a smaller amount than the training error. After all hyperparameter optimization is complete, the generalization error may be estimated using the test set." ([GBC] p. 121) | Hyperparameters cannot be learned on the training set; validation error is itself optimistically biased once used for selection. |
| TB-GBC-2 | §5.3, p. 121 | "It is important that the test examples are not used in any way to make choices about the model, including its hyperparameters. For this reason, no example from the test set can be used in the validation set." ([GBC] p. 121) | The rule that 10 of the 50 documents break (Section 4.5). |
| TB-GBC-3 | §5.3.1, pp. 122–123 | "The most common of these is the k-fold cross-validation procedure, shown in algorithm 5.1, in which a partition of the dataset is formed by splitting it into k non-overlapping subsets." ([GBC] p. 122) "While these confidence intervals are not well-justified after the use of cross-validation, it is still common practice to use them to declare that algorithm A is better than algorithm B only if the confidence interval of the error of algorithm A lies below and does not intersect the confidence interval of algorithm B." ([GBC] p. 123) | $K$-fold CV for small data; no recommended $K$. |
| TB-GBC-4 | §5.2, p. 114 | "Typically, generalization error has a U-shaped curve as a function of model capacity." ([GBC] p. 114) | The U-curve that capacity hyperparameters (width, depth, epochs, dropout, $L^2$) move along. |
| TB-GBC-5 | §6.3, p. 192; §6.4, p. 198 | "It is usually impossible to predict in advance which will work best. The design process consists of trial and error, intuiting that a kind of hidden unit may work well, and then training a network with that kind of hidden unit and evaluating its performance on a validation set." ([GBC] p. 192) "The ideal network architecture for a task must be found via experimentation guided by monitoring the validation set error." ([GBC] p. 198) | Activation and architecture are chosen by experiment on the validation set, which is the opposite of [WM]/[AIT]'s fixed default. |
| TB-GBC-6 | §7.1, p. 230 | "where α ∈ \[0, ∞) is a hyperparameter that weights the relative contribution of the norm penalty term, Ω, relative to the standard objective function J. Setting α to 0 results in no regularization. Larger values of α correspond to more regularization." ([GBC] p. 230) "In the context of neural networks, it is sometimes desirable to use a separate penalty with a different α coefficient for each layer of the network. Because it can be expensive to search for the correct value of multiple hyperparameters, it is still reasonable to use the same weight decay at all layers just to reduce the size of search space." ([GBC] p. 230) | One weight-decay coefficient for all layers, to save search. |
| TB-GBC-7 | §7.8, pp. 247–248, 252 | "This strategy is known as early stopping. It is probably the most commonly used form of regularization in deep learning." ([GBC] p. 247) "Most hyperparameters must be chosen using an expensive guess and check process, where we set a hyperparameter at the start of training, then run training for several steps to see its effect. The “training time” hyperparameter is unique in that by definition a single run of training tries out many values of the hyperparameter." ([GBC] p. 248) "Early stopping therefore has the advantage over weight decay that early stopping automatically determines the correct amount of regularization while weight decay requires many training experiments with different values of its hyperparameter." ([GBC] p. 252) | Early stopping is the cheapest hyperparameter selection there is, and a regulariser (towards the starting point). |
| TB-GBC-8 | §7.11, pp. 257–258 | "Differences in random initialization, random selection of minibatches, differences in hyperparameters, or different outcomes of non-deterministic implementations of neural networks are often enough to cause different members of the" ([GBC] p. 257) "ensemble to make partially independent errors." ([GBC] p. 258) "It is common to use ensembles of five to ten neural networks—Szegedy et al. (2014a) used six to win the ILSVRC— but more than this rapidly becomes unwieldy." ([GBC] p. 258) | Seed differences are enough to build an ensemble; 5–10 members is common. |
| TB-GBC-9 | §7.12, pp. 259, 262, 265 | "The probability of sampling a mask value of one (causing a unit to be included) is a hyperparameter fixed before training begins." ([GBC] p. 259) "Even 10-20 masks are often sufficient to obtain good performance." ([GBC] p. 262) "Because dropout is a regularization technique, it reduces the effective capacity of a model. To offset this effect, we must increase the size of the model." ([GBC] p. 265) "When extremely few labeled training examples are available, dropout is less effective." ([GBC] p. 265) | Dropout needs a larger model and helps little with very few examples, which is the triangle situation. |
| TB-GBC-10 | §8.1.3, p. 279 | "Small batches can offer a regularizing effect (Wilson and Martinez, 2003), perhaps due to the noise they add to the learning process. Generalization error is often best for a batch size of 1." ([GBC] p. 279) "Training with such a small batch size might require a small learning rate to maintain stability due to the high variance in the estimate of the gradient." ([GBC] p. 279) | Batch size and learning rate interact; tune them together. |
| TB-GBC-11 | §8.3.1–8.3.2, pp. 294, 298 | "In practice, it is necessary to gradually decrease the learning rate over time, so we now denote the learning rate at iteration k as εk." ([GBC] p. 294) "Common values of α used in practice include .5, .9, and .99. Like the learning rate, α may also be adapted over time. Typically it begins with a small value and is later raised." ([GBC] p. 298) | A schedule is needed for SGD; momentum values are conventional. |
| TB-GBC-12 | §8.4, pp. 301, 304 | "Our understanding of how the initial point affects generalization is especially primitive, offering little to no guidance for how to select the initial point." ([GBC] p. 301) "When computational resources allow it, it is usually a good idea to treat the initial scale of the weights for each layer as a hyperparameter, and to choose these scales using a hyperparameter search algorithm described in section 11.4.2, such as random search. The choice of whether to use dense or sparse initialization can also be made a hyperparameter." ([GBC] p. 304) "A good rule of thumb for choosing the initial scales is to look at the range or standard deviation of activations or gradients on a single minibatch of data." ([GBC] p. 304) | The initial weight scale is itself a hyperparameter; starting at a fitted GLM (`HP-M20`) removes it for the output layer. |
| TB-GBC-13 | §8.5, pp. 306, 309–310 | "Neural network researchers have long realized that the learning rate was reliably one of the hyperparameters that is the most difficult to set because it has a significant impact on model performance." ([GBC] p. 306) "The choice of which algorithm to use, at this point, seems to depend" ([GBC] p. 309) "largely on the user’s familiarity with the algorithm (for ease of hyperparameter tuning)." ([GBC] p. 310) | No principled choice of optimiser exists; the papers' choice follows their software and their textbook. |
| TB-GBC-14 | §11.2, p. 425 | "A reasonable choice of optimization algorithm is SGD with momentum with a decaying learning rate (popular decay schemes that perform better or worse on different problems include decaying linearly until reaching a fixed minimum learning rate, decaying exponentially, or decreasing the learning rate by a factor of 2-10 each time validation error plateaus). Another very reasonable alternative is Adam." ([GBC] p. 425) "Unless your training set contains tens of millions of examples or more, you should include some mild forms of regularization from the start. Early stopping should be used almost universally." ([GBC] p. 425) | The recommended baseline: SGD with momentum and decaying rate (or Adam), mild regularisation and early stopping from the start. |
| TB-GBC-15 | §11.3, p. 427 | "It is therefore recommended to experiment with training set sizes on a logarithmic scale, for example doubling the number of examples between consecutive experiments." ([GBC] p. 427) | Learning curves in the amount of data; relevant when epochs are transferred from half to full data. |
| TB-GBC-16 | §11.4.1, pp. 428–430 | "Automatic hyperparameter selection algorithms greatly reduce the need to understand these ideas, but they are often much more computationally costly." ([GBC] p. 428) "In the idealized quadratic case, this occurs if the learning rate is at least twice as large as its optimal value (LeCun et al., 1998a)." ([GBC] p. 429) "Usually the best performance comes from a large model that is regularized well, for example by using dropout." ([GBC] p. 430) "The brute force way to practically guarantee success is to continually increase model capacity and training set size until the task is solved." ([GBC] p. 430) | Manual tuning is a capacity argument; the largest well-regularised model usually wins. |
| TB-GBC-17 | §11.4.2, p. 432 | "Neural networks can sometimes perform well with only a small number of tuned hyperparameters, but often benefit significantly from tuning of forty or more hyperparameters." ([GBC] p. 432) "we are trying to find a value of the hyperparameters that optimizes an objective function, such as validation error, sometimes under constraints (such as a budget for training time, memory or recognition time)." ([GBC] p. 432) "Unfortunately, hyperparameter optimization algorithms often have their own hyperparameters, such as the range of values that should be explored for each of the learning algorithm’s hyperparameters." ([GBC] p. 432) | Automatic search has its own hyperparameters (ranges, budget), which must be reported too. |
| TB-GBC-18 | §11.4.3–11.4.5, pp. 434–436 | "Grid search usually performs best when it is performed repeatedly." ([GBC] p. 434) "In fact, as illustrated in figure 11.2, a random search can be exponentially more efficient than a grid search, when there are several hyperparameters that do not strongly affect the performance measure." ([GBC] p. 435) "Currently, we cannot unambiguously recommend Bayesian hyperparameter optimization as an established tool for achieving better deep learning results or for obtaining those results with less effort." ([GBC] p. 436) | Grid for ≤ 3 hyperparameters, random otherwise, Bayesian with caution. |
| TB-GBC-19 | §11.5, p. 440 | "As suggested by Bottou (2015), we would like the magnitude of parameter updates over a minibatch to represent something like 1% of the magnitude of the parameter, not 50% or 0.001% (which would make the parameters move too slowly)." ([GBC] p. 440) | A numerical check for the learning rate that no paper in the folder uses. |
| TB-GBC-20 | §15.1, p. 534 | "Neural network training is non-deterministic, and converges to a different function every time it is run." ([GBC] p. 534) | The reason seeds matter. |

## [H] Hindley (2017), *Claims Reserving in General Insurance*

Hindley contains no neural networks, no machine learning and none of the words "hyperparameter", "cross-validation", "early stopping" or "dropout". What it does have is the reserving profession's own versions of hyperparameters (the averaging period, the tail curve, the BF prior, the Cape Cod decay factor), all set by judgement supported by diagnostics, and three out-of-time checks that are the natural selection signals for a reserving network.

| Label | Where | Quotation | Implication |
|---|---|---|---|
| TB-H-1 | §3.2.3, pp. 47–48 | "those most commonly used in practice (at least in the UK currently) are probably the CSA and CSA Recent (e.g. CSA4)" ([H] p. 47) "Graphs can be useful in deciding on the groups of cohorts to use for each estimator" ([H] p. 48) | The averaging period $n$ is a reserving "hyperparameter" chosen by judgement from graphs; the analogue of `HP-M06`. |
| TB-H-2 | §3.2.6, p. 60 | "In doing so, it will be important to use enough data points, though, to avoid over-fitting to the data." ([H] p. 60) | The book's only explicit over-fitting warning (for tail curves). |
| TB-H-3 | §3.6, pp. 126, 132–133 | "It is selected based upon the degree of confidence (i.e. reliability) that there is assumed to be in the CL ULR for the Target Cohort itself" ([H] p. 126) "The decay factor is selected as 0.75." ([H] p. 132) "whatever decay factor is chosen, the resulting prior assumption will inevitably need to be scrutinised to assess whether it is appropriate for the particular cohort(s)." ([H] p. 133) | The GCC decay factor is set by reliability judgement and then scrutinised, not optimised. |
| TB-H-4 | §3.4, p. 82 | "the reasonableness of the estimated ultimate is then critically dependent on the appropriateness of the prior." ([H] p. 82) "this might be based on selecting a particular % developed (e.g. 40%, for illustrative purposes only), so that when the claims are estimated to be less developed than the chosen value, a BF method will be used" ([H] p. 82) | The BF/CL switching point is a threshold hyperparameter chosen by rule of thumb (`HP-M05`). |
| TB-H-5 | §4.10.2, p. 310 | "Consideration therefore needs to be given to the selection of cohort and development period frequency when applying stochastic methods, and in some cases the sensitivity of results to alternative options may need investigating." ([H] p. 310) | Granularity (cohort and development period length) is itself a design choice with a volume trade-off. |
| TB-H-6 | §5.5, p. 328; §5.7, pp. 332, 334 | "In many situations it will be appropriate to select more than one method for each reserving category" ([H] p. 328) "There are no golden rules or universally applicable procedures that define the factors to take into account when selecting the final results derived from the core technical reserving analysis" ([H] p. 332) "some practitioners combine the results produced by the different methods using some form of simple or weighted averaging to produce the selected ultimate." ([H] p. 334) | Method selection and blending are judgemental; averaging across methods is the reserving counterpart of ensembling. |
| TB-H-7 | §4.10.3, pp. 311–312; §4.3.3, p. 190 | "Assuming that the required data is available, then the core component of this assessment is to consider whether the assumptions that underpin the method are valid for the particular dataset." ([H] p. 311) "If the model is a “good” fit to the data, then there should be no obvious trends in the residuals" ([H] p. 312) "standard statistical goodness-of-fit tests such as Akaike Information Criterion and Bayesian Information Criterion." ([H] p. 190) | Model checking by residuals and, for GLMs, by information criteria. |
| TB-H-8 | §4.10.3, p. 314 | "The idea, based on an approach often used in time series applications, is to remove a diagonal from the data triangle, apply the stochastic method, and then compare the actual and fitted data on that diagonal" ([H] p. 314) "These one-step-ahead prediction errors or validation residuals can sometimes show patterns that are not evident in the other types of residual plots, and hence can be a useful part of overall method validation." ([H] p. 314) | The removed-diagonal test: the one-step-ahead validation signal (`HP-V2`/`HP-V4`) that a reserving network should be tuned on. |
| TB-H-9 | §4.1, p. 149; §4.10.4, pp. 318–319 | "One simple way of assessing the Total Uncertainty is to look at how wrong the estimates made in the past have been relative to the corresponding actual claims outgo" ([H] p. 149) "Backtesting of results, for example by considering the reasonableness of the percentiles (derived from the stochastic reserving methods) that are implied by known historical movements in ultimate claims." ([H] p. 318) "further backtesting can be done on industry or synthetic data, as opposed to data specific to a particular reserving exercise." ([H] p. 319) | Back-testing over several past valuations, including on synthetic data: the rolling-origin signal. |
| TB-H-10 | §6.3, pp. 353–355 | "First, it can be compared with the actual claims development in the same period, to help determine whether the estimated ultimate claims at the previous valuation date need revising and, if so, in what direction and by what order of magnitude." ([H] p. 353) "It can be appropriate to set tolerances for the observed A − E by cohort, whereby if the difference is within a specified range, no adjustment is made to the previously estimated ultimates." ([H] p. 354) "In some instances, the A vs E analysis might suggest that the reserving model (i.e. the methods and assumptions) selected at the previous valuation date needs revising." ([H] p. 355) | A vs E with tolerances: a reserve-level signal (`HP-V7`) and a monitoring rule for re-tuning. |
| TB-H-11 | pp. 214, 282 | "It can be seen that, as the number of parameters increases, the factor will also increase, and so the estimation variance produced by the bootstrap will increase." ([H] p. 214) "as a means of avoiding over-parameterisation." ([H] p. 282) | Parameter count enters the bootstrap scaling; over-parameterisation is to be avoided. |
| TB-H-12 | §5.4, p. 326 | "An example is so-called “anchoring”, which refers to the tendency to place too much reliance on one piece of information, leading to possibly biased results." ([H] p. 326) | The behavioural risk of manual tuning (anchoring on the first value tried). |
| TB-H-13 | §4.4.5, p. 237; §4.9, p. 294 | "This uncertainty around the results will exist regardless of whether 100, 1,000 or 10 million simulations are used in the bootstrap procedure." ([H] p. 237) "The obvious solution is to increase the number of simulations, and / or perhaps use the same random number set for each reserving category within the bootstrap process." ([H] p. 294) | Monte-Carlo noise and common random numbers: the reserving version of seed control. |

## [ISL] James, Witten, Hastie & Tibshirani, *An Introduction to Statistical Learning* (1st edition) — pending

The PDF is not among the project files, and the download from the authors' site ([statlearning.com](https://www.statlearning.com)) was refused by this environment's network proxy, so no ISL page is cited here. Two things are already clear and are stated without page numbers:

* The **first edition has no neural-network chapter** (deep learning was added in the second edition, 2021). Its contribution to this document would therefore be the **selection machinery**, not network advice: the validation-set approach, leave-one-out and $k$-fold cross-validation and the bootstrap (resampling chapter), choosing a model's complexity and a shrinkage penalty by cross-validation, the one-standard-error rule, $C_p$/AIC/BIC/adjusted $R^2$ (model-selection chapter), and tuning tree and SVM parameters by cross-validation.
* When you add the PDF to the project, the rows TB-ISL-1 … will be added in the same format, with printed pages, and the "one-standard-error rule" will become a new method in Table 2.1 (none of the four books above describes it, and no paper in the folder uses it).

# The shipped code: what it shows that the papers do not

A search of every `.py`, `.R`, `.yaml`, `.toml` file and notebook cell of the six code bases for `optuna`, `GridSearch`, `RandomizedSearch`, `kerastuner`, `keras_tuner`, `tfruns`, `param_grid`, `n_trials`, `hyperopt` and `BayesSearch` returns **no hits**. None of the code bases ships a hyperparameter search. Where a search was done, it exists only in the paper's prose.

| Code base | Network | How the hyperparameters are set in code | Early stopping / validation in code | Seeds and repeats | What the code adds to the paper |
|---|---|---|---|---|---|
| Manai (2026), `claims_reserving` (Python) | PyTorch MLP (32, 16), AdamW; scikit-learn residual MLP (24, 12) on a chain-ladder backbone | versioned YAML; `config/research.yaml` declares `tuning_policy: fixed_a_priori`; the only sweep is a prespecified ablation of the shrinkage $\lambda\in\{0,0.15,0.45,0.90\}$ | PyTorch: hand-written patience 35 on the validation Huber loss, best weights restored; scikit-learn: built-in, validation $R^2$, patience 10, only if ≥ 25 cells. Both validate on a **random 20 % of triangle cells** | one seed per run (42, 20260807 or the scenario seed); no ensemble | the PyTorch learning rate **0.003** is a dataclass default (`neural.py:53`) that no configuration file sets, although the paper says exact values are "stored in the effective configuration" |
| Zelený (2026), `python_reserving` + notebook | scikit-learn two-part MLP (192, 96, 48); Keras per-transition network (24), tanh, dropout 0.30, RMSprop | hard-coded in notebook calls; values match the thesis | scikit-learn: random 10 %, patience 20; Keras: `validation_split = 0.1` (the last 10 % of rows; the data are sorted by accident year), patience 12, best weights restored | seed 42 for the point forecast; $K=20$ seed ensemble and $B=100$ bootstrap for uncertainty only | the triangle network is labelled "Tuned default from Section 17.2 anti-overfit sweep" and `…-NN-Tuned`, but no sweep is shipped and the thesis describes none |
| Richman, Scognamiglio & Wüthrich (2025), PIN example (R, MTPL frequency) | Keras PIN (not a reserving model) | hard-coded "Select the PIN hyper-parameters" block | `callback_model_checkpoint(save_best_only = T)` over 100 epochs plus `callback_reduce_lr_on_plateau(factor = 0.9, patience = 5)`, `validation_split = 0.1` | 10 networks with seeds 100–109, averaged (nagging) | the comment "define callback for early stopping" sits above a checkpoint callback: the procedure is to train for 100 epochs and keep the best-validation weights, not to stop early |
| Gabrielli (2019) NNDODP notebook (third-party Kaggle re-run, R) | multiple NNDODP (40, 30), tanh, dropout 0.2, $L^2$ 0.001, RMSprop | hard-coded; width, dropout, $L^2$, optimiser, epochs and epoch-averaging match the paper | none: fixed 390 + 20 epochs with snapshot averaging; the paper's 78-model width grid and its epoch selection are **not in the code** | **no seeds**; 100 unseeded re-fits | the batch size (full batch) appears only in the code; the paper does not state it |
| Utulu (2026) | none | – | – | – | chain-ladder workflow only |
| Van Oirbeek (2026), `hgr` | none | – | – | – | negative-binomial chain ladder only |

Three code facts that matter for reading the papers:

1. **`validation_split` holds out the last rows.** The Keras `Model.fit` documentation states that the validation data are selected from the last samples provided, before shuffling. In Zelený's code the rows are sorted by accident year, so the Keras validation set is the latest accident years (a quasi-temporal hold-out that the thesis does not describe). In Richman & Wüthrich (2026b) and in the PIN example, which rows are held out depends on the unstated row order.
2. **Hidden defaults.** Both Manai's learning rate and the Gabrielli line's RMSprop learning rate are defaults that never appear in the text as numbers (`HP-M03`).
3. **Claimed tuning that is not shipped.** Zelený's "anti-overfit sweep" and Gabrielli's width grid are described (in a code comment and in the paper respectively) but cannot be re-run from the shipped code.

Excerpts (verbatim from the files):

```python
# Manai 2026, src/claims_reserving/models/neural.py:50-57
    hidden_units: tuple[int, int] = (32, 16)
    epochs: int = 350
    patience: int = 35
    learning_rate: float = 0.003
    dropout: float = 0.05
    validation_fraction: float = 0.2
    early_stopping_min_delta: float = 1e-5
    weight_decay: float = 1e-3
```

```python
# Zelený 2026, notebook_analysis.ipynb cell 61 (inside a ''' string, i.e. not executed)
# Tuned default from Section 17.2 anti-overfit sweep.
```

```{r pin-excerpt}
# Richman et al. 2025, "01_a PIN - fit networks.r" L265-287 (excerpt: some lines omitted, closing brace added)
T0 <- 10     # number of fitted PINs
for (t in 1:T0){
   seed  <- 100+t-1
   model <- PIN(seed=seed, q0=qq, kk=kk)
   # initialize to the null model
   w0 <- get_weights(model)
   w0[[length(w0)-1]] <- array(0, dim=dim(w0[[length(w0)-1]]))
   w0[[length(w0)]] <- array(log(mu.hom), dim=dim(w0[[length(w0)]]))
   set_weights(model, w0)
   adam = optimizer_adam(learning_rate = 0.001)
   model %>% compile(optimizer = adam, loss = "poisson")
   ## define callback for early stopping
   model_write = callback_model_checkpoint(path1, save_best_only = T, verbose = 1, save_weights_only = T)
   learn_rate = callback_reduce_lr_on_plateau(factor = 0.9, patience = 5, cooldown = 0, verbose = 1)
}
```

```{r nndodp-excerpt}
# Gabrielli 2019 NNDODP notebook, cell 18 L1-6
# training epochs (values derived in [4] using train-validation-split):
epochs <- 390     # number of epochs
epochs.cont <- 20 # for averaging

# Train the neural network
fit <- model %>% fit(x = x.upper, y = y.upper, epochs = epochs, batch_size = length(x.upper[[1]]), verbose = 0)
```

# Recurring referee flags

Each flag is a pattern that appears in more than one document. The evidence column quotes the document; the textbook column gives the rule it runs against. These were found in the primary texts; your own `NOTE_` files were not consulted.

| Label | Flag | Where it occurs (evidence) | Textbook rule |
|---|---|---|---|
| `HP-F01` | **Selection on the test data or the known lower triangle** | 10 confirmed documents, 3 possible: Section 4.5 | "It is important that the test examples are not used in any way to make choices about the model, including its hyperparameters. For this reason, no example from the test set can be used in the validation set." ([GBC] p. 121) |
| `HP-F02` | **$t^\star$ found on part of the data, reused on all of it** | Gabrielli et al. 2018: "For this reason, we decide to run the gradient descent algorithm on the full data DI\|m for 300 iterations (for exactly this network architecture). Note that, for simplicity, we use 300 iterations for all LoBs." (Gabrielli et al. 2018, PDF p. 13, §3.3.2); Gabrielli 2020 (80 % → 100 %, fixed batch 10,000: "After this training/validation analysis, we train the neural network using all n individual claims for the chosen number of epochs." (Gabrielli 2020, PDF p. 19, §5.4)); Härkönen: "Hence, the models are fitted again on the entire upper triangle (training and validation data) and predictions are made on the lower triangle." (Härkönen MSc 2021, PDF p. 35, §3.2); Gabrielli 2019 (400 epochs on the full triangles after selection on half) | "For example, there is not a good way of knowing whether to retrain for the same number of parameter updates or the same number of passes through the dataset." ([GBC] p. 249) |
| `HP-F03` | **One global setting across heterogeneous sub-portfolios** | lines of business: "For this reason, we decide to run the gradient descent algorithm on the full data DI\|m for 300 iterations (for exactly this network architecture). Note that, for simplicity, we use 300 iterations for all LoBs." (Gabrielli et al. 2018, PDF p. 13, §3.3.2); 200 Schedule P triangles from four lines: "As stated before, the model has been fitted individually to each of the 200 triangles selected by Meyers (2015) from the Schedule P of the NAIC Annual Statement." (Ramos-Pérez et al. 2022, PDF p. 6, §4.1); one tuning triangle for 50: "The hyper-parameter selection algorithm was only run on a single triangle from each environment. The chosen model for that triangle was used to fit all 50 triangles of that environment. This was done to increase the efficiency of modelling." (Al-Mudafer et al. 2021, PDF p. 36, App. D); one simulated data set for 50: "Once a hyperparameter combination has been chosen, that combination is then used for training and evaluating the model on each of the fifty datasets." (Avanzi et al. 2025, PDF p. 14, §4). Guo is the exception: "The best values differed materially across the LOBs, so hyperparameters should be tuned per business line." (Guo 2026, PDF p. 20, §6.2) | [WM] and [AIT] assume one portfolio; [GBC] tunes per task |
| `HP-F04` | **Selection from a single split and a single seed** | Gabrielli 2019's width choice rests on near-ties (1218.6 vs 1221.2 vs 1221.9; Appendix A): "The three combinations (q1 , q2 ) with the smallest average validation loss observed over 1’000 epochs are presented in Table 6. We get the best result for combination (q1 , q2 ) = (30, 25)." (Gabrielli 2019, PDF p. 17, §3.2.1); Avanzi et al. 2025: "Consequently, we train the model with each hyperparameter combination once, and evaluate its performance on the validation set." (Avanzi et al. 2025, PDF p. 13, §3.4); Guo's screening stage: "The screening-stage winner (Config 2, screening MAPE 8.26%) dropped to rank 5 after multiseed validation (mean 8.66%, σ = 0.198%), confirming that single-seed rankings can be misleading. The validated winner was Config 99 (mean 8.39%, σ = 0.000%), with 256 GRU units, low dropout (1.5%), and a conservative learning rate (1.07 × 10−4 )." (Guo 2026, PDF p. 17, §5.2) | "To reduce the randomness coming from early stopping with different seeds, we average the deviance losses over 20 runs" ([WM] p. 460) |
| `HP-F05` | **Optimum on the edge of the searched range** | Wüthrich 2017 ($(2,2)$ for $j\ge3$); Yeldan & Karabey (50 epochs, smallest architecture); Avanzi et al. 2025 (learning rate 0.01 for all models); Hiabu et al. (10 nodes, $\epsilon=0$); Côté et al. (learning rate 0.01, the maximum); Gabrielli 2019 (LoB 1 at the 1,000-epoch limit). All from Appendix A | "the smallest and largest element of each list is chosen conservatively, based on prior experience with similar experiments, to make sure that the optimal value is very likely to be in the selected range." ([GBC] p. 434) |
| `HP-F06` | **Epoch cap binding** | Lindholm et al.: "Almost all LoBs need close to the maximum of 10,000 epochs and allowing for more epochs may yield better results than those we will acquire. For the payment part of the model, the minimum losses are reached much earlier for most LoBs." (Lindholm et al. 2020, PDF p. 90, §4); Al-Mudafer et al.: "Training would usually last for several thousand epochs, with higher dropout rates and larger networks often requiring up to 10-15 thousand iterations. A 10000 epoch limit was set when running the hyper-parameter optimisation algorithm, in order to increase efficiency." (Al-Mudafer et al. 2021, PDF p. 16, §4) | "of course, in practice we need to continue beyond this minimal validation loss to ensure that we have really found the minimum." ([WM] p. 297) |
| `HP-F07` | **Tuning budget differs from the final fit** | Hiabu et al.: tuning with `epochs = 300`, patience 20 ("patience = 20), epochs = as.integer(300), num\_workers = 0, verbose = FALSE, verbose.cv = TRUE, folds = 3, parallel = FALSE, random\_seed = as.integer(Sys.time()))" (Hiabu et al. 2025, PDF p. 17, §2.4.2; identical code again on PDF p. 18, §2.5.1)), final fit with patience 350 ("num\_layers = 2, early\_stopping = TRUE, patience = 350, verbose = FALSE, network\_structure = NULL, num\_nodes = 10, activation = "LeakyReLU", optim = "SGD", lr = 0.02226655, xi = 0.4678993, epsilon = 0, batch\_size = 5000L, epochs = 5500L," (Hiabu et al. 2025, PDF p. 22, §2.6)); Schneider & Schwab refit on training + validation data with no early-stopping signal ("Finally, we trained the model with the best hyperparameters on both the training and validation sets to predict the test set." (Schneider–Schwab 2025, PDF p. 35, Appendix B)) | [GBC] Algorithm 7.2 keeps the step count, p. 249 |
| `HP-F08` | **Unequal tuning effort between compared models** | Spedicato & Richman: the winning transformer untuned ("the MLP and GBT approaches, even without hyperparameter tuning." (Spedicato–Richman 2025, PDF p. 20)); Guo: only the baseline tuned (Appendix A); Côté et al.: CTGAN untuned; Yeldan & Karabey: baselines' settings unreported; Gueye et al. tune their model per table ("RC-TGAN1 (based on conditional data of the parent row) and RC-TGAN2 (extended to grandparent rows) are implemented by modifying the source code of CTGAN, packaged in the SDV library. The hyperparamater tuning of the RCTGAN neural networks is carried out separately for each single table." (Gueye et al. 2023, PDF p. 4, §4.2)) with no statement about the baseline | "When comparing machine learning algorithm A and machine learning algorithm B, it is necessary to make sure that both algorithms were evaluated using the same hand-designed dataset augmentation schemes." ([GBC] p. 241) The same principle applies to tuning budgets. |
| `HP-F09` | **Text, table and code disagree** | Avanzi et al. 2025: patience 10 in the text ("After some initial testing, we decided to use a maximum of 200 epochs with a patience of 10 epochs. Once training stops, the weights are ‘restored’ to those that produced the smallest observed loss on the validation set." (Avanzi et al. 2025, PDF p. 26, App. D)), 5 in Table D.6; Noordhoek: "All networks are trained for 500 epochs, with a single iteration per epoch." (Noordhoek MSc 2025, PDF p. 40, §3.3) vs "All networks are trained for 300 epochs, with a single iteration per epoch." (Noordhoek MSc 2025, PDF p. 57, §4.2); Qiu: "Since there might be a local minimum, the number of repetitions should not be too small. Meanwhile, a large number of repetitions can be time-consuming. Therefore, 500 epochs are the standard number of times that is used frequently." (Qiu MSc 2019, PDF p. 44, §3.2) vs `maxit = 100` in the code; Usman: "DropOut (0.20)" (Usman PhD 2024, PDF p. 143, Table 4.1) vs "nn . add ( Dropout (0.05) )" (Usman PhD 2024, PDF p. 175, Code Listing 4.3); LocalGLMnet: $q_4=8$ in the text ("We refrain from doing so, but we fit the LocalGLMnet architecture (2.7) using the identity link for g, a network of depth d = 4 having (q0 , q1 , q2 , q3 , q4 ) = (8, 20, 15, 10, 8) neurons and as activation functions φm we choose the hyperbolic tangent function for m = 1, 2, 3 and the linear function for m = 4." (Richman–Wüthrich 2021 LocalGLMnet, PDF p. 9, §3.1)) vs `units=40` in Listing 1; Cai PhD: "As shown in Figure 2.6, the cross-validation error was evaluated across different sequence lengths, with a length of nine identified as optimal for the DT model." (Cai PhD 2025, PDF p. 53, §2.4) vs "To select a suitable block size, we evaluated the validation error of DT across different sequence lengths and found that the longest sequence (I) minimized the validation error (Figure 2.6). We adopt this length, assuming it best captures the within-block temporal dependence, thereby justifying the approximate exchangeability of blocks." (Cai PhD 2025, PDF p. 130, App. A.3); Härkönen: "The validation loss in the neural network models have quite slow convergence and all of the LoBs need at least 6 000 epochs." (Härkönen MSc 2021, PDF p. 48, §4.2) vs Table 8 (3,000 and 1,207 epochs for the double network); Swallow: "The ADAM optimiser was used for both the generator and the discriminator networks. The learning rate was experimented with during training and varied between 0.01 and 0.0001. RMSProp was another suggestion in the work presented by authors in \[2\] for WGAN and WGAN GP implementations." (Swallow MSc 2023, PDF p. 31, §3.1.5) vs Table 5 ("selected from research"); Richman & Wüthrich 2026a, b: the "Early stopping" row holds a learning-rate schedule ("reduce learning rate on plateau, factor 0.9, patience 5" (Richman–Wüthrich 2026a, PDF p. 14, Table 4; the row label "Early stopping", batch size/epochs "4,096 and 1,000" and learning-validation split "9 : 1" are confirmed from the table image, PDF p. 14)); Schneider & Schwab: the Bayesian-stage bounds come from the top three random-search configurations ("The upper and lower bounds for each parameter in the Bayesian search space were set based on the extremities of these ranges, ensuring a focused yet comprehensive exploration in the subsequent optimization phase. To thoroughly explore the refined search space, we evaluated 32 further configurations." (Schneider–Schwab 2025, PDF p. 33, Appendix B)), yet Table B3 reports Liability-incremental widths of 128, outside that range; Hiabu et al.: "batch\_size &lt;- as.integer(5000L)" (Hiabu et al. 2025, PDF p. 17, §2.5.1) in the objective, against batch sizes of 196–4,508 in the printed Table 5 | – |
| `HP-F10` | **Keras `validation_split` = the last rows** | Richman & Wüthrich 2026b, Zelený 2026, Ferrario et al. 2020 and the PIN example (Section 7); Andersen & Roed-Sørensen: "history = model . fit ( X\_train , y\_train , epochs = 300 , validation\_split = 0.3 , callbacks = \[ es \])" (Andersen–Roed-Sørensen MSc 2021, PDF p. 122, App. .6 code) | – |
| `HP-F11` | **Random (interpolation) validation for an extrapolation task** | the claims split of the Gabrielli line, Härkönen and Lindholm et al.; Kuo 2020's record-level split, which can put records of the same claim on both sides ("We use a random subset of the training set consisting of 5% of the records as the validation set for determining early stopping and scheduling the learning rate." (Kuo 2020 BMDN, PDF p. 19, Training and Scoring)); Cai et al.; Schneider & Schwab; Nicholas; Hiabu et al. (standard $K$-fold) | "These two samples should be mutually independent, and contain i.i.d. data" ([AIT] p. 28) — the condition fails across calendar years |
| `HP-F12` | **Best-of-N instead of averaging** | Rügamer et al. (in-sample), Usman, Côté et al. (`HP-M19`) | "However, this slight improvement in the performance should not be overstated" ([WM] p. 300) |
| `HP-F13` | **Final values not reported** | Avanzi et al. 2026 ("The FNN hyperparameters that we tune are: the number of hidden layers and how many nodes are in each hidden layer, the batch size, the dropout rate, and the learning rate. The validation procedure for tuning hyperparameters is described in section 5.2." (Avanzi et al. 2026, PDF p. 36, App. B.2), no values); Pittarello et al. (candidates only); Belabed et al.; Mahohoho et al.; Gabrielli PhD Paper A ("we still need to determine the optimal neural network in terms of the numbers q1 and q2 of hidden neurons." (Gabrielli PhD 2020, PDF p. 83, Paper A §3.3), no values for 35 networks) | "To be able to replicate results, the fitting procedure has to be designed very carefully and seeds of random number generators need to be stored to be able to track and replicate the specific solutions" ([AIT] p. 96) |
| `HP-F14` | **"Tuned" or "optimal" without a documented search** | Mulquiney: "The tuning parameters were determined using cross-validation and the final neural network consisted of a single hidden layer with 20 units and a weight decay of 0.05." (Mulquiney 2006, PDF p. 2, §2.3); Härkönen speaks of "optimal hyper-parameters" ("after the optimal hyper-parameters are found we predict the outstanding reserves and calculate the prediction error (out-of the sample error) on the lower triangles." (Härkönen MSc 2021, PDF p. 30, §3.1)) where only epochs were tuned ("The only tuning parameter for neural networks that we have considered here is the number of epochs as we have closely followed the architecture of the network from \[4\] and \[5\]." (Härkönen MSc 2021, PDF p. 55, §5)); Zelený's code label (Section 7); Gueye et al. ("RC-TGAN1 (based on conditional data of the parent row) and RC-TGAN2 (extended to grandparent rows) are implemented by modifying the source code of CTGAN, packaged in the SDV library. The hyperparamater tuning of the RCTGAN neural networks is carried out separately for each single table." (Gueye et al. 2023, PDF p. 4, §4.2)) | "Unfortunately, hyperparameter optimization algorithms often have their own hyperparameters, such as the range of values that should be explored for each of the learning algorithm’s hyperparameters." ([GBC] p. 432) |
| `HP-F15` | **Non-reproducible seeds** | Hiabu et al. document the seed argument as "The random seed, integer. It guarantees full replicable code." (Hiabu et al. 2025, PDF p. 10, §2.2.1) but tune with `random_seed = as.integer(Sys.time())` ("patience = 20), epochs = as.integer(300), num\_workers = 0, verbose = FALSE, verbose.cv = TRUE, folds = 3, parallel = FALSE, random\_seed = as.integer(Sys.time()))" (Hiabu et al. 2025, PDF p. 17, §2.4.2; identical code again on PDF p. 18, §2.5.1)); the Gabrielli 2019 notebook sets no seeds; Nicholas could not replicate the original study: "Although neural networks are deterministic, the results of the micro-level reserving study could not be replicated." (Nicholas MSc 2026, PDF p. 46, Ch. 4) | "To be able to replicate results, the fitting procedure has to be designed very carefully and seeds of random number generators need to be stored to be able to track and replicate the specific solutions" ([AIT] p. 96) |
| `HP-F16` | **One validation set, several jobs** | Avanzi et al. 2025 use it for early stopping, selection and the bias-correction factor ("Bias correction is only applied to a model’s predictions after hyperparameter tuning has been conducted. The bias correction factor b is calculated using the model predictions for all observations in the validation set." (Avanzi et al. 2025, PDF p. 9, §2.5)); Ye et al. for selection and early stopping; Schwab PhD Ch. 3 for selection, temperature scaling and the combiner | "Since the validation set is used to “train” the hyperparameters, the validation set error will underestimate the generalization error, though typically by a smaller amount than the training error. After all hyperparameter optimization is complete, the generalization error may be estimated using the test set." ([GBC] p. 121); "Moreover, early stopping will imply that the selected parameters must also be good on the validation data being disjoint (and independent) from the training data." ([WM] p. 515) |

**The single most consequential flag for a reserving thesis** is `HP-F11` combined with `HP-F02`: the Gabrielli-line design finds the number of gradient steps on an interpolation split of half the claims and then applies it to the full data to extrapolate into later calendar years. Nothing in that design tests the extrapolation. The rolling-origin signals of Section 4.4 do.

# R / keras3 skeletons for each method (not run)

These are templates in the style of the papers' listings, written against the `keras3` R interface and `ParBayesianOptimization`. They are **not executed** (`eval = FALSE`) and were not tested here. Each chunk says which method (`HP-M`) and which signal (`HP-V`) it implements, and what it deliberately does differently from the papers. `x`/`y` are the design matrix and response of whatever the "cells" are in your application (triangle cells, or individual-claim records); `split` is a data frame of training and validation indices produced by one of the designs in Section 4.

## A network builder with every in-scope hyperparameter exposed

```{r builder}
library(keras3)

build_net <- function(p, hp, seed) {
  # hp: list(depth, width (vector or scalar), activation, dropout, l2, lr, optimizer)
  set_random_seed(seed)                      # seeds Python, NumPy and TensorFlow
  widths <- rep_len(hp$width, hp$depth)
  model <- keras_model_sequential(input_shape = p)
  for (k in seq_len(hp$depth)) {
    model |> layer_dense(units = widths[k], activation = hp$activation,
                         kernel_regularizer = regularizer_l2(hp$l2))
    if (hp$dropout > 0) model |> layer_dropout(rate = hp$dropout)
  }
  model |> layer_dense(units = 1, activation = "exponential")   # log link, as in the papers
  opt <- switch(hp$optimizer,
                adam    = optimizer_adam(learning_rate = hp$lr),
                rmsprop = optimizer_rmsprop(learning_rate = hp$lr),
                nadam   = optimizer_nadam(learning_rate = hp$lr))
  model |> compile(optimizer = opt, loss = "poisson")
  model
}
# Critique hook: pass hp$lr explicitly even when it equals the default (HP-M03 / HP-F13).
```

## `HP-M13` Early stopping, and the two refit strategies of [GBC] Algorithms 7.2 and 7.3

```{r early-stopping}
fit_early_stopped <- function(x, y, split, hp, seed, max_epochs = 1000, patience = 50,
                              batch_size = nrow(x)) {
  model <- build_net(ncol(x), hp, seed)
  hist <- model |> fit(
    x[split$train, , drop = FALSE], y[split$train],
    validation_data = list(x[split$valid, , drop = FALSE], y[split$valid]),
    epochs = max_epochs, batch_size = batch_size, verbose = 0,
    callbacks = list(callback_early_stopping(monitor = "val_loss", patience = patience,
                                             restore_best_weights = TRUE)))
  v <- hist$metrics$val_loss
  list(model = model, val_loss = v, t_star = which.min(v),
       train_loss_at_t_star = hist$metrics$loss[which.min(v)])
}

# Variant (c): smoothed curve, as in Harkonen (window 100) or Gabrielli 2019 (21 epochs).
t_star_smoothed <- function(val_loss, w = 21) {
  ma <- stats::filter(val_loss, rep(1 / w, w), sides = 2)
  which.min(ma)
}

# GBC Algorithm 7.2: retrain from scratch on all data for t_star epochs.
# Critique hook (HP-F02): t_star was found on the training part only; with a fixed
# batch size the number of gradient steps per epoch changes with the data volume.
refit_alg72 <- function(x, y, hp, seed, t_star, batch_size = nrow(x)) {
  model <- build_net(ncol(x), hp, seed)
  model |> fit(x, y, epochs = t_star, batch_size = batch_size, verbose = 0)
  model
}

# GBC Algorithm 7.3: keep the early-stopped weights, continue on all data until the
# validation loss falls below the training loss recorded at t_star (may never terminate).
continue_alg73 <- function(es, x, y, split, n_steps = 10, max_rounds = 100) {
  target <- es$train_loss_at_t_star
  for (r in seq_len(max_rounds)) {
    es$model |> fit(x, y, epochs = n_steps, batch_size = nrow(x), verbose = 0)
    v <- es$model |> evaluate(x[split$valid, , drop = FALSE], y[split$valid], verbose = 0)
    if (v[[1]] <= target) break
  }
  es$model
}
```

## A seed-averaged score: the building block of every search below

```{r score}
# HP-V1/V2/V4: 'splits' is a list of splits (one random split, a time hold-out,
# or several rolling origins). Each configuration is scored as the mean over
# seeds and splits, which is what [WM] p. 460 and Al-Mudafer et al. (2T runs) do.
score_config <- function(x, y, splits, hp, seeds = 1:5, ...) {
  s <- c()
  for (sp in splits) for (sd in seeds) {
    es <- fit_early_stopped(x, y, sp, hp, sd, ...)
    s <- c(s, min(es$val_loss))
  }
  c(mean = mean(s), sd = sd(s), n = length(s))
}
```

## `HP-M07` Grid search, with an edge check

```{r grid}
grid <- expand.grid(depth = 2:4, width = c(10, 20, 40), dropout = c(0, 0.1, 0.2),
                    KEEP.OUT.ATTRS = FALSE)
base <- list(activation = "tanh", l2 = 0, lr = 1e-3, optimizer = "adam")
res <- do.call(rbind, lapply(seq_len(nrow(grid)), function(g) {
  hp <- modifyList(base, as.list(grid[g, ]))
  cbind(grid[g, ], t(score_config(x, y, splits, hp)))
}))
best <- res[which.min(res$mean), ]
# HP-F05: an optimum on the boundary means the grid must be extended ([GBC] p. 434).
on_edge <- sapply(names(grid), function(v) best[[v]] %in% range(grid[[v]]))
```

## `HP-M08` Random search on log scales

```{r random}
draw_hp <- function() list(
  depth = sample(2:4, 1), width = sample(c(16, 32, 64), 1),
  dropout = exp(runif(1, log(0.01), log(0.3))),     # log-uniform, as in Guo (2026)
  l2 = 10^runif(1, -6, -2), lr = 10^runif(1, -4, -2),
  activation = "tanh", optimizer = "adam")
set.seed(1)
trials <- replicate(40, draw_hp(), simplify = FALSE)
scores <- sapply(trials, function(hp) score_config(x, y, splits, hp, seeds = 1)["mean"])
```

## `HP-M11` Staged screening: cheap single-seed screen, expensive multi-seed confirmation

```{r halving}
# Guo (2026) used seeds as the fidelity; iterations (Cote et al.) work the same way.
top <- order(scores)[1:8]                                  # stage 1: 1 seed each
confirm <- sapply(trials[top], function(hp)
  score_config(x, y, splits, hp, seeds = 1:5)["mean"])     # stage 2: 5 seeds each
winner <- trials[top][[which.min(confirm)]]
# HP-F01: both stages must use validation splits, never the evaluation diagonal(s).
```

## `HP-M10` Sequential (coordinate-wise) search in the order of Al-Mudafer et al.

```{r sequential}
theta <- list(l2 = 0, dropout = 0, depth = 2, width = 60,
              activation = "sigmoid", lr = 1e-3, optimizer = "adam")   # judgement start
order_and_grids <- list(l2 = c(0, 1e-4, 1e-3, 1e-2, 1e-1),
                        dropout = c(0, 0.1, 0.2),
                        depth = 1:4,
                        width = c(20, 40, 60, 80, 100))
for (h in names(order_and_grids)) {
  s <- sapply(order_and_grids[[h]], function(v)
    score_config(x, y, splits, modifyList(theta, setNames(list(v), h)))["mean"])
  theta[[h]] <- order_and_grids[[h]][which.min(s)]
}
# Critique hook: the answer depends on the order and on the start; interactions are never visited.
```

## `HP-M09` Bayesian optimisation with a Gaussian process

```{r bayesopt}
library(ParBayesianOptimization)
obj <- function(log10_lr, dropout, width) {
  hp <- list(depth = 3, width = round(width), dropout = dropout, l2 = 0,
             lr = 10^log10_lr, activation = "tanh", optimizer = "adam")
  list(Score = -score_config(x, y, splits, hp, seeds = 1:3)[["mean"]])  # bayesOpt maximises
}
bounds <- list(log10_lr = c(-4, -2), dropout = c(0, 0.3), width = c(8, 64))
opt <- bayesOpt(FUN = obj, bounds = bounds, initPoints = 10, iters.n = 30, iters.k = 1)
getBestPars(opt)
# Critique hooks: report the bounds and check whether the optimum sits on one (Hiabu et al.);
# use the same epoch budget and patience in tuning as in the final fit (HP-F07).
```

## `HP-M16`/`HP-M17` Nagging and snapshot averaging

```{r nagging}
nagging_predict <- function(x, y, x_new, hp, t_star, M = 20) {
  pred <- 0
  for (m in seq_len(M)) {
    model <- refit_alg72(x, y, hp, seed = 100 + m, t_star = t_star)
    pred <- pred + as.numeric(predict(model, x_new, verbose = 0)) / M
  }
  pred
}

snapshot_predict <- function(x, y, x_new, hp, seed, t_star, k = 10) {
  model <- build_net(ncol(x), hp, seed)
  model |> fit(x, y, epochs = t_star - k - 1, batch_size = nrow(x), verbose = 0)
  pred <- 0
  for (e in seq_len(2 * k + 1)) {          # epochs t_star - k, ..., t_star + k
    model |> fit(x, y, epochs = 1, batch_size = nrow(x), verbose = 0)
    pred <- pred + as.numeric(predict(model, x_new, verbose = 0)) / (2 * k + 1)
  }
  pred
}
# Choosing M: increase M until the reserve (not the loss) changes by less than a tolerance,
# the stabilisation argument of [WM] pp. 323 and 328.
```

## `HP-V4` Rolling-origin, next-diagonal score for a triangle

```{r rolling-origin}
# 'cells' is a long data frame with columns i (accident period), j (development period),
# y (incremental) and the features the network uses. 'fit_fun' fits the model on a
# data frame and returns a predict function; it can wrap build_net() or a bCCNN.
rolling_origin_score <- function(cells, fit_fun, hp, origins, h = 1, loss = poisson_dev) {
  s <- c()
  for (c0 in origins) {                                    # valuation at calendar period c0
    train <- subset(cells, i + j <= c0)
    test  <- subset(cells, i + j >  c0 & i + j <= c0 + h)  # the next h diagonals
    pred  <- fit_fun(train, hp)(test)
    s <- c(s, loss(test$y, pred))
  }
  mean(s)
}
poisson_dev <- function(y, mu) 2 * mean(ifelse(y > 0, y * log(y / mu), 0) - (y - mu))
# The lower triangle of a simulated data set (or the last h calendar periods of real data)
# is used only after this score has chosen hp: the [GBC] p. 121 rule (HP-F01).
```

# Summary judgement

* **Most hyperparameters in the folder were never searched.** Of the 50 network documents, 46 fix at least one in-scope value by fiat, 43 inherit at least one from earlier work and 28 rely on at least one library default. Twenty-three run any explicit search (grid, random, Bayesian, sequential, staged or evolutionary); 30 use early stopping; 14 do neither.
* **The actuarial reserving papers follow [WM]/[AIT], not [GBC].** The typical design is: a fixed architecture of the (20, 15, 10) tanh family or a close relative, a library-default optimiser, the number of gradient steps chosen by early stopping on a split of the claims, one seed, and sometimes a width grid (Wüthrich 2017; Gabrielli 2019). Systematic searches come from outside the ETH line: Al-Mudafer et al. (sequential), Schneider & Schwab (random then Bayesian), Hiabu et al. (Bayesian), Guo (random with multi-seed confirmation) and Avanzi et al. 2025 (grid).
* **The weak point is the signal, not the search.** Most validation sets are random splits inside the upper triangle, which measure interpolation. Only Al-Mudafer et al. (rolling origin), Avanzi et al. 2025 (a time hold-out) and Avanzi et al. 2026 (rolling settlement validation) choose network hyperparameters on a time-ordered signal; Balona & Richman and Hindley supply the next-diagonal and removed-diagonal templates. Ten documents use the test data or the known truth for at least one choice.
* **The textbooks disagree on what to search and agree on what not to do.** [GBC] says search (random by default), [WM]/[AIT] say use a sufficiently large default and early-stop and average, [H] says use judgement and check out of time. All three that discuss it forbid, or restrict, the use of the test data, and both actuarial books reject AIC/BIC for networks. None of them treats a time-ordered validation design for networks, which is precisely what a reserving application needs.
* **For your thesis,** the defensible protocol is the one in Section 4.7: an untouched outer evaluation, a rolling-origin inner score averaged over seeds, a stated refit rule with a check that $t^\star$ transfers to the full data, nagging with $M$ chosen by stabilisation of the reserve, and full reporting of candidates and chosen values. Each element has a textbook anchor ([GBC] p. 121; [WM] pp. 290, 323, 460; [AIT] pp. 23, 109; [H] pp. 314, 318–319) and a precedent in the folder.
* **ISL is still to be added** (Section 6.5).

# References

**Textbooks**

* [WM] Wüthrich, M.V., Merz, M. (2023). *Statistical Foundations of Actuarial Learning and its Applications.* Springer Actuarial (open access).
* [AIT] Wüthrich, M.V., Richman, R., Avanzi, B., Lindholm, M., Maggi, M., Mayer, M., Schelldorfer, J., Scognamiglio, S. (2026). *AI Tools for Actuaries.* Course material, version of 20 January 2026.
* [GBC] Goodfellow, I., Bengio, Y., Courville, A. (2016). *Deep Learning.* MIT Press.
* [H] Hindley, D. (2017; imprint 2018). *Claims Reserving in General Insurance.* Cambridge University Press.
* [ISL] James, G., Witten, D., Hastie, T., Tibshirani, R. *An Introduction to Statistical Learning* (1st ed.). Springer. Not yet in the project.

**Documents in the folder fitting a neural network** (version in your folder)

* Al-Mudafer, M.T., Avanzi, B., Taylor, G., Wong, B. (2021). Stochastic loss reserving with mixture density neural networks. arXiv:2108.07924v1.
* Andersen, M.R., Roed-Sørensen, U. (2021). Bayesian Neural Networks: Theory and Applications. MSc thesis, Copenhagen Business School.
* Avanzi, B., Lambrianidis, M., Taylor, G., Wong, B. (2025). On the use of case estimate and transactional payment data in neural networks for individual loss reserving. arXiv:2601.05274v1.
* Avanzi, B., Richman, R., Wong, B., Wüthrich, M.V., Xie, Y. (2026). Reinforcement Learning for Micro-Level Claims Reserving. arXiv:2601.07637v1.
* Belabed, A., Doumi, K., Merzguioui, O., Zellou, A. (2025). Optimizing Non-Life Insurance Technical Reserves: The Contribution of Neural Networks under the Solvency II Directive. IEEE SITA 2025.
* Bücher, A., Rosenstock, A. (2022). Micro-level prediction of outstanding claim counts using neural networks. Supplementary material only.
* Cai, P. (2021). Claim Reserving: Classical versus Machine Learning Methods. MSc thesis, McMaster University.
* Cai, P. (2025). Advanced Dependence Modeling of Loss Reserves. PhD thesis, McMaster University.
* Cai, P., Abdallah, A., Jeganathan, P. (2025). Recurrent Neural Networks for Multivariate Loss Reserving and Risk Capital Analysis. arXiv:2402.10421v3.
* Côté, M.-P., Hartman, B., Mercier, O., Meyers, J., Cummings, J., Harmon, E. (2025). Synthesizing Property & Casualty Ratemaking Datasets using Generative Adversarial Networks. *Variance* 18.
* Dong, C., Liu, L., Li, Z., Shang, J. (2020). Towards Adaptive Residual Network Training: A Neural-ODE Perspective. ICML 2020.
* Fang, K., Mugunthan, V., Ramkumar, V., Kagal, L. (2022). Overcoming Challenges of Synthetic Data Generation. IEEE Big Data 2022.
* Ferrario, A., Noll, A., Wüthrich, M.V. (2020). Insights from Inside Neural Networks. SSRN 3226852, version of 23 April 2020.
* Gabrielli, A. (2019). A Neural Network Boosted Double Over-Dispersed Poisson Claims Reserving Model. SSRN 3365517, version of 4 April 2019.
* Gabrielli, A. (2020). An Individual Claims Reserving Model for Reported Claims. SSRN 3612930, version of 28 May 2020.
* Gabrielli, A. (2020). Claims Reserving and Neural Networks. PhD thesis, Diss. ETH No. 26990.
* Gabrielli, A., Richman, R., Wüthrich, M.V. (2018). Neural Network Embedding of the Over-Dispersed Poisson Reserving Model. SSRN 3288454, version of 21 November 2018.
* Gorishniy, Y., Kotelnikov, A., Babenko, A. (2025). TabM: Advancing Tabular Deep Learning with Parameter-Efficient Ensembling. ICLR 2025; arXiv:2410.24210v3.
* Graziani, S., Xibilia, M.G. (eds.) (2021). *Innovative Topologies and Algorithms for Neural Networks.* MDPI (reprint of a *Future Internet* special issue).
* Gridin, I. (2021; the copyright page says first edition 2022). *Time Series Forecasting using Deep Learning.* BPB Publications (EPUB).
* Gueye, M., Attabi, Y., Dumas, M. (2023). Row Conditional-TGAN for Generating Synthetic Relational Databases. ICASSP 2023.
* Guo, Q. (2026). Hyperparameters over Architecture: A Controlled Comparison of Neural Networks for Aggregate Loss Reserving. *Risks* 14, 162.
* Härkönen, V. (2021). On Claims Reserving with Machine Learning Techniques. MSc thesis, Stockholm University.
* Hiabu, M., Hofman, E., Pittarello, G. (2025). Claim Counts Prediction Using Individual Data with ReSurv. CAS Forum, Q1 2025.
* Kuo, K. (2020). Individual Claims Forecasting with Bayesian Mixture Density Networks. CAS Research Papers.
* Kuo, K. (2020). Generative Synthesis of Insurance Datasets. arXiv:1912.02423v2.
* Lindholm, M., Verrall, R., Wahl, F., Zakrisson, H. (2020). Machine Learning, Regression Models, and Prediction of Claims Reserves. CAS E-Forum, Summer 2020.
* Mahohoho, B., Chimedza, C., Matarise, F., Munyira, S. (2023). Artificial Intelligence Based Automated Actuarial Loss Reserving Model for the General Insurance Sector. Research Square preprint.
* Mulquiney, P. (2006). Artificial Neural Networks in Insurance Loss Reserving. (No venue printed.)
* Nicholas, A.-L. (2026). Evaluation of Long Short-Term Memory Neural Networks for Actuarial Reserving of Auto Long-Tail General Insurance Claims. MSc thesis, University of Guelph.
* Noordhoek, C. (2025). Hybrid Modeling for Loss Reserving. MSc thesis, Tilburg University.
* Pittarello, G., Clemente, G.P., Zappa, D. (2022). An individual model for claims reserving based on Bayesian neural networks. Working paper, 27 September 2022.
* Qiu, D. (2019). Individual Claims Reserving: Using Machine Learning Methods. MSc thesis, Concordia University.
* Ramos-Pérez, E., Alonso-González, P.J., Núñez-Velázquez, J.J. (2020). Stochastic reserving with a stacked model based on a hybridized Artificial Neural Network. arXiv:2008.07564v1.
* Ramos-Pérez, E., Alonso-González, P.J., Núñez-Velázquez, J.J. (2022). Mack-Net model: Blending Mack's model with Recurrent Neural Networks. *Expert Systems with Applications* 201, 117146.
* Richman, R., Wüthrich, M.V. (2021). LocalGLMnet: interpretable deep learning for tabular data. arXiv:2107.11059v1.
* Richman, R., Wüthrich, M.V. (2026a). From Chain-Ladder to Individual Claims Reserving. arXiv:2602.15385v2.
* Richman, R., Wüthrich, M.V. (2026b). One-Shot Individual Claims Reserving. arXiv:2603.11660v1.
* Rügamer, D., Pfisterer, F., Bischl, B., Grün, B. (2023). Mixture of experts distributional regression. *AStA Advances in Statistical Analysis* 108, 351–373.
* Schneider, J.C., Schwab, B. (2025). Advancing loss reserving: A hybrid neural network approach for individual claim development prediction. *Journal of Risk and Insurance* 92(2), 389–423.
* Schwab, B. (2025). Robust and Explainable AI for Risk Prediction in Insurance and Finance. PhD thesis, Leibniz Universität Hannover.
* Spedicato, G.A., Richman, R. (2025). Comparing Predictive Models for Dependent Risk Pricing. *Variance* 18.
* Swallow, R. (2023). An Application of Generative Adversarial Networks to One-Dimensional Value-at-Risk. Minor dissertation, University of Cape Town.
* Usman, F. (2024). Advancing Insurance Intelligence. PhD thesis, University of Sydney.
* Wüthrich, M.V. (2017). Neural Networks Applied to Chain-Ladder Reserving. Working paper, version of 10 May 2017.
* Xu, L., Skoularidou, M., Cuesta-Infante, A., Veeramachaneni, K. (2019). Modeling Tabular Data using Conditional GAN. NeurIPS 2019; arXiv:1907.00503v2.
* Ye, H.-J., Liu, S.-Y., Cai, H.-R., Zhou, Q.-L., Zhan, D.-C. (2025). A Closer Look at Deep Learning Methods on Tabular Datasets. arXiv:2407.00956v4.
* Yeldan, M., Karabey, U. (2026). Dispersion modeling in Tweedie compound Poisson with combined actuarial neural networks. *Communications in Statistics – Simulation and Computation*, online 17 September 2026.
* Yu, S., Tomasi, C. (2019). Identity Connections in Residual Nets Improve Noise Stability. ICML 2019 workshop.
* Zelený, O. (2026). Beyond Chain-Ladder: Claims Reserving in the Machine Learning Era. MSc thesis, Charles University.

**Documents without a network cited for a method**

* Avanzi, B., Li, Y., Wong, B., Xian, A. (2024). Ensemble distributional forecasting for insurance loss reserving. *Scandinavian Actuarial Journal* 2024(9), 971–1012.
* Balona, C., Richman, R. (2020). The Actuary and IBNR Techniques: A Machine Learning Approach. SSRN 3697256, 14 August 2020.
* Jin, F.F. (2021). Using decision tree ensemble methods for the estimation of individual claims reserving. MSc thesis, Erasmus University Rotterdam.
* Mayr, E. (2025). Development and Optimization of Reserving Models in Actuarial Science. MSc thesis, TU Wien.
* Mienye, I.D., Swart, T.G., Obaido, G. (2024). Recurrent Neural Networks: A Comprehensive Review. *Information* 15, 517.
* Tavares, A.C. (2023). A Machine Learning Approach for Predicting Claims Reserving. MSc thesis, University of Porto.

**Shipped code:** Manai (2026) `claims-reserving-benchmark`; Zelený (2026) `masters-thesis`; Richman, Scognamiglio & Wüthrich (2025) PIN example v11; Gabrielli (2019) NNDODP Kaggle notebook (third-party re-run); Utulu (2026); Van Oirbeek (2026) `hgr`.

# Appendix A – Extraction tables, document by document
These are the extraction records on which Sections 2–8 rest, one per document, in the words of the extraction pass (lightly normalised). Each row gives the final value, how it was determined (extraction code `S`, mapped to `HP-M` labels in Table 2.1), the candidates searched, the selection signal (`V` code) and the PDF page. Codes `S20`–`S27` were introduced during extraction and have been harmonised across passes:
`S20` initialisation at a fitted classical model (`HP-M20`); `S21` reasoned a-priori argument (`HP-M04`); `S22` warm start / fine-tuning (`HP-M21`); `S23` best-of-N seeds (`HP-M19`); `S24` transfer of tuned values to a related configuration (`HP-M21`); `S25` empirical-null input test (`HP-M22`); `S26` visual screening of loss curves (`HP-M26`); `S27` top-$k$ trial pattern analysis (`HP-M25`).
Values described as "from the table image" or "from the figure image" were read from the page image because the text layer does not contain them; they are not covered by the automatic quote check of Appendix B.

## A.1 The ETH / Gabrielli line (1): the founding papers

### Wüthrich 2017
**Document.** Mario V. Wüthrich, "Neural Networks Applied to Chain-Ladder Reserving", version dated **May 10, 2017** (date printed under the author name on PDF p. 1; PDF metadata creation date also 10 May 2017; 19 pages). No journal header, volume or DOI is printed, so this is the preprint/working-paper version (ETH Zurich, RiskLab affiliation), not the journal version. Everything below applies to the May 2017 version only; the July 2018 version was not in the files and was not examined, so differences between versions cannot be reported here.

**Network(s).** One feed-forward network per development period j = 0,...,10 (11 separate networks) with two hidden layers of q1 and q2 neurons, a centred sigmoid activation and a log link, modelling feature-dependent chain-ladder factors f_j(x) from 5 claim features (AQ, LoB, cc, age, inj_part). The loss is Mack's weighted square loss (3.1) on aggregated cells with C_{i,j-1}(x) > 0. A second network variant adds accident year as a sixth feature (§5.2).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of hidden layers (depth) | 2 (same for all 11 development periods) | S4 (+S21): author's judgement; called "rather arbitrary" and a "subjective choice", justified by a general claim that 2 layers are often better than 1 and that more than 2 are hard to calibrate | none tested | VX: no data-based comparison reported | p. 5, p. 6 (§3.1) |
| Neurons per layer (q1, q2), chosen separately per development period j | j=0: (9,7); j=1: (4,3); j=2: (3,3); j=3,...,10: (2,2) (Table 1, read from the page image) | S6: full grid search over all combinations, done separately for each j; the selected width was then refit on all data | q1, q2 ∈ {2,...,10}, i.e. 9 × 9 = 81 combinations per j (count derived from the stated range) | V1: out-of-sample weighted square loss (3.1)/(3.3) on a random 10% of individual claims (the "test data set"), with models fitted on the other 90% ("learning data set"). The split is within the observed upper triangle | p. 8 (§3.3, Table 1) |
| Activation function (hidden layers) | φ(x) = (1 − e^{−x})/(1 + e^{−x}) ∈ (−1,1), a "centered version of the sigmoid" (equal to tanh(x/2)) | S1: stated with no reason beyond describing it as centred. The input scaling is motivated by "the activation function lives around the origin" | not stated | VX | p. 5 (§3.1), p. 7 |
| Output link | log link: log f_{j−1}(x) = β0 + Σ β_k z_k^{(2)}(x) (eq. 3.2) | S1: model specification (keeps CL factors positive, f: X → R+) | none | VX | p. 5 |
| Optimiser | Gradient descent with momentum (coefficient ν ∈ [0,1)) plus layer-by-layer ("block") updates | S2 + S4: momentum taken from Nielsen [3]. Both changes were kept because they "led to better convergence properties in our example" | plain gradient descent (3.5) vs. the two modifications (only qualitative) | V6: training convergence, qualitative; no metric reported | p. 6–7 (§3.2) |
| Momentum coefficient ν | not stated (only ν ∈ [0,1)) | S19 | not stated | VX | p. 6 |
| Learning rate ρ and schedule | not stated; only "tempered learning rates" are mentioned, and "the speed of convergence should be fine-tuned" | S19 for the value. A decreasing ("tempered") rate is mentioned qualitatively but not specified | not stated | VX | p. 6 (§3.2) |
| Number of gradient-descent iterations / stopping rule | not stated. Fits are described as minimising the in-sample loss to "optimal model parameters". No early stopping is described | S19 | not stated | VX | p. 8 |
| Batch size | not stated. The gradient is written for the full loss L_j over all cells; mini-batching is not mentioned | S19 | not stated | VX | p. 7 |
| Weight initialisation / starting points / random seed | not stated. The paper says different starting points "should be explored" but does not report doing so | S19 | not stated | VX | p. 6 |
| Regularisation (dropout, penalties) | none used or mentioned. Complexity is controlled only through the choice of (q1, q2) | S19 (not applicable) | none | none | p. 6, p. 8 |
| Ensembling / bagging | none. Bootstrap/bagging declared "not feasible ... for computational reasons" | not used | none | none | p. 15 (§6) |
| Architecture of the accident-year-extended model (§5.2) and of the AQ-excluded model (Fig. 2 right) | not stated. The text only says "replace d by d + 1"; it does not say whether (q1, q2) were re-selected | S19 | not stated | VX | p. 12–13 |
| (Context, pre-processing: not strictly a hyperparameter) Categorical encoding and scaling | LoB, cc, inj_part replaced by class-wise empirical CL ratios (a target encoding); then min–max scaling to [−1,1] | S5/S2: scaling justified by the activation's range and "appropriate convergence", citing Wüthrich & Buser [5] Fig. 3.5 | none | VX | p. 7 |

### Gabrielli et al. 2018
**Document.** Andrea Gabrielli, Ronald Richman, Mario V. Wüthrich, "Neural Network Embedding of the Over-Dispersed Poisson Reserving Model", version dated **November 21, 2018** (PDF p. 1), footer "Electronic copy available at: https://ssrn.com/abstract=3288454" on every page. This is the SSRN preprint, not the journal version. Code listings (R/Keras) are in Appendix A (PDF pp. 25–30).

**Network(s).** (i) A "blended cross-classified neural network" (bCCNN) per line of business (6 synthetic LoBs, 12×12 triangles). A feed-forward network (3 tanh hidden layers of 20, 15, 10 neurons, 10% dropout, exp output) takes non-trainable 1-dimensional accident-year and development-year embeddings fixed at the ccODP MLEs. It is joined to the ccODP GLM through a skip connection and initialised so that it starts exactly at the ccODP (chain-ladder) model. (ii) A multi-LoB bCCNN fitted jointly on all 6 LoBs, with the same hidden layers plus a trainable LoB embedding.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of gradient-descent steps (epochs), single-LoB bCCNN | **300** for every LoB (full batch, so 1 epoch = 1 step) | **S12**: trained 1,000 epochs on the training half, with the validation loss tracked per epoch. The minimum was read off the plots ("seem to have a minimum after roughly 300 iterations", dotted vertical line). The model was then refit on the **full data** for 300 steps. The same 300 was used for all 6 LoBs "for simplicity" | 1 to 1,000 epochs (validation curve) | **V1**: un-scaled Poisson deviance (Keras `loss='poisson'`) on a *validation triangle* built from the other 50% of individual claims. The split was 50/50, balanced per LoB and accident year (Listing 2), and covers the same upper-triangle cells as the training triangle | p. 11–13 (§3.3.1–3.3.2, Fig. 2, Table 2), p. 14 (§3.3.3), pp. 25–26 (App. A, Listing 2) |
| Number of gradient-descent steps, multi-LoB bCCNN | **200** | **S12**: same protocol. 1,000 epochs on the pooled training triangles, over-fitting judged to start "after roughly 200 gradient descent steps", then 200 steps on the entire data | 1 to 1,000 | **V1**: validation deviance on the pooled validation triangles (Fig. 3). The deviance is scaled by φ̂^ODP_m through an offset (Listing 5) | p. 18 (§4.2), p. 19 (Fig. 3) |
| Hidden layers (depth) | 3 (D − 1 = 3) | **S4**: informal trial. "we have also been trying different network architectures"; the chosen one is "a compromise between accuracy and run-time". The text does not say whether depth itself was among the variations tried (examples given are "other numbers of hidden neurons or different dropout rates") | not reported | **V1 + V9**: "decrease in out-of-sample validation loss" on the validation half, traded off against run-time / number of GD steps. No numbers reported | p. 11, p. 13 (§3.3.2) |
| Neurons per layer | (q1, q2, q3) = (20, 15, 10) (single-LoB and multi-LoB) | **S4**: same informal trial and "compromise" statement. For the multi-LoB model it was carried over ("We choose a similar set up as in Section 3.3.2"), not re-tuned | "other numbers of hidden neurons" (values not reported) | **V1 + V9** (as above) | p. 11, p. 13, p. 18 |
| Dropout rate | 10% after each of the 3 hidden layers | **S4**: purpose stated ("to regularize the network and improve the out-of-sample performance"); "different dropout rates" were tried informally with "similar results". Carried over unchanged to the multi-LoB model | "different dropout rates" (values not reported) | **V1 + V9** | p. 11, p. 13, p. 18; Listing 4 p. 29 |
| Activation functions | tanh in hidden layers; exponential output (log link, matching the ccODP GLM) | **S1**: stated with no justification for tanh. The exp output follows from the ccODP log link ("the same exponential activation function as in the cross-classified case") | none | VX | p. 8 (§3.1) |
| Skip connection (CANN-type blending with ccODP) | ccODP predictor placed in a skip connection. Output = exp(w(α_i + β_j) + c + B'z^(D−1)) | **S2 + design rationale**: skip connections cited from computer vision and from Richman & Wüthrich (2018) mortality [12]. The main reason is interpretability: boosting from the classical model | none | VX | p. 9 (§3.2) |
| Embedding dimension and trainability (single LoB) | AY and DY embeddings: **1-dimensional, non-trainable**, fixed at the ccODP MLEs (training-half MLEs in the validation run) | **S4**: "a modeling choice that has worked well in our example"; "led to more stability in calibration". A 2-dimensional embedding (one non-trainable, one trainable component) was considered but rejected because "calibration is slower". The paper says "we opt for the simpler model" | 1-dim non-trainable vs. 2-dim part-trainable (discussed, not reported numerically) | V9: calibration stability / speed (qualitative) | p. 8, pp. 11–12 |
| Embeddings (multi-LoB) | AY and DY: 6-dim (one column per LoB), non-trainable at the ccODP MLEs. LoB: 1-dim **trainable** γ(m), plus a non-trainable intercept embedding and a non-trainable one-hot LoB embedding | **S1/S4**: trainable LoB embedding added "To have more modeling flexibility w.r.t. LoBs" | none | VX | pp. 16–18 (§4.1); Listing 5 p. 30 |
| Weight initialisation | **ccODP start**: embeddings = ccODP MLE, skip weight w = 1, output intercept = ĉ^ODP, NN output weights B_D = 0, so the network starts exactly at the chain-ladder model. Hidden-layer weights: not stated in the text; Listing 4 gives no initializer, so Keras defaults apply | **NEW S20** (initialisation at the fitted classical actuarial model, NN branch starting at zero). Justified by interpretation as a boosting step and by calibration stability. Hidden layers: **S3** (library default, evident from code) | none | VX | p. 10 (eq. 3.7), p. 15; Listing 4 lines 31–33 p. 29 |
| Optimiser | **RMSprop** (`optimizer_rmsprop()`), in both the validation run and the final fit | **S3/S1**: appears **only in the code** (Listing 4 line 37). The prose only says "with the same optimizer, see line 37 of Listing 4". No reason is given anywhere | none | VX | p. 14; p. 29 (Listing 4) |
| Learning rate (and other RMSprop settings) | not stated. `optimizer_rmsprop()` is called with no arguments, so the Keras defaults apply (the value is not printed in the paper) | **S3** (evident from code) | none | VX | p. 29 |
| Batch size | full batch: 78 (single-LoB triangle cells), 468 = 6·78 (multi-LoB) | **S1**: stated as the "maximal batch size", with no justification. A per-LoB mini-batch variant is mentioned only as an alternative to dispersion scaling | none | VX | p. 12, p. 18; Listing 4 line 40 |
| Random seed (NN training) | not stated (seed 75 and seeds 1–100 belong to the data simulation only) | **S19** | — | — | pp. 25–26 |
| Ensembling | none. The reported point estimate is a single fit. 1,000 parametric-bootstrap refits (same architecture, same 300 / 200 steps, ccODP start) are used only for the RMSEP | not used (bootstrap count 1,000: **S1**) | — | — | p. 15 (§3.3.4), p. 20 (§4.3) |
| (Out of scope, same procedure) Dispersion φ_m of the bCCNN | φ̂^ODP_m reduced by the relative decrease in validation loss over the first 300 steps (Table 2, last row). Set to 0% reduction for LoBs 3 and 6 | derived from the same validation curves | — | V1 | p. 13 |

### Gabrielli 2019
**Document.** Andrea Gabrielli, "A Neural Network Boosted Double Over-Dispersed Poisson Claims Reserving Model", version dated **April 4, 2019** (PDF p. 1), footer "Electronic copy available at: https://ssrn.com/abstract=3365517". This is the SSRN preprint, not the journal version. (A third-party notebook in the uploads says the journal version is ASTIN Bulletin 50(1), 2020; that version was not examined.)

**Network(s).** "NNDODP", a multi-output Keras network that jointly models claim counts N and claim amounts Y. It has non-trainable embeddings set to the ccODP MLEs, two feed-forward sub-networks (K = 2 tanh hidden layers each, identical widths), a (J+1)-dimensional claim-counts layer, an ordered claim-counts layer with batch normalisation, a linear "payout attention" layer, and skip connections so that training starts exactly at the two ccODP models. It is fitted (a) per LoB ("single NNDODP", (q1,q2) = (30,25)) and (b) jointly on all 6 LoBs with one-hot LoB input ("multiple NNDODP", (q1,q2) = (40,30)).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Neurons per hidden layer (q1, q2), single NNDODP | (30, 25). One setting for all 6 LoBs and for both sub-networks | **S6** grid search with an **S5** pyramid constraint q1 > q2 ("information should be condensed"). Each candidate trained 1,000 epochs; the best epoch is implicit in the score | q1, q2 ∈ {20,25,...,50}, q1 > q2 → 21 models | **V1**: minimum over 1,000 epochs of a 21-epoch centred moving average of the claim-amounts Poisson deviance (scaled by φ̂^Y_m) on the *validation triangles* (other 50% of claims), summed over the 6 LoBs. Top 3: 1218.6 / 1221.2 / 1221.9 (Table 6) | p. 17 (§3.2.1, Table 6) |
| Neurons per hidden layer, multiple NNDODP | (40, 30) | **S6 + S5** (same protocol, larger grid because the input is 30-dimensional) | q1, q2 ∈ {20,25,...,80}, q1 > q2 → 78 models | **V1** (as above). Top 3: 1193.6 / 1193.7 (80,50) / 1194.4 (25,20) (Table 10, from image) | p. 25 (§4.2.1, Table 10) |
| Number of hidden layers K (both sub-networks) | 2 | **NEW S21** (reasoned a-priori choice): one layer suffices in theory but may need "an excessively large number of neurons"; a second layer "may facilitate learning of interactions". Not tested | none | VX | p. 9 (§3.1.2) |
| Architecture of the 2nd sub-network (payout attention branch) | tied to the 1st: same K, same widths, same inputs | **S1**: "For simplicity" | none | VX | p. 12 (§3.1.3) |
| Number of epochs, single NNDODP | **400** for every LoB. Final reserves are the **average of predictions at epochs 390,...,410** | **S12** (+ pooling): the chosen (30,25) model was trained 1,000 epochs on the training half, *separately per LoB*. A per-LoB "ideal" epoch was read off (Table 7: 1,000 / 500 / 0 / 500 / 300 / 100). These were **averaged across LoBs** to give 400, and the model was then refit on the full upper triangles for 400 epochs. How the per-LoB "ideal" value was obtained (the rule) is not stated; all values are multiples of 100 | 0–1,000 epochs | **V1**: per-LoB claim-amounts Poisson deviance on the validation triangle (Fig. 2) | pp. 17–19 (§3.2.1, Fig. 2, Table 7), p. 19 (§3.2.2) |
| Number of epochs, multiple NNDODP | **400** (average of 390–410) | **S12** (+ pooling) as above. Per-LoB ideals 500 / 500 / 0 / 300 / 1,000 / 100, average 400 (Table 11, from image) | 0–1,000 | **V1** (Fig. 7) | p. 25 (Table 11), p. 26 |
| Averaging window over epochs (snapshot averaging) | 21 epochs (390–410) | **S15** (snapshot averaging instead of picking one epoch). The window of 21 is **S1**, matching the 21-epoch smoothing used for selection | none | not stated (the reason given is dropout-induced wiggliness) | p. 19, p. 26 |
| Dropout rate | 20% after both hidden layers of each sub-network, before the claim-counts layer and before the claim-amounts output | **S1**: purpose stated ("to prevent from over-fitting", citing Srivastava et al. [27]); the value is not justified or tuned | none | VX | p. 9; Listings 3–5 (pp. 10, 13, 14) |
| L2 (ridge) penalty | 0.001 on hidden, claim-counts, attention and claim-amounts output kernels | **S1**: purpose stated ("weights ... do not explode", citing James et al. [13] §6.2.1); not tuned | none | VX | p. 9; Listings 3–5 |
| Batch normalisation | one layer on the ordered claim-counts layer | **S1/S21**: "to transform the values ... to values around 0", citing Ioffe & Szegedy [12] | none | VX | p. 14 (§3.1.4) |
| Activation functions | tanh (hidden layers); linear (payout attention, pre-output); exponential (outputs, log link) | **S21**: tanh justified by two general properties (derivative φ' = 1 − φ², bounded range) | none | VX | p. 9, p. 12 |
| Embeddings | Non-trainable, fixed at the ccODP MLEs. Single model: 2-dim per AY and per DY (N and Y parameters), 4-dim input. Multiple model: 12-dim per AY and DY plus 6-dim one-hot LoB, 30-dim input | by construction (**S20**-related); not tuned | none | VX | p. 8, p. 24 |
| Skip connections and initialisation | ccODP start: claim-counts layer biases = ĉ^N, weights 0; attention biases 1, weights 0; claim-amounts output bias = ĉ^Y, weights 0, so training starts exactly at the two ccODP models. Hidden-layer weights: Keras default random initialisation (seeded) | **NEW S20** (initialisation at the fitted classical model), attributed to Wüthrich & Merz [30] (**S2**). Hidden layers: **S3** | none | VX | pp. 11–15 (eqs. 3.4, 3.6, 3.8) |
| Optimiser | RMSprop (Keras) | **S1**: "We choose the optimizer rmsprop"; only a pointer to Goodfellow et al. §8.5.2 "for theoretical background". No comparison | none | VX | p. 16 (§3.1.5, Listing 6) |
| Learning rate | not stated. `optimizer_rmsprop()` is called with no arguments, so the Keras default applies | **S3** (evident from code) | none | VX | p. 16 (Listing 6) |
| Batch size | **not stated in the paper**. The fit call is not printed. A third-party Kaggle notebook (2022) reproducing the author's GitHub code uses full batch (`batch_size = length(x.upper[[1]])`) | **S19** (paper) | — | — | not in paper; notebook `CODE_Gabrielli_2019_NNDODP-notebook...ipynb` cell 18 |
| Random seed | one Keras seed: `set.seed(100); seed1 &lt;- sample(1:1000000, 1)`, "chosen randomly, but in a reproducible way". The same seed is used for the multiple model | **S1** | — | — | pp. 7–8 (Listing 1), p. 24 |
| Ensembling over seeds | none for the reported estimates. 100 Keras seeds are used only as a robustness check (S18) | not used | — | — | p. 20 |
| (Out of scope, same procedure) Loss weights N:Y | 1:1 ("contribute equally"). Selection, however, uses the claim-amounts loss only | S4 judgement | — | — | p. 16, p. 19 |

### Gabrielli 2020
**Document.** Andrea Gabrielli, "An Individual Claims Reserving Model for Reported Claims", version dated **May 28, 2020** (PDF p. 1), footer "Electronic copy available at: https://ssrn.com/abstract=3612930". This is the SSRN preprint. The R code is said to be on GitHub (gabrielliandrea/neuralnetworkindividualrbnsclaimsreserving); that code was not available here.

**Network(s).** One multi-task Keras network per LoB (6 synthetic LoBs, individual reported claims). It has J + 1 = 12 subnets, one per payment delay j. Each subnet has two shared-design tanh hidden layers (40, 30) followed by two parallel task-specific layers (10 and 10). The outputs are a logistic payment probability p_j and a log-normal mean μ_j. Inputs are trainable 2-dim embeddings (3-dim for accident year), and skip ("GLM") connections run from the second embedding coordinates to the outputs. A structured "dropout" on past-payment embeddings mimics the missing future information. Training has two steps: step 1 learns the embeddings, step 2 re-trains the other weights with the embeddings frozen.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Neurons (q1, q2, q3, q4) | 40, 30, 10, 10 (identical in all 12 subnets and all 6 LoBs) | **S4 + S5**: the author explicitly *does not* run the usual search ("Usually, one selects ... However, here we directly choose small numbers of neurons"). The stated reasons are over-fitting risk, run time and stability. Pyramid guideline q1 > q2 > q3 + q4 | none evaluated | VX | p. 13 (§4.2.5) |
| Hidden layers | 2 shared + 1 task-specific per output (parallel 3rd/4th layers) | **S21**: universal approximation vs. "too many neurons" and "interactions" argument; task-specific layers "to increase the task-specific flexibility" | none | VX | p. 10, p. 12 (§4.2.1–4.2.3) |
| Subnet design tied across j | same design for all 12 subnets | **S1**: "For simplicity" | none | VX | p. 8 |
| Activation functions | tanh (hidden); logistic output for p_j; linear output for μ_j | **S21** (tanh: efficient gradients, bounded). Outputs follow from the range of the target (S1) | none | VX | pp. 11–13 |
| Embedding dimensions | 2 for cc, AQ, age, inj_part, RepDel and the past-payment labels (one shared embedding for all delay periods); 3 for AY. β(6) = (0,0) non-trainable | **S4**/design: dimension 1 feeds the FFN, dimension 2 feeds the skip/"GLM" part, and dimension 3 of AY handles AY weight sharing across subnets. Embeddings for categorised continuous features were chosen "believing that the gain in flexibility outweighs the loss of stability". A shared past-payment embedding is used because separate ones "can become unstable" | none | VX | pp. 9–10, p. 13 (§4.1, §4.2.4) |
| Skip connections | second embedding values linked directly to the outputs of each subnet | **S2/S21**: "to speed up learning", citing He et al. [18] | none | VX | pp. 11–12 |
| Initialisation | Output-layer weights on the embedding and hidden layers set to 0. Output intercepts set to logit(a_j) and b_j (empirical probability and log-mean), i.e. start "from the homogeneous model". Other weights: Keras random initialisation (seeded). Step 2 restarts the non-embedding weights "to the same values as before the first training step" | **NEW S20** (initialisation at a simple baseline model; here the homogeneous model rather than a GLM). Rest: **S3** | none | VX | pp. 14–15 (§5.1), p. 19 |
| Optimiser | Nadam (Keras) | **S1**: only "we refer to Sections 8.1.3 and 8.5.2 of [17] for theoretical background" | none | VX | p. 16 (§5.2) |
| Learning rate | not stated | **S19** | — | — | — |
| Batch size | 10,000 (mini-batches) | **S1** | none | VX | p. 16 |
| Number of epochs, step 1 (embedding step) | per LoB: 40, 30, 60, 60, 50, 30 (Table 2, from image) | **S12**: random **80/20 split of individual claims**. Train on 80%, record the loss after every epoch, and read the epoch where the validation loss "flattens out or starts to increase" (green lines, visual). Epochs restricted to multiples of 10 "for simplicity". Then refit on **all n claims** for that many epochs. Chosen **separately per LoB** | multiples of 10. Figure 4 axes show 100 epochs | **V1**: global weighted multi-task loss (5.3) (weighted binary cross-entropy + MSE of log payments) on the 20% validation claims | pp. 18–19 (§5.4, Fig. 4, Table 2) |
| Number of epochs, step 2 (network weights) | per LoB: 40, 50, 60, 90, 50, 140 (Table 3, from image) | **S12** as above. Same 80/20 split, embeddings frozen at the step-1 values *fitted on all n claims*, then refit on all n claims | multiples of 10. Figure 5 axes show 100 epochs (200 for LoB 6) | **V1**, but the frozen embeddings were trained on the validation claims too (see flags) | p. 19 (§5.5, Fig. 5, Table 3) |
| Snapshot averaging over epochs | average of predictions at E−2,...,E+2 (5 epochs) | **S15** (averaging over consecutive epochs "to stabilize the results"). Window size **S1** | none | none (reason: "rather erratic" losses) | p. 19 |
| Regularisation (dropout, L1/L2) | none. "apart from early stopping ... we refrain from using additional regularization techniques". Small widths and multi-task learning are credited as regularisers | **S4** | none | VX | p. 13 |
| Structured "dropout" of past-payment embeddings (not a regulariser; mimics missing future information) | for subnet j ≥ 2, keep the first k+1 past payments with probability 1/j each (eq. 5.6) | **S5**: derived analytically so that each past payment is used in about (j − k)/j of cases, matching prediction time "assuming a roughly uniform distribution among reporting years". Not tuned. (The "dropout rate of 10%" on p. 17 is only a generic illustration of dropout.) | none | none | p. 17 (§5.3) |
| Random seed | one Keras seed, set "in a random but reproducible way". The value is not given | **S1** | — | — | p. 14 |
| (Out of scope, same procedure) task loss weights w_j,1, w_j,2 | inverse of the homogeneous-model losses, so all 24 tasks "live on the same scale" | S5 | — | — | p. 16 (eqs. 5.4–5.5) |

### Mulquiney 2006
**Document.** Peter Mulquiney (Taylor Fry Consulting Actuaries, Sydney), "Artificial Neural Networks in Insurance Loss Reserving". It is a 4-page, two-column conference-style paper. **No venue, volume, date or year is printed on the PDF.** The year 2006 comes only from the file name and the PDF metadata (created 8 June 2006, title "Microsoft Word - Peter_Mulquiney.doc"). The venue cannot be confirmed from the file.

**Network(s).** A single-hidden-layer feed-forward network (R package `nnet`) with 20 hidden units and weight decay 0.05. It models the size of individual finalised claims (motor bodily injury / CTP, about 60,000 claims) as a function of calendar quarter, development quarter, operational time, season and an accident-quarter legislative-change dummy. It is compared with a GLM (Tweedie-type variance power 2.3).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of hidden layers | 1 | not stated as tuned. `nnet` only fits single-hidden-layer networks, so this is effectively **S3** (software constraint). The text reports only "a single hidden layer" | not stated | VX | p. 2 (§2.3) |
| Hidden units | 20 | "The tuning parameters were determined using cross-validation". The search strategy (grid, etc.) and candidates are **not stated**: **S19 for the search, with CV as the selection device** | not stated | **V3?** "cross-validation": type, number of folds, metric and data (whether restricted to the 70% training set) **not stated** | p. 2 (§2.3) |
| Weight decay (L2) | 0.05 | same sentence: "determined using cross-validation" (search not stated) | not stated | **V3?** as above | p. 2 (§2.3) |
| Activation / output function | not stated (`nnet` defaults would apply unless overridden; the paper does not say whether a linear output was used) | **S19** | — | — | — |
| Optimiser, iterations, initialisation, random seed, restarts | not stated | **S19** | — | — | — |
| Ensembling | none mentioned | — | — | — | — |
| Total parameters | 181 (vs 13 for the GLM) | consequence of the above | — | — | p. 4 (§4) |

## A.2 The ETH / Gabrielli line (2): thesis, Richman–Wüthrich, LocalGLMnet, Tweedie CANN

### Gabrielli PhD 2020
**Document.** Gabrielli, A. (2020). *Claims Reserving and Neural Networks*. Doctoral Thesis, Diss. ETH No. 26990, ETH Zurich (examiner M.V. Wüthrich; co-examiners P. Cheridito, F. Moriconi). DOI 10.3929/ethz-b-000445511. **PhD thesis** (cumulative). File "(2)" has identical extracted text (its PDF differs slightly in size) and was ignored.

**Network(s).** Paper A: 35 feed-forward networks (mostly two tanh hidden layers, softmax/logistic/linear outputs) that make up an individual-claims simulator calibrated to about 10 million Suva accident claims. Papers C–E: the bCCNN, NNDODP and individual RBNS networks (these are covered in the standalone-paper entries; only the differences are listed here). Paper B: none.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| [Synopsis] General rule for depth, width and number of GD steps | (general advice) | S4 + S6/S12 recommended: "try various combinations" to "get a feeling"; the "mechanical" route is to pick the best configuration on a training/validation split while also weighing computing time. Early stopping is described generically | not stated | V1 (generic): validation loss | 18, 25–26 |
| [A] Number of hidden layers | 2 for most of the 35 networks; 1 for the re-opening indicator network and the closing-delay indicator network | S1/S4: two layers justified by argument (universal approximation vs. "difficult to calibrate" wide single layers). The one-layer choice for the two claim-status networks is stated without a reason | not stated | VX | 65, 78, 79 |
| [A] Neurons per hidden layer (q1, q2) | Selected value for each of the 35 networks **not reported**. Figure 1 illustrates q1 = 11 and q2 = 15 for the reporting-delay network (the text does not say whether these are the selected values) | S6-like validation selection ("the model with the smallest (validation) out-of-sample loss"). The candidate set is not given | not stated | V1: out-of-sample deviance loss (categorical cross-entropy / Bernoulli / square loss, depending on the network) on a random 10% validation split, drawn afresh "for each calibration" | 64, 83 |
| [A] Activation | tanh in the hidden layers; softmax/logistic output (categorical/Bernoulli), linear output (log-normal mean) | S4 (reasoned choice): bounded range, and the derivative σ' = 1 − σ² helps gradient descent | — | — | 23, 64 |
| [A] Categorical feature encoding (embedding analogue) | 1-dimensional target (mean) encoding of LoB, cc and inj_part, then MinMax scaling to [−1, 1] | S4: "we prefer the following version because it leads to less parameters" (compared with dummy coding). MinMax scaling cites [20] (Ferrario et al.), i.e. S2 | dummy coding (rejected) | — | 23, 63 |
| [A] Optimiser | Momentum-based gradient descent (the text cites [57] = Rumelhart et al. 1986 for the method) | S2/S4 | plain GD (µ = 0) vs. momentum | VX | 80–81 |
| [A] Learning rate ϱ, momentum coefficient µ | not stated (the text only says that "fine-tuning" µ "may lead to faster convergence") | S19 | not stated | VX | 81 |
| [A] Number of GD steps / epochs, batch size | not stated | S19 (the synopsis defers to "the corresponding papers", but Paper A gives no epoch count) | — | VX | 26, 83 |
| [A] Initialisation / seed | not stated. The paper advises exploring different starting points (quote 24) | S19 (advice only) | — | — | 81 |
| [A] Regularisation (dropout/L2) | none mentioned | S19 | — | — | — |
| [C, thesis-only] Depth D−1 = 3 | 3 hidden layers (20, 15, 10): same values as the SSRN version | Thesis adds an explicit rationale (S4): D − 1 = 3 is chosen because the authors are mainly interested in interactions beyond the cross-classified structure (quote 30) | — | — | 146 |
| [C, thesis-only] Activation tanh | tanh | Thesis adds a rationale (S4): the choice "often plays a minor role"; tanh's bounded range means no batch normalisation is needed | — | — | 146 |
| [C] Dropout rate | 10% in all hidden layers (same value) | **Justification differs.** Thesis: S4 "In a preliminary analysis dropout rates of 10% have provided stable predictive models over several runs". SSRN: stated as "to regularize the network and improve the out-of-sample performance" (S1) | other dropout rates tried informally (both versions) | Thesis: V9 (stability of predictions across GD runs) | 150 (thesis); SSRN p. 11 |
| [C] Optimiser | rmsprop (Keras default settings in Listing 4) | Thesis text now names rmsprop explicitly (in the SSRN version it appears only in the code listing): S3 (default learning rate) | — | — | 148, 171 |
| [C] Number of GD steps (single-LoB) | 300 for all LoBs (same) | S12 on a 50/50 claim-level split, then refit on the full triangle for the same count. Thesis adds an explicit rationale for the transfer: "because the complexity of the problem is the same in both situations" | 1,000 epochs monitored | V1-type (claim-level 50/50 split, stratified by LoB × AY; in Listing 2 the claims are sorted by LoB and AY and then **alternately** assigned 1/2, i.e. a systematic rather than random allocation; both halves are aggregated to triangles): Poisson deviance on the validation triangle | 149–150, 152, 168 |
| [C] Validation evidence behind the 300 steps for LoB 6 | 300 (unchanged) | The Table 3/Figure 2 validation run was **redone/changed**. Thesis: LoB 6 training/validation loss decrease 23% / 5%, with LoB 6 among the "clear" LoBs. SSRN: 43% / 0%, and "for LoB 6 we are already in the phase of over-fitting ... after 300 gradient descent steps". Final LoB 6 bCCNN reserve 30,671 is identical in both | — | V1 | 152 (thesis, table image checked); SSRN p. 13 (table image checked) |
| [C] Number of GD steps (multi-LoB) | 200 (same) | S12 as above | 1,000 epochs | V1 | 159 |
| [C] Batch size | full batch: 78 (single LoB) / 468 (multi-LoB). Same | S4 (1 epoch = 1 GD step) | — | — | 150, 159 |
| [C, thesis-only] Replication over 100 simulated data sets | architecture and 300 steps reused unchanged on 100 new data sets (seeds 1–100); **no re-tuning** | S18 robustness check (not in the SSRN version, where the 100 data sets are used for CL only) | — | V5-type evaluation (true reserves) used only for reporting, not for selection | 154, 160 |
| [D, thesis-only] Width grid rationale | (q1, q2) = (30, 25) single / (40, 30) multi (same values) | S6 grid (same). Thesis adds a reason for using step-5 grids instead of {8, …, 256}, and says that "too high numbers of neurons" slow training | {20, 25, …, 50} with q1 > q2 (21 models); {20, …, 80} (78 models) | V1-type claim-level 50/50 split stratified by LoB × AY (thesis text now says "randomly split"; the SSRN version says "split" and refers to Paper C's Listing 2, which allocates alternately): 21-epoch moving-average validation Poisson deviance of claim amounts | 192–193 |
| [D] Epochs | 400 (average of per-LoB optima), with predictions averaged over epochs 390–410 (same). Thesis now calls the 21-epoch average "similar in spirit to neural network ensembles" [27] = Hansen & Salamon 1990 (S15) | S12 + S15 | 0–1,000 | V1 | 194–195 |
| [D, thesis-only] Ablation models A–D | For each of the 4 ablation variants, neurons and epochs are **re-selected separately** with the §3.2.1 procedure under one fixed Keras seed; each variant is then run on 100 random seeds. Selected values for B–D are not reported | S6 + S12 per variant, then S18 ablation | same grid as §3.2.1 | V1; results judged by bias against the true reserves (evaluation only) | 198–200 |
| [D] Dropout 20%, L2 = 0.001 | same in both versions | S1 (no search) | — | — | 186 |
| [E] All hyperparameters | q = (40, 30, 10, 10) fixed directly; nadam; batch 10,000; structured dropout on past-payment embeddings; per-LoB epochs (Table 2: 40/30/60/60/50/30; Table 3: 40/50/60/90/50/140) | **No differences** from the SSRN version of 28 May 2020 were found | — | — | 229, 232, 235–236 |

### Richman–Wüthrich 2026a
**Document.** Richman, R., Wüthrich, M.V. (2026). *From Chain-Ladder to Individual Claims Reserving*. arXiv:2602.15385v2 [stat.AP], "Revised Version of February 19, 2026". **arXiv preprint.**

**Network(s).** Four separate plain feed-forward networks per dataset (one per development period j = 0,…,3). Each maps the latest individual claim state (payments, status and covariates; plus incurred and case reserve for liability) directly to the ultimate claim. Architecture: 3 tanh hidden layers (20, 15, 10), exponential output, MSE loss. Applied to an accident dataset and a liability dataset (5×5 annual squares each).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth | 3 hidden layers | S1/S2: "Selected FNN architecture", described as "elementary"/"plain-vanilla" and "a crude proposal". Implementation referred to Wüthrich–Merz [24, Listing 7.1]. No search | none | VX | 3, 12–13 |
| Width | (20, 15, 10); 606 weights (accident) / 646 (liability) | S1/S2 as above; the same architecture is reused for all j and for both datasets | none | VX | 13 |
| Activation | tanh hidden; exp output | S1 (the exp output is later criticised because it cannot produce zero claims) | — | — | 13, 20 |
| Input pre-processing | log-standardised payments/incurred; [0,1]-scaled month and log reporting delay (censored at 365 days) | S4 (standard practice: "should be standardized") | — | — | 13–14 |
| Optimiser, learning rate | Adam, 10⁻³ | S1/S3 (10⁻³ equals the Keras Adam default; the paper does not say whether this is deliberate) | — | — | 14 |
| LR schedule | reduce LR on plateau, factor 0.9, patience 5 | S13, fixed values, no justification. Listed in Table 4 under the row label "Early stopping" | — | VX (monitored quantity not stated) | 14 |
| Epochs / early stopping | max 1,000 epochs "with early stopping". The stopping rule itself (monitored metric, patience) is not specified beyond Table 4 | S12 | — | V1: 9:1 learning/validation split (whether random is not stated); MSE | 14 |
| Batch size | 4,096 | S1 | — | — | 14 |
| Ensemble size / seeds | 10 fits with different seeds, averaged (each balance-corrected) | S15 (nagging, citing Richman–Wüthrich [16]); size 10 fixed without justification | — | — | 14 |
| Dropout / L2 / other regularisation | none stated. Bias control is achieved via a balance correction (multiplicative rescaling to the in-sample mean) and, as a suggestion only, CL/BF guard-rails | S19 for dropout and weight penalties | — | — | 14–15 |

### Richman–Wüthrich 2026b
**Document.** Richman, R., Wüthrich, M.V. (2026). *One-Shot Individual Claims Reserving*. arXiv:2603.11660v1 [stat.AP], "Version of March 13, 2026". **arXiv preprint** (follow-up to arXiv:2602.15385).

**Network(s).** (i) Feed-forward networks, one per recursion step j−1, that replace the paper's main linear-regression projection-to-ultimate (PtU) models: 2 GELU hidden layers (20, 15), identity output, MSE loss. Used in the accident example (§4.4) and in the liability example (§5, "Model CIO" FNN column). (ii) A small single-attention-layer Transformer over the past payment and status history (§4.5; Listing 6). The main recommended models are linear regressions, not NNs.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| FNN depth / width | 2 hidden layers, (20, 15); 140 + 315 + 16 weights | S1: "The specific selected FNN architecture is documented in Table 11". No search described | none | VX | 29, 37 |
| FNN activation / output | GELU hidden, identity (linear) output on a standardised response | S1 | — | — | 29, 37 |
| Input features / pre-processing | standardised log payments; accident month continuous; manual interaction payments × claim status | S4 (manual feature engineering) | — | — | 29, 37 |
| Optimiser, learning rate | Adam, 10⁻³ | S1/S3 (equals the Keras default) | — | — | 29, 37 |
| LR schedule | ReduceLROnPlateau, factor 0.9, patience 5, cooldown 0 | S13, fixed | — | VX (monitored quantity not stated in the text; Keras default is val_loss) | 29, 37 |
| Epochs / early stopping | max 500 epochs; best-validation weights restored via `callback_model_checkpoint(save_best_only = T)` and then reloaded | S12 (checkpoint-based early stopping) | 1–500 | V1 (nominally): 10% validation split, MSE. In code, Keras `validation_split = 0.1` takes the last 10% of rows, not a random subset (see flags) | 29, 37 |
| Batch size | 8,192 | S1 | — | — | 29, 37 |
| Ensemble size / seeds | 10 fits with different seeds (averaged, balance-corrected) | S15, size 10 fixed without justification | — | — | 29 |
| Regularisation (dropout, L2) | none | S19. A post-fit multiplicative balance correction (eq. 4.9, code line 58) removes the in-sample bias | — | — | 30, 37 |
| Transformer: embedding / attention width | `units0 = c(10, 15, 10)`: 10-dim time-distributed linear embedding plus Q/K/V projections; one Keras `layer_attention` (dot-product, scaled); residual adds; one layer normalisation | S1: "we only select “simple” linear embeddings" | none | VX | 31, 38 |
| Transformer: head FNN | 2 GELU layers (15, 10), linear output | S1 | — | — | 38 |
| Transformer: fitting settings | not restated. Listing 6 "focuses on the differences to Listing 5", so presumably the same Adam/500/8,192 set-up (not explicit) | S19 / inferred S2 (reuse of Listing 5) | — | — | 31, 38 |
| Transformer used for j−1 = 0? | no; the FNN is used there (only one past period) | S4 (structural) | — | — | 31 |

### Richman–Wüthrich 2021 LocalGLMnet
**Document.** Richman, R., Wüthrich, M.V. (2021). *LocalGLMnet: interpretable deep learning for tabular data*. arXiv:2107.11059v1 [cs.LG], "Version of July 26, 2021". **arXiv preprint** (v1). A later journal version, if any, was not examined.

**Network(s).** LocalGLMnet: a feed-forward network (tanh hidden layers, linear output of dimension q) produces feature-dependent "regression attentions" β(x). These enter a GLM-type predictor g(µ) = β0 + ⟨β(x), x⟩ through a skip connection. Fitted to (i) synthetic Gaussian data (q = 8) and (ii) French MTPL claim frequencies (Poisson, log link, q = 42, reduced to 38). A plain FFN (20, 15, 10) is the benchmark.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Benchmark FFN depth/width | d = 3, (20, 15, 10) | S2: "the R code for this FFN architecture is given in Listing 7.1 of Wüthrich–Merz [31]" (input dimension changed from 40 to 42) | none | VX | 15 |
| LocalGLMnet depth/width | synthetic: (q0,…,q4) = (8, 20, 15, 10, 8); MTPL: (42, 20, 15, 10, 42); reduced MTPL: q0 = q4 = 38 | S1/S2: the benchmark FFN (20, 15, 10) plus an attention output layer whose size is forced to equal the input dimension (a structural constraint, not a choice) | none | VX | 9, 15, 17 |
| Activations | tanh (m = 1, 2, 3), linear (m = 4, attention layer); output: identity link (Gaussian) / log link (Poisson) | S1 (links: canonical link of the EDF) | — | — | 9, 15 |
| Optimiser | nadam (Keras default settings; learning rate not stated) | S1/S3 | — | — | 9, 15, 24 |
| Epochs / early stopping | synthetic: epochs not stated; MTPL: 100 epochs, keeping "the network calibration that provides the smallest validation loss" | S12 (best-validation checkpoint) | ≤ 100 epochs (MTPL) | V1: synthetic 80/20 training/validation split of the learning data (whether random is not stated), MSE; MTPL: training/validation partition U/V of the learning data (proportion not stated), Poisson deviance | 9, 15 |
| Batch size | MTPL: 5,000; synthetic: not stated | S1 | — | — | 15 |
| Train/test split (MTPL) | random, n = 610,206 / 67,801, "exactly the same split as in Table 5.2 of Wüthrich–Merz" | S2 | — | — | 15 |
| Categorical encoding | one-hot (not dummy coding) for Vehicle Brand and Region | S4: reasoned choice (dummy coding would give a zero-contribution reference level, so no local interactions) | one-hot vs. dummy | — | 14–15, 20 |
| Input scaling | continuous and binary inputs centred and scaled to unit variance | S4: required for SGD and for the selection test | — | — | 11, 14 |
| Regularisation (dropout, L2, lasso) | none. No weight penalty is used; sparsity is obtained by a post-hoc test instead | S19 (no penalty) | — | — | — |
| **Feature-selection threshold** (determines input dimension q0 = q4) | significance level α = 0.1%, giving the interval Iα = ±3.2905 · ŝ(control); ŝ from injected random control features (synthetic: x7, s.d. 0.0461; MTPL: RandU 0.052, RandN 0.048). Final MTPL input 42 → 38 | **NEW S25: empirical-null variable-selection test.** An i.i.d. random control covariate is added and trained with the network; its attention spread defines the null interval. α is fixed by fiat (S1). The final drops were made by **judgement (S4)**, overriding the test: Area Code and VehPower were dropped although their coverage ratios (97.1%, 98.1%) are below 1 − α, so the test says "keep" | α only (no alternatives tried); control distribution uniform vs. normal compared | V9: coverage ratio of β̂j(x) within Iα on the fitted data. Confirmation by refit: out-of-sample Poisson deviance on the test set T (23.945 → 23.912 × 10⁻²) | 11, 15–17 |
| Seeds / repetitions | not stated (a single fit is reported) | S19 | — | — | — |
| Spline smoother for gradient plots (not an NN hyperparameter) | locfit `alpha = 0.1, deg = 2` | S1 | — | — | 24 |

### Richman 2024
**Document.** Richman, R. (2024). "An AI Vision for the Actuarial Profession." *CAS Forum*, Summer 2024 (July), Essays section. **Essay / practitioner forum paper** (no empirical study).

**Network(s).** NONE. The paper does not fit a neural network. It is a vision essay. It does not describe or recommend any procedure for choosing NN hyperparameters (no mention of tuning, validation, early stopping, dropout, ensembles, etc.).

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Yeldan–Karabey 2026
**Document.** Yeldan, M., Karabey, U. (2026). *Dispersion modeling in Tweedie compound Poisson with combined actuarial neural networks*. *Communications in Statistics – Simulation and Computation*, published online 17 Sep 2026, DOI 10.1080/03610918.2026.2732143. **Journal article (online-first version)**. Based on the first author's PhD thesis (Hacettepe University).

**Network(s).** Feed-forward networks for Tweedie compound-Poisson pure premium on the Yip–Yau auto dataset (10,296 policies, 80/20 train/test): NN, CANN (GLM skip connection + FFN, exp output), and the "double" versions DNN and DCANN. In the double versions a second CANN models the dispersion with a Gamma deviance on unit deviances, alternating with the mean network until convergence.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Hidden-layer widths (depth fixed at 3) | mean ("Tweedie") network (15, 10, 5); dispersion ("Gamma") network (25, 15, 10) | S6 grid search, run **separately** for the mean and dispersion networks | {(25,20,15), (25,15,5), (20,15,10), (15,10,5)}; depth 3 fixed by fiat (S1) | V3 5-fold CV on the training set (80%). Criterion: average validation deviance **plus** the validation–training gap (combination rule not specified; Table 2 instead reports the validation–**test** gap, see flags) | 4, 12 |
| Batch size | 1,250 (mean); 1,500 (dispersion) | S6 (same grid) | {750, 1000, 1250, 1500} | V3 as above | 12 |
| Epochs | 50 (both networks) | S6 (epoch count is a grid dimension; no early stopping mentioned) | {50, 100, 150, 200} | V3 as above | 12 |
| Hidden activation | not stated (only: activations "may vary across the nodes"); output exponential (log link) | S19 / S1 | — | — | 6 |
| Optimiser, learning rate | "gradient descent algorithm" with learning rate ϱt; type and value not stated | S19 | — | — | 7 |
| Dropout / L2 / other regularisation | not stated. The authors present the val–train gap criterion as their anti-overfitting device | S19 | — | — | 4, 12 |
| Hyperparameters of the pure NN / DNN (non-CANN) models | not stated. Table 2 gives only "optimal CANN models", and the text says hyperparameters were determined for "the CANN models" | S19 (reuse implied, not stated) | — | — | 12 |
| Ensemble size (nagging) | Table 4 averages "all" predictions over different initialisations. Figure 5 plots test NLL for M = 1,…,50 | S15 (nagging, citing Richman & Wüthrich 2020). The size is not selected, only shown to stabilise | M = 1…50 | V5-type display only (test NLL vs. M) | 13–14 |
| DCANN alternation (mean ↔ dispersion) | "until deviance loss convergence"; tolerance not stated | S4 | — | V6 (training deviance) | 10 |
| Seeds | multiple random initialisations for nagging; individual seeds not stated | S15 | — | — | 13–14 |
| *(Out of scope, one line)* Tweedie power p | estimated per model by profile likelihood on the training data **after** hyperparameter tuning (not part of the grid); the p used during tuning is not stated | — | candidate p in (1, 2) | profile NLL | 10, 12–13 |

## A.3 Monash (Avanzi, Taylor, Wong) and co-authors; ReSurv; Balona–Richman

### Al-Mudafer et al. 2021
**Document.** Muhammed Taher Al-Mudafer, Benjamin Avanzi, Greg Taylor, Bernard Wong (2021), "Stochastic loss reserving with mixture density neural networks", arXiv:2108.07924v1 [stat.ME], 18 Aug 2021 (PDF footer dated August 19, 2021). **arXiv preprint**. The journal version (Insurance: Mathematics and Economics 105, 144–174, 2022) is cited in Avanzi et al. (2024), but this file is the preprint.

**Network(s).** A Mixture Density Network (MDN): a fully connected feed-forward net with inputs (accident quarter i, development quarter j) whose output layer gives the weights, means and s.d.s of a K-component Gaussian mixture (or a log-Gaussian mixture fitted to ln X). Also a ResMDN, where a fixed embedding-layer skip connection carries a ccODP GLM approximation and the MDN boosts it. Fitted to 40×40 quarterly incremental-paid triangles: 4 SynthETIC environments with 50 triangles each, plus 10 AUSI real-data 36×36 triangles.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| L2 weight penalty λw | Table A: Env1 MDN 0; Env2 MDN 0.001; Env2 ResMDN 0; Env3 MDN 0; Env3 ResMDN 0* (manual override); Env4 MDN 0; AUSI MDN 0 | S9 with S6 inside each step. Step 2 of the one-at-a-time algorithm is a grid over λw with everything else at θ_initial = {0,0,0,60,2,2}. For the Env3 ResMDN the value was then **manually set to 0** (S4) | [0, 0.0001, 0.001, 0.01, 0.1] | V4: rolling-origin "test error" = negative log-likelihood of the mixture density on the test cells of two partitions inside the upper triangle, weighted by cell count (V8: NLL/log score). Averaged over T random initialisations per partition | p.11 §3.2; p.12 §3.2 steps 1–2; p.16 §4.1 eq. 4.2–4.4; p.34 Table A; p.36 App. D |
| L2 "sigma activity" penalty λσ (on the mixture s.d. outputs) | Env1 0.0001; Env2 MDN 0.1; Env2 ResMDN 0; Env3 MDN 0.0001; Env3 ResMDN 0; Env4 0; AUSI 0 | S9/S6: step 3, grid with λ̂w fixed | [0, 0.0001, 0.001, 0.01, 0.1] | V4 + V8 as above | p.11 §3.2; p.12 step 3; p.34 Table A |
| Dropout rate p | Env1 0; Env2 MDN 0.1; Env2 ResMDN 0; Env3 MDN 0; Env3 ResMDN 0.1; Env4 0; AUSI 0.1 | S9/S6: step 4, grid with λ̂w, λ̂σ fixed | [0, 0.1, 0.2] | V4 + V8 as above | p.11 §3.2 item 3; p.12 step 4; p.34 Table A |
| Number of hidden layers h (depth) | Env1 4; Env2 MDN 2; Env2 ResMDN 2; Env3 MDN 3; Env3 ResMDN 2; Env4 4; AUSI 3 | S9/S6: step 5, grid with regularisers fixed and **n held at 60, K at 2** | [1, 2, 3, 4] | V4 + V8 as above | p.11 §3.2 item 5; p.12 step 5; p.34 Table A |
| Neurons per hidden layer n (width) | Env1 60; Env2 MDN 100; Env2 ResMDN 20; Env3 MDN 80; Env3 ResMDN 60; Env4 40; AUSI 20 | S9, **tuned jointly with K** in step 6: for each K = 1, 2, … pick the best n (n_K) from the grid, and stop increasing K once E(n_{K+1}, K+1) is worse than E(n_K, K). Equal width in all layers is **fixed by design** (S1) | [20, 40, 60, 80, 100]; equal width across layers | V4 + V8 as above | p.11 §3.2 (constraints and item 4); p.12 step 6; p.34 Table A |
| (out of scope) Mixture components K | Env1 2; Env2 4/4; Env3 1/2; Env4 3; AUSI 3 | Tuned inside the same step-6 loop (greedy increase). For the ResMDN, K was preset to the MDN's value | K = 1, 2, … until no improvement | V4 + V8 | p.12 step 6; p.36 App. D |
| Activation function (hidden layers) | sigmoid | S1: "set constant" before the algorithm runs, with no justification given | none | none | p.11 §3.2 |
| Output activations | softmax (α), identity (µ), exponential (σ) | S5/S2: standard MDN design, justified by the parameter constraints (Bishop 1994; Hjorth & Nabney 2000) | none | none | p.7 §2.3.2 |
| Skip/CANN connection (ResMDN) | Embedding-layer skip connection carrying ccODP mixture parameters, frozen during training | S2: adapted from the ResNet/CANN design of Gabrielli, Richman & Wüthrich (2020), Wüthrich & Merz (2019) and He et al. (2016). Presented as an alternative model, not tuned | MDN vs ResMDN, both reported | Compared after the fact on lower-triangle metrics (Tables 4–6) | p.3 §1.2.3; p.8 §2.4.2; pp.30–31 |
| Optimiser | Adam | S4: "via experimentation", compared with RMSProp and SGD | Adam, RMSProp, SGD | V9: "most stable training" (qualitative; data not stated) | p.16 §4 |
| Learning rate | 0.001 | S4: stated together with Adam "via experimentation". (0.001 is also the Keras default for Adam, but the paper does not say it used the default.) | not stated | V9: training stability | p.16 §4 |
| Epochs / early stopping | Early stopping on the validation loss, patience 1000 epochs; cap of 10 000 epochs during the hyperparameter search; training usually lasted several thousand epochs (10–15 thousand for large or high-dropout nets) | S12 (early stopping); patience = S4 (a smaller patience "would sometimes prematurely stop training"); 10 000 cap = S4 (for efficiency) | not stated | V2: validation set = 4 latest non-test calendar quarters (excluding the first 3 AQ/DQ). The paper does not say whether the monitored validation loss includes the penalty terms | p.10 §3.1; p.16 §4 |
| Batch size | not stated | S19 | not stated | not stated | none |
| Weight initialisation | MDN: random ("different weight initialisation" per run; scheme not stated). ResMDN: final-hidden-layer weights initialised at 0 so the network starts at the GLM | MDN: S19 for the scheme. ResMDN: S2 (follows Gabrielli, Richman & Wüthrich 2020) | none | none | p.9 §2.4.2; p.16 §4.1 |
| Repeated runs per θ during tuning (T) | T runs per partition, 2T per θ, errors averaged; **the value of T is not stated** | S15-type averaging over initialisations inside the selection signal; T = S19 | not stated | Averaged V4 NLL | p.16 §4.1 |
| Final ensemble size | 5 fits with different initialisations, densities averaged (eq. 4.7). Env3 adjusted scheme: 3 fits on Partition 3 plus 2 on Partition 4 | S15 (averaging over seeds); number 5 = S1 (no justification, apart from citing Perrone & Cooper 1993 for ensembling) | none | none | p.17 §4.3; p.34 App. B |
| Input/response scaling | inputs standardised; response normalised | S4: "through early experimentation" (a preprocessing choice, not strictly a hyperparameter) | none | V9: convergence | p.16 §4 |

### Avanzi et al. 2024
**Document.** Benjamin Avanzi, Yanfeng Li, Bernard Wong, Alan Xian (2024), "Ensemble distributional forecasting for insurance loss reserving", *Scandinavian Actuarial Journal* 2024:9, 971–1012, DOI 10.1080/03461238.2024.2365392 (published online 3 Jul 2024; open access). **Journal version.**

**Network(s).** NONE. The paper does not fit a neural network. The ensemble ("linear pool": SLP/ADLP) combines 18 component models: GLMs with ODP, log-normal and gamma errors, zero-adjusted GLMs, smoothing splines and GAMLSS. NNs were deliberately excluded (criterion 3, §2.2).

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Avanzi et al. 2025
**Document.** Benjamin Avanzi, Matthew Lambrianidis, Greg Taylor, Bernard Wong, "On the use of case estimate and transactional payment data in neural networks for individual loss reserving", arXiv:2601.05274v1 [q-fin.ST], stamped 28 Dec 2025 (PDF footer dated January 12, 2026). **arXiv preprint.** (The file "(2)" is a byte-identical duplicate: `cmp` reports no difference.)

**Network(s).** Four individual-claim models that predict (normalised) log ultimate claim size under MSE loss, with Duan bias correction afterwards: FNN and FNN+ (feed-forward on summarised payment data; "+" adds case-estimate summaries), and LSTM and LSTM+ (LSTM layers on transaction time series, then two feed-forward layers that also take static inputs; "+" adds case-estimate histories). Categorical covariates enter via embeddings. Data: 50 SPLICE "complexity 5" simulated datasets (about 30,000 claims each), plus one separate dataset used only for tuning.

*selected values read from the bold entries in Table D.6, PDF p. 25 image*

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of layers (LSTM layers for LSTM/LSTM+; total FF layers for FNN/FNN+) | LSTM+ 3; LSTM 2; FNN+ 4; FNN 2 | S6: full grid, one training run per combination, each model tuned separately | LSTM/LSTM+ {2, 3}; FNN/FNN+ {2, 3, 4} | V2: minimum validation loss (MSE on normalised log ultimate). Validation set = claims finalised in calendar quarters 36–40, minus 20% moved to training. Measured on **one separate simulated dataset** | p.13 §3.4; p.25 Table D.6 and App. D |
| Units per layer (LSTM units, or FF units for FNN) | LSTM+ 16; LSTM 16; FNN+ 16; FNN 32 | S6 (same grid) | LSTM {8, 16}; FNN {16, 32} | V2 as above | p.25 Table D.6 |
| Units in the two post-LSTM feed-forward layers | not stated | S19 | not stated | none | p.25 App. D |
| Embedding dimensions (legal rep, severity, age) | not stated | S19 (embeddings appear in Figs 1–2 only) | not stated | none | p.4 Figs 1–2 |
| Recurrent cell type | LSTM | S2: Lambrianidis (2024) found LSTM better than vanilla RNN and GRU "in this context" | RNN, GRU, LSTM (in the prior thesis) | V9: prior work | p.7 §2.2 |
| Activation function | ReLU in hidden FF layers; linear output | S1: "No other activation functions have been tested" | none | none | p.25 App. D |
| Optimiser | AdamW | S1: only AdamW was used (the paper says "we tested the AdamW optimiser" but gives no alternatives) | AdamW only | none | p.25 App. D |
| Learning rate | 0.01 for all four models | S6 | {0.001, 0.01} | V2 as above | p.25 Table D.6 |
| Max epochs / early stopping | 200 max epochs; early stopping on validation loss with best weights restored. Patience **10 (text) vs 5 (Table D.6)** | S12 (early stopping); max epochs and patience = S4 ("after some initial testing") | none | V2: validation loss | p.25 Table D.6; p.26 App. D |
| Batch size | LSTM+ 512; LSTM 256; FNN+ 512; FNN 512 | S6 | LSTM {256, 512}; FNN {512, 1024} | V2 as above | p.26 App. D; p.25 Table D.6 |
| Dropout rate | 0 | S4: "Non-zero dropout rates were initially tested, however the results were not compelling". The values tried are not stated | not stated | not stated (judgement) | p.26 App. D |
| Normalisation layers | batch norm before the activation in every FF layer except the last; layer norm after each LSTM layer | S1: stated without justification | none | none | p.26 App. D |
| Weight initialisation / seeds | random initialisation; one run per combination; seed values not stated | S19 (the authors acknowledge the randomness was not mitigated) | none | none | p.13 §3.4; p.19 §5 |
| Ensemble | none | none | none | none | none |

### Avanzi et al. 2026
**Document.** Benjamin Avanzi, Ronald Richman, Bernard Wong, Mario Wüthrich, Yagebu Xie, "Reinforcement Learning for Micro-Level Claims Reserving", arXiv:2601.07637v1 [q-fin.RM], 12 Jan 2026 (PDF footer dated January 13, 2026). **arXiv preprint.**

**Network(s).** (i) A Soft Actor-Critic (SAC) reinforcement-learning agent. Its policy (actor) and value (critic) functions are neural networks, but their architecture is never specified. The agent updates each open claim's OCL estimate multiplicatively, period by period. (ii) A benchmark fully connected FNN that predicts the OCL under an importance-weighted MSE. Data: 5 CAS simulated datasets (annual, valuation year 15) and 30 SPLICE datasets (quarterly, valuation quarter 40, complexity 1 and 5).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| FNN number of hidden layers | not stated | Said to be "tuned" through Rolling Settlement Validation; **search strategy not stated** (S19). No grid, random, Bayesian or Optuna search is mentioned | not stated | V4 (a new variant: expanding window by claim **settlement** time, k = 3 folds on training period [0, 40]) + V7: aggregate relative OCL (predicted/true) closest to 1, averaged over folds | p.20 §5.2.3; p.23 §7.3; p.36 App. B.2 |
| FNN nodes per hidden layer | not stated; equal in every hidden layer | Tuned (S19 strategy). Equal widths = S5 ("typical in practice ... to reduce the complexity of hyperparameter tuning") | not stated | V4 + V7 as above | p.36 App. B.2 |
| FNN batch size | not stated | tuned (S19 strategy) | not stated | V4 + V7 | p.36 App. B.2 |
| FNN dropout rate | not stated | tuned (S19 strategy) | not stated | V4 + V7 | p.36 App. B.2 |
| FNN learning rate | not stated | tuned (S19 strategy) | not stated | V4 + V7 | p.36 App. B.2 |
| FNN optimiser, activation | not stated | S19 | none | none | none |
| FNN epochs / early stopping | Early stopping on a 20% sub-fold (80-20 split of each rolling-settlement fold); patience not stated | S12 (described in Remark 5.2, partly in the conditional "we would train on the first 80% of S1") | none | V2-type sub-fold within the fold | p.20 Remark 5.2 |
| SAC actor/critic architecture (depth, width, activation) | not stated | S19 | not stated | not stated | none |
| SAC optimiser, learning rate(s), replay-buffer size, batch size, entropy temperature | not stated | S19 | not stated | not stated | none |
| RL training passes (epochs) | one pass through the training data | S1 (a property of the RL design as described; no early stopping) | none | none | p.20 Remark 5.2 |
| RL algorithm | SAC (over PPO) | NEW S21 (a-priori argued choice): off-policy replay buffer means better sample efficiency with limited reserving data. No empirical comparison reported | PPO, SAC (discussed) | none | p.16 §4.3 |
| Seeds / repetitions | not stated | S19 | none | none | none |
| (outside the three families: RL- and loss-specific) action bound K, reward accuracy multiplier C, warm-up steps M, past-prediction window n, importance-weight temperature α, discount γ | K = 2 ("often led to better performance than larger values"); γ = 0.99 "arbitrarily chosen"; C, M, n, α "tuned" but values not stated | K: S4. γ: S1. C, M, n, α: tuned through the same RSV procedure, search strategy S19 | not stated | V4 + V7 (data for the K observation not stated) | p.10 Remark 3.3; p.12 §4.1.1; p.14 §4.1.2; p.15 §4.1.3; p.21 §6.1 |

### Balona–Richman 2020
**Document.** Caesar Balona, Ronald Richman (14 August 2020), "The Actuary and IBNR Techniques: A Machine Learning Approach". **SSRN preprint / working paper** (every page carries "Electronic copy available at: https://ssrn.com/abstract=3697256").

**Network(s).** NONE. The paper does not fit a neural network. It tunes the "actuarial-judgement" parameters of Chain Ladder (CL), Bornhuetter-Ferguson (BF) and Generalised Cape Cod (GCC) with the Python chainladder package. It is recorded here because it proposes the **back-tested, next-diagonal (rolling-origin) grid-search tuning scheme** that NN reserving papers cite and borrow (e.g. Al-Mudafer et al. 2021/2022).

*No network fitted: listed for the selection method it describes (Sections 3–4).*

| (non-NN) parameter | Selected | How determined | Candidates | Selection signal | Evidence (PDF p.) |
|---|---|---|---|---|---|
| CL: drop_high, drop_low, n_periods (accident years used for LDFs) | Swiss triangle: n_periods 11; drop_high selected under CDR, no drops under AvE | S6 exhaustive grid | drop_high/drop_low {True, False}; n_periods "k ∈ [10..19]"; stated as 36 combinations | V4 + V7: weighted RMSE of next-diagonal AvE or CDR, averaged over 13 back-test calendar years (1984–1996) | pp.16–17, Table 1 |
| BF: CL options + a-priori loss ratio | 59.0% (both scores); n_periods 15 (AvE) or 11 (CDR) | S6 | CL grid × LR {0.50, 0.51, …, 0.70} = 756 sets | V4 + V7 as above | p.22, Table 5 |
| GCC: CL options + decay | decay 0% (AvE, i.e. CL) or 95% (CDR); n_periods 11 | S6 | CL grid × decay {0.00, 0.05, …, 1.00} | V4 + V7 as above | pp.28–29, Table 10 |
| Quarterly triangles: method choice + options | Method with lowest MSE after each method's optimum | S6 | drop_high/low; n_periods k ∈ [5..21]; BF LR {0.40, …, 0.60}; GCC decay {0.00, …, 1.00} | V4 + V7: 11 back-test calendar quarters (2012Q1–2014Q3 accident quarters as training) | pp.35–36, Table 15 |

### Hiabu et al. 2025
**Document.** Munir Hiabu, Emil Hofman, Gabriele Pittarello (2025), "Claim Counts Prediction Using Individual Data with ReSurv", *CAS Forum*, Vol. Quarter 1, 2025 (April), Reserving Call Papers. This is a **practitioner/software paper** (package vignette style; ReSurv v1.0.0). The underlying methodology is in the "main manuscript", Hiabu, Hofman & Pittarello (2023), arXiv:2312.14549.

**Network(s).** A feed-forward NN for the log-risk score of a Cox-type proportional-hazards model of reporting delay (DeepSurv-style, after Katzman et al. 2018, corrected for left-truncation and ties). It is implemented in PyTorch via reticulate and trained on partial likelihood with an elastic-net penalty. Competing hazard models are COX (with splines) and XGB (gradient boosting). Data: one simulated dataset per scenario (SynthETIC-based `data_generator`, daily data over 4 years). Results are shown for scenario Alpha (and Delta from the main manuscript's replication material).

*final values = `hparameters_nn`, PDF p. 22*

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of hidden layers `num_layers` | 2 | S8: Bayesian optimisation with `ParBayesianOptimization::bayesOpt` (method attributed to Snoek, Larochelle & Adams 2012), wrapped around ReSurvCV K-fold CV | integer bounds [2, 10]. (The earlier illustrative grid, S6, used {1, 2}) | V3: 3-fold "standard K-Fold" CV (fold construction not described). Score = −(out-of-fold `test.lkh`), i.e. negative partial log-likelihood (V9) | pp.16–18 §2.4.2, §2.5.1; p.22 §2.6 |
| Neurons per layer `num_nodes` | 10 (**upper bound**) | S8 | [2, 10] (illustrative grid {2, 4}) | V3 + V9 as above | pp.17, 22 |
| Activation | LeakyReLU | S8 over a categorical index | {LeakyReLU, SELU} (illustrative grid: ReLU) | V3 + V9 | pp.17, 22 |
| Optimiser | SGD | S8 over a categorical index | {Adam, SGD} (illustrative grid: Adam) | V3 + V9 | pp.17, 22 |
| Learning rate `lr` | 0.02226655 | S8 | [0.005, 0.5] (illustrative grid: 0.5) | V3 + V9 | pp.17, 22 |
| Elastic-net penalty on partial likelihood `xi`, `eps` | xi = 0.4678993; epsilon = 0 (**lower bound**) | S8 | xi ∈ [0, 0.5], eps ∈ [0, 0.5]. **But Table 4 gives the range as [1, ∞)** | V3 + V9 | p.15 Table 4 (image); pp.17, 22 |
| Batch size | 5000 | S1: hard-coded `batch_size &lt;- as.integer(5000L)` inside the BO objective function | fixed at 5000 in the code, yet Table 5 reports varying batch sizes (196–4508) | none (fixed) | pp.17, 19, 22 |
| Epochs | 300 during CV/BO; **5500 in the final fit** | S1 (values stated without justification); change between tuning and final fit unexplained | none | none | pp.17–18, 22 |
| Early stopping / patience | TRUE; patience 20 during CV/BO; **350 in the final fit** | S12 (validation-based early stopping) with S1 values | none | Validation negative log-likelihood (`os_lkh`); how the final validation split is formed is not stated | pp.15, 17–18, 21–22 |
| Weight initialisation | not stated (PyTorch default presumably, but not stated) | S19 | none | none | none |
| Random seed (CV/BO) | `random_seed = as.integer(Sys.time())` | S1: clock-based seed, so not reproducible | none | none | pp.17–18 |
| Ensemble / repeats | none (single final fit) | none | none | none | p.22 |

## A.4 DeepTriangle and recurrent-network reserving

### Cai et al. 2025
**Document.** Pengfei Cai, Anas Abdallah, Pratheepa Jeganathan (2025). "Recurrent Neural Networks for Multivariate Loss Reserving and Risk Capital Analysis". arXiv preprint arXiv:2402.10421v3 [stat.AP], 11 Apr 2025 (McMaster University). Preprint, not a journal version.

**Network(s).** Extended Deep Triangle (EDT): a bivariate GRU sequence-to-sequence "Deep Triangle" (encoder GRU, decoder GRU, company-code embedding, two LOB-specific fully connected heads) fitted to 30 NAIC company pairs (personal + commercial auto); plus CTGAN / CopulaGAN (SDV library) used to generate synthetic triangles, with the DT re-fitted (fine-tuned) on each synthetic or block-bootstrap triangle.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Recurrent cell type | GRU (not LSTM) | S2: justified by citing Goodfellow et al. (2016) — fewer parameters, faster; DT design itself taken from Kuo (2019) | GRU vs LSTM (argued, not compared empirically) | none (argument) | p.5, p.3 |
| Number of recurrent layers | one encoder GRU + one decoder GRU (from Figure 1 image) | S2 (implicit, DT topology of Kuo 2019) / S1 — no justification | not stated | VX | p.6 (Figure 1 image) |
| GRU units (hidden state size) | not stated | S19 | not stated | VX | — |
| Dense head width / depth | 1 hidden layer of 64 units per LOB head, then 1 output unit | S1: stated without justification (paper does not attribute the value to Kuo) | not stated | VX | p.6 |
| Activation functions | GRU gates sigmoid, candidate tanh (equations 3-5); dense-layer activation not stated explicitly — He initialisation is justified as "recommended for ReLU", implying ReLU | S1 / S19 for the dense layer | not stated | VX | p.6, p.7 |
| Company-code embedding dimension | C − 1 (number of companies minus one; C = 30 in the application; the simulation uses 50 pairs but the dimension is not restated) | S5: rule of thumb (levels − 1), called "a predetermined hyperparameter" | not stated | VX | p.7 |
| Input / output sequence length | I − 1 = 9 time steps (masked) | S6 (one-dimensional sweep over lengths 1–9, done in the simulation study) + by construction of the design in §2.2 | lengths 1,…,9 (Figure 6 x-axis) | V1/V3 ambiguous: called "cross-validation error" in text/caption, y-axis labelled "validation error"; procedure not described; simulated data | p.3, p.7, p.17, p.18 (Figure 6 image) |
| Optimiser | AMSGrad variant of Adam | S4/S1: chosen by argument (handles high gradient variability from small samples); cites Reddi et al. 2018 | not stated | none (argument) | p.8 |
| Learning rate | not stated | S19 | not stated | VX | — |
| Batch size | not stated | S19 | not stated | VX | — |
| Epochs / early stopping | max 1000 epochs; stop if validation loss does not improve over a 100-epoch window; keep weights of lowest validation-loss epoch | S12 (patience 100 and cap 1000 are S1, unjustified) | not stated | V1: validation loss (MSE-type loss eq. 7 or variance-weighted eq. 8) on a random 80/20 split of training sequences, grouped so that the same (AY, DY) from all companies stays together — NOT a calendar-diagonal hold-out | p.7, p.8 |
| Validation set construction | random 80/20 split; for I = 10: 36 training and 9 validation sequences per company; same split rule re-applied inside each block-bootstrap replicate | S1 | — | V1 | p.7, p.8 |
| Weight initialisation (from scratch) | He initialisation | S2: He et al. (2015), "recommended for ReLU" (Murphy 2022) | not stated | none | p.7 |
| Weight initialisation for bootstrap / GAN replicates | warm start from the DT trained on the observed data, then fine-tuned | NEW S22 (warm-start / pre-train-then-fine-tune, chosen for computational cost) | from-scratch vs warm start (timing only: ~2 min vs ~1 min per sample) | none (computational) | p.3, p.12, p.13 |
| Dropout / L1 / L2 / weight decay | not stated (no regularisation of the DT reported; LASSO is only suggested as future work for the copula regressions) | S19 | — | VX | p.23 |
| Random seed | not stated | S19 | — | VX | — |
| Number of bootstrap / synthetic triangles (predictive-distribution ensemble size) | real data: "repeated multiple times" (number not stated); simulation: 1,000 synthetic triangles per pair | S1 | not stated | none | p.12, p.18 |
| Block-bootstrap block size | I (=10) | S1 / argued from exchangeability | not stated | none | p.8 |
| CTGAN / CopulaGAN hyperparameters | not stated (SDV library used; defaults not stated) | S19 (possibly S3, but not stated) | — | VX | p.10 |

### Cai MSc 2021
**Document.** Pengfei (Frank) Cai (May 2021). "Claim Reserving: Classical versus Machine Learning Methods". MSc thesis (Statistics), Department of Mathematics & Statistics, McMaster University; supervisors Anas Abdallah and Traian Pirvu. Thesis.

**Network(s).** (a) Kuo's (2019) DeepTriangle GRU sequence-to-sequence model (code from github.com/kasaai/deeptriangle), fitted to ONE company: first to one commercial-line triangle (paid + claims outstanding as the two outputs), then to the personal + commercial auto paid triangles of a major US insurer (two-line version); (b) a toy [784, 256, 10] sigmoid feed-forward net on MNIST in Chapter 4 (illustration only).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Model / recurrent cell type | Kuo's DeepTriangle, GRU (Keras `layer_gru`) | S2: "Kuo's DeepTriangle model" applied, code taken from Kuo's GitHub repository | none | none | p.15, p.61, p.85 |
| GRU units | 128 | S2 (implicit: value from Kuo's model; stated in the annotated code listing, not justified) | none | VX | p.87 |
| Dropout (input) | 0.2 | S2 (implicit, Kuo 2019; "see page 6 in Kuo (2019)") | none | VX | p.71, p.87 |
| Recurrent dropout | 0.2 | S2 (implicit, Kuo 2019) | none | VX | p.87 |
| GRU activations / initialisers | Listing reproduces the Keras `layer_gru` signature: activation "tanh", recurrent_activation "hard_sigmoid", kernel_initializer "glorot_uniform", recurrent_initializer "orthogonal" (and dropout = 0 in the signature, overridden to 0.2 in the argument notes) | S3: Keras defaults as printed in the reproduced function signature; not stated which were overridden besides units/dropout | none | VX | p.85, p.86, p.87 |
| Dense / output layers, number of GRU layers | not stated | S19 | — | VX | — |
| Input sequence length | 9 time steps (masked) | S1 / by construction (I − 1 for a 10×10 triangle), following Kuo | none | VX | p.15, p.64, p.77 |
| Optimiser | AMSGrad variant of Adam | S2 (implicit, Kuo's model) / S1 | none | VX | p.65 |
| Learning rate | 0.0005 | S1 as written ("is set to be"); implicitly Kuo's setting | none | VX | p.65 |
| Batch size | not stated (generic advice only: powers of 2, e.g. 32–256) | S19 | — | VX | p.58 |
| Epochs / early stopping | max 1000 epochs; stop if validation loss does not decrease over a 200-epoch window | S12 (cap and patience S1/S2) | none | VX for the DeepTriangle: "validation data" is never defined; all 45 upper-triangle samples are called training data | p.65, p.77 |
| Number of runs averaged (ensemble size) | 100 runs, predictions averaged | S15 (averaging over random dropout runs, justified by Lakshminarayanan et al. 2017); size 100 by S1 with an after-the-fact display of 1–100 runs (S18) | 1, 10, 20, 30, 40, 50, 100 runs (Table 5.19) | none (no stopping criterion) | p.15, p.73, p.74, p.76 |
| Random seed | not stated | S19 | — | VX | — |
| MNIST toy net: architecture / activation | [784, 256, 10], sigmoid | S1 | none | VX | p.56 |
| MNIST toy net: epochs | 100 epochs planned; training stopped after 84 epochs when validation loss rose | S12 | — | V1: validation loss on 20% of the training data | p.56 |

### Cai PhD 2025
**Document.** Pengfei (Frank) Cai (September 2025). "Advanced Dependence Modeling of Loss Reserves: Integrating Recurrent Neural Networks and Seemingly Unrelated Regression Copula Mixed Models for Diversified Risk Capital". PhD thesis (Statistics), McMaster University; supervisors Anas Abdallah and Pratheepa Jeganathan. Thesis. Chapter 2 is a thesis version of Cai, Abdallah & Jeganathan (arXiv 2402.10421); Chapter 5 is a new, explicitly preliminary hybrid DT + SUR copula mixed model.

**Network(s).** (Ch. 2) the bivariate Extended Deep Triangle (GRU encoder–decoder, company embedding, two 64-unit LOB heads) with CTGAN/CopulaGAN (SDV) and block bootstrap (App. A.3) for predictive distributions; (Ch. 5) a per-LOB Deep Triangle whose residuals are modelled by a SUR copula mixed model, with the DT then trained with a loss that adds the fitted SUR residuals. Chapters 3–4 are non-NN (SUR copula mixed models; sparse version with LASSO).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Recurrent cell type | GRU (not LSTM) | S2: argued via Goodfellow et al. (2016) (fewer parameters, faster); DT framework of Kuo (2019) | GRU vs LSTM argued only | none | p.33, p.34 |
| Number of recurrent layers | encoder GRU + decoder GRU (Figure 2.1, same as article) | S2 (implicit, DT) / S1 | not stated | VX | p.34 |
| GRU units | not stated | S19 | — | VX | — |
| Dense heads | 1 hidden layer of 64 units per LOB, then 1 output unit | S1 | not stated | VX | p.35 |
| Activation | GRU sigmoid/tanh (eqs 2.1–2.3); dense activation not stated (He init "recommended for ReLU") | S1 / S19 | — | VX | p.34–36 |
| Company embedding dimension | C − 1 ("a predetermined hyperparameter") | S5: levels − 1 rule | not stated | VX | p.35 |
| Input / output sequence length | I − 1 = 9 time steps (masks used "to fix sequence lengths for efficient batch processing") | S6 one-dimensional sweep (lengths 1–9, simulation study) | 1,…,9 | V1/V3 ambiguous: "cross-validation error" (text/caption) vs "validation error" (axis; App. A.3); simulated data | p.32, p.36, p.53, p.130 |
| Block-bootstrap block size (App. A.3) | I (sequence length) | S6-derived: set equal to the sequence length that minimised validation error in Figure 2.6 | lengths 1–9 | V1-type validation error (simulated data) | p.130 |
| Optimiser | AMSGrad (Adam variant) | S4/S1: argued (gradient variability from small samples); Reddi et al. 2018 | none | none | p.38; p.113 (Ch. 5) |
| Learning rate | not stated | S19 | — | VX | — |
| Batch size | not stated (batch processing mentioned) | S19 | — | VX | p.36 |
| Epochs / early stopping | max 1000 epochs; patience 100 epochs on validation loss; restore best weights | S12 (values S1) | none | V1: random 80/20 split grouped by (AY, DY) across companies; loss eq. 2.5/2.6 | p.36 |
| Weight initialisation | He initialisation (from scratch); warm start from DT fitted on real data for GAN samples | S2 (He et al. 2015) + NEW S22 warm-start/fine-tune | from-scratch vs warm-start (timing only) | none (computational) | p.32, p.36, p.42, p.46 |
| Dropout | "dropout is applied within the RNN" (Ch. 3 summary of EDT) — rate never stated; Ch. 2 does not mention dropout | S19 | — | VX | p.62 |
| L1/L2 / weight decay on the NN | not stated | S19 | — | VX | — |
| Random seed | not stated | S19 | — | VX | — |
| Number of GAN/bootstrap triangles | real data: "repeated multiple times"; simulation: 1,000 per pair | S1 | — | none | p.46, p.54 |
| CTGAN/CopulaGAN settings | not stated (SDV library) | S19 | — | VX | p.41 |
| Ch. 5 hybrid DT hyperparameters | only "AMSGRAD" stated; all others not stated; "a single run" reported | S19 (except optimiser S1) | — | VX | p.113, p.114 |
| (Non-NN, Ch. 4) LASSO penalties λ1, λ2 of the sparse SUR copula mixed model | pair minimising AIC | S17 (AIC over a λ grid) | not stated in detail | V9: AIC in-sample | p.97 |

### Ramos-Pérez et al. 2020
**Document.** Eduardo Ramos-Pérez, Pablo J. Alonso-González, José Javier Núñez-Velázquez (2020). "Stochastic reserving with a stacked model based on a hybridized Artificial Neural Network". arXiv:2008.07564v1 [q-fin.RM], 17 Aug 2020 (Universidad de Alcalá); p.1 states "This manuscript version is made available under the CC-BY-NC-ND 4.0 license". Preprint/author manuscript, not the typeset journal version.

**Network(s).** Stacked-ANN: level 1 = RF, GB, a feed-forward ANN (inputs scaled AY and DY), Chain Ladder factors and CSR (Bayesian MCMC) means; level 2 = a feed-forward ANN combining those inputs to predict scaled cumulative payments. An individual ANN (same as the level-1 ANN) is a benchmark. Fitted separately to each of 200 NAIC triangles (50 each in CA, PA, WC, OL).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of hidden layers (level-1 and level-2 ANN) | 2 | S2: literature review of one vs multiple hidden layers, then "several hidden layers" adopted; confirmed afterwards by S18 sensitivity (1, 2, 3 layers) | 1, 2, 3 hidden layers (sensitivity only) | V5 for the sensitivity: %RMSE of reserves / next-year payments / ultimates against the actually observed lower-triangle outcomes | p.4, p.5, p.10, p.12, p.20–22 |
| Neurons per hidden layer | 5 (both levels) | S1: no justification (literature on choosing neuron counts cited but not applied) | not varied | VX | p.5, p.10, p.12 |
| Activation functions | sigmoid in hidden layers, linear output (stated for the level-2 ANN; level-1 ANN activation not separately stated — benchmark ANN has the "same" characteristics as level-1 ANN) | S1 | none | VX | p.6, p.12 |
| Dropout rate θ (level-1 ANN) | tuned per triangle; mean by LOB (Table 1): CA 0.10, PA 0.07, WC 0.13, OL 0.12 | S6: grid search | grid values not stated | V2: RMSE on the last observed calendar diagonal (called the "test set"), model fitted on the rest of the upper triangle | p.9, p.10, p.14, p.15 |
| Dropout rate θ (level-2 ANN) | tuned per triangle; mean by LOB: CA 0.09, PA 0.06, WC 0.12, OL 0.12 | S6: grid search | grid values not stated | V2: RMSE on last observed diagonal | p.12, p.13, p.15 |
| Optimiser | Adam, β1 = 0.9, β2 = 0.999 | S3/S2: "default calibration proposed by the authors" (Kingma & Ba 2014) | none | none | p.12 |
| Learning rate | initial 0.01 (Adam adapts it) | S1 (+ S13: Adam's adaptive rate described as "progressive adaptation of the initial learning rate") | none | none | p.12 |
| Epochs | 10,000 | S1 (no early stopping) | none | none | p.12 |
| Batch size | full batch (= length of training data) | S1 | none | none | p.12 |
| Loss | RMSE | S1 | — | — | p.12 |
| Weight initialisation, seed | not stated | S19 | — | VX | — |
| Number of repeated fits / ensemble | not stated (single fit per triangle implied; stacking itself is the combination) | S19 | — | VX | — |
| (Non-NN) RF: N, Obs_RF; GB: Obs_GB; GB learning rate | RF/GB node sizes grid-searched per triangle (Table 1 means); GB learning rate fixed at 0.01 | S6 / S1 | not stated | V2 (same last-diagonal RMSE) | p.10, p.15 |

### Ramos-Pérez et al. 2022
**Document.** Eduardo Ramos-Pérez, Pablo J. Alonso-González, José Javier Núñez-Velázquez (2022). "Mack-Net model: Blending Mack's model with Recurrent Neural Networks". Expert Systems With Applications 201 (2022) 117146; received 21 Sep 2020, revised 8 Jan 2022, accepted 29 Mar 2022; open access. Journal version.

**Network(s).** For each of 200 NAIC triangles (paid and incurred separately), an ensemble of 20 identical LSTM-based RNNs (two LSTM layers, six fully connected layers, one skip connection; Fig. 2) forecasting next-year scaled payments from the last 8 lags; the averaged predicted triangle gives Mack-type parameters for a bootstrap. Code said to be on GitHub (github.com/EduardoRamosP/MackNet; not inspected here).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Recurrent cell type | LSTM (first layer of every RNN) | S1 / S2 (Hochreiter & Schmidhuber 1997 cited; "to take temporal dependencies into consideration") | none | none | p.4 |
| Architecture (layers, units) | from Fig. 2 image: LSTM layer 1 (16 units) → FC1 (8, ReLU) → two branches [FC2 (8, ReLU) → FC3 (8, ReLU)] and [LSTM layer 2 (16 units) → FC4 (8, ReLU)] → FC5 (4, ReLU) → FC6 output ("ReLU/Linear") | S1: stated in figure without justification | none | VX | p.4 (Fig. 2 image) |
| Skip / residual connection | skip connection FC1 → FC5 | S2: motivated by He et al. (2016) residual learning (lets network "skip" layers, avoids vanishing gradients) | with/without not compared | none | p.4 |
| Activation functions | ReLU in FC layers; output "ReLU/Linear" (Fig. 2); LSTM gates sigmoid/tanh (eqs 14–19) | S1 | none | VX | p.4 |
| Input window (sequence length) | last 8 lags of each input series | S5: constrained by triangle size ("chosen due to the size of the triangles"; 9 training development years ⇒ max lag t − 8) | none | none | p.4 |
| Optimiser | Adam, β1 = 0.9, β2 = 0.999 | S3/S2: "default values" suggested by Kingma & Ba | none | none | p.5 |
| Learning rate | initial 0.01 | S1 (+ S13 as Adam adapts it) | none | none | p.5 |
| Batch size | full batch (= number of training observations) | S1 | none | none | p.5 |
| Epochs / early stopping | not stated | S19 | — | VX | — |
| Loss | MSE | S1 | — | — | p.5 |
| Weight initialisation | Glorot for LSTM input kernels, orthogonal for recurrent kernels; each ensemble member randomly initialised | S2 (Glorot & Bengio 2010; Saxe et al. 2013); these coincide with the Keras LSTM defaults, but the paper does not call them defaults | none | none | p.5 |
| Dropout rate θ | 5% | S1: "In order to avoid overfitting … is set to 5%" | none | none | p.5 |
| Ensemble size | 20 RNNs, predictions averaged | S15 + S2: "high enough to obtain the average model prediction regardless their initial weights"; strategy attributed to Kuo (2018) | not varied | none | p.4 (Fig. 1 "Ensemble of 20 RNNs") |
| Hold-out set | last observed diagonal / development year held out as "test set"; RNNs trained on the remaining 9 development years | S1 | — | V2 (hold-out by time) — but its use for any selection is not described | p.3, p.4 |
| Random seed | not stated | S19 | — | VX | — |

### Nicholas MSc 2026
**Document.** Anna-Lise Nicholas (May 2026). "Evaluation of Long Short-Term Memory Neural Networks for Actuarial Reserving of Auto Long-Tail General Insurance Claims". MSc thesis (Mathematics and Statistics, Collaborative Specialization in AI), University of Guelph; advisor Ayesha Ali. Thesis.

**Network(s).** Re-uses the customised multi-task micro-level reserving LSTM of Chaoubi et al. (2023) (static-feature linear layer, one layer of 128 LSTM cells, payment-probability and payment-amount heads) with their code, refitted to 17 simulated scenarios of Gabrielli–Wüthrich individual-claims data (replicated), for five learning rates; a bidirectional LSTM was tried cursorily. (The data simulator itself consists of 35 pre-calibrated feed-forward networks, not fitted here.)

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Recurrent cell / depth | one layer of LSTM cells (unidirectional); bidirectional LSTM tried on a small sample and dropped | S2 (Chaoubi et al. 2023 design) + S18 (cursory bidirectional check) | uni- vs bidirectional | V5-type: reserve/ultimate predicted-to-actual ratios on test sets (not detailed) | p.24, p.47 |
| LSTM units | 128 parallel cells | S2 (Chaoubi et al.) | none | VX | p.24; Fig. 8 p.26 |
| Static-feature linear (embedding-like) layer | 37 inputs → 32 output nodes, no activation; LSTM input depth 36 = 32 + 4 (from Fig. 8 image) | S2 (Chaoubi et al.) | none | VX | p.24, p.26 (Fig. 8 image) |
| Output heads / activations | linear head for standardised payment; linear + sigmoid head for payment probability | S2 | none | VX | p.25, p.26 |
| Optimiser | stochastic gradient descent | S2 (Chaoubi code) | none | VX | p.27, p.35 |
| Learning rate | five values run as a study factor; "best" = 0.001 | S6-like grid over 5 values, used as an evaluation factor rather than a tuning step | 0.0001, 0.0005, 0.001, 0.01, 0.05 | V5: mean/median reserve and ultimate predicted-to-actual ratios computed on the test sets against true reserves | p.35, p.45, p.47, p.48 |
| Learning-rate schedule | reduce by factor 0.1 after 10 epochs without validation improvement | S13 (ReduceLROnPlateau-type), values S2 | none | V1: validation error | p.27 |
| Epochs / early stopping | max 500 epochs; early stopping patience 15 epochs (active after the LR-schedule patience of 10) | S12 (values S2) | none | V1: validation error on a 20% stratified (by LOB) random claim-level split; train/validation/test = 60/20/20 | p.27, p.34 |
| Batch size | 2048 | S2 | none | VX | p.24 |
| Teacher-forcing schedule | n_p = 10, s_p = 0.01 | S2 | none | VX | p.25 |
| Weight initialisation | random (general statement) | S19 for the specific scheme | — | VX | p.22 |
| Random seed | seeds set per simulated data set (e.g. Table 28: LR 0.001 with seed 2503) | S1 | — | — | p.29, p.70 |
| Dropout / L2 | not stated (regularisation paragraph mentions only early stopping) | S19 | — | VX | p.27 |
| Replicates | "seventy replicates" mentioned once (unit of replication and choice of 70 not described) | S1 | — | — | p.43 |

### Mienye et al. 2024
**Document.** Ibomoiye Domor Mienye, Theo G. Swart, George Obaido (2024). "Recurrent Neural Networks: A Comprehensive Review of Architectures, Variants, and Applications". Information 2024, 15, 517 (MDPI), doi:10.3390/info15090517; received 21 Jul 2024, accepted 23 Aug 2024, published 25 Aug 2024. Journal review article.

**Network(s).** NONE — paper does not fit a neural network (narrative review of RNN architectures and applications). It does make general statements about choosing RNN architecture/training settings, recorded below as recommendations.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Nirmala 2026 (bibliography only)
**Document.** Arnaya Inggid Nirmala (supervisor Prof. Dr. Drs. Gunardi, M.Si.) (2026). "Analisis Model Sequence-to-Sequence Berbasis Gated Recurrent Unit (GRU) dengan Embedding dan Multi-Task Learning untuk Estimasi Cadangan Klaim Asuransi" [Analysis of a GRU-based sequence-to-sequence model with embedding and multi-task learning for insurance claim reserve estimation]. Undergraduate (Bachelor's) thesis, Universitas Gadjah Mada; downloaded from etd.repository.ugm.ac.id. Thesis. **Only the bibliography ("DAFTAR PUSTAKA", printed pp. 125–131; PDF pp. 1–7) survives in the supplied file; no methods, results or hyperparameter values are available.**

**Network(s).** Cannot be determined from the surviving extract. The title indicates a GRU sequence-to-sequence model with (entity) embedding and multi-task learning, i.e. a DeepTriangle-type design, but no model specification is present.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

## A.5 Individual-claims networks (Bayesian, LSTM-attention, spline)

### Kuo 2020 BMDN
**Document.** Kevin Kuo (February 2020), "Individual Claims Forecasting with Bayesian Mixture Density Networks", *CAS Research Papers*, © 2020 Casualty Actuarial Society. Research report in the CAS research-paper series (not a journal article). Section headings in the PDF are unnumbered; the § labels below use the headings (the paper's own cross-references imply numbering such as "Section 4.4").

**Network(s).** A Bayesian mixture density network (BMDN): an encoder–decoder with embedding layers for static categorical claim features, one-layer LSTM encoders for the payment/status sequences, a one-layer LSTM decoder repeated over 11 future steps, and two dense *variational* (Bayes-by-backprop style) output layers that parameterise zero-inflated shifted log-normal mixtures for paid losses and recoveries. Fitted to about 497k simulated claims (Gabrielli–Wüthrich simulator). Code: github.com/kasaai/bnn-claims (R + TensorFlow).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Overall architecture template (encoder–decoder with sequence output) | adapted from DeepTriangle | S2: adapted from Kuo (2019) DeepTriangle | none | VX | p. 5, p. 13 |
| Embedding dimension (all categorical features) | n = 2 | S1: "chosen by the modeler", no justification | none | VX | p. 15 |
| LSTM layers (each encoder and the decoder) | 1 layer | S4: "found that these relatively small modules provided reasonable results"; no systematic search | none reported; deeper/larger nets explicitly not tested | VX: "reasonable results" (metric and data not stated) | p. 15 |
| LSTM hidden units | 3 | S4: as above | none reported | VX | p. 15 |
| Decoder sequence length (repeat count) | 11 | Set by the forecast horizon (maximum 11 steps ahead), not tuned | none | n/a | p. 14 |
| Dense variational output layers | 2 layers (paid, recovery), 4 output units each; weights shared across time steps | Set by the output distribution (4 parameters per mixture), not tuned | none | n/a | p. 14, p. 16 |
| Which weights are Bayesian | only the two dense output layers; embeddings and LSTMs are point-estimated | S1 (implied by the description; no reason given) | none | n/a | p. 14–16 |
| Prior on variational weights | P(w) = N(0, I) (zero mean, unit variance, fixed) | S1 (+S14): fixed standard-normal prior; no prior-scale tuning | none | n/a | p. 15–16 |
| Variational posterior family | mean-field Gaussian N(μ(θ), σ(θ)), both trainable | S14 (+S2: follows Graves 2011, Blundell et al. 2015) | none | n/a (fitted by ELBO) | p. 7, p. 15–16 |
| KL weighting | KL multiplied by abs(D_i)/abs(D) per minibatch, i.e. 1/abs(D) per training sample (full KL once per epoch; no annealing or β-tempering described) | S2: standard minibatch ELBO of Graves (2011) / Blundell et al. (2015) | none | n/a | p. 8 (Eq. 7–8, from page image), p. 18 (Eq. 19, from page image) |
| Weight samples per training step | 1 sample per training sample | S1/S2 (standard Bayes-by-backprop estimator; no justification) | none | n/a | p. 9 |
| Posterior (weight) samples at scoring | 1,000 draws for the single-claim plots; 1 draw per claim per model for the aggregate point estimate | S1: no justification; author notes more draws would give "an even more stable estimate" | none | n/a | p. 20, p. 22 |
| Activation functions | not stated | S19 | — | — | — |
| Optimiser | stochastic gradient descent | S1 | none | n/a | p. 19 |
| Initial learning rate | 0.01 | S1 | none | n/a | p. 19 |
| Learning-rate schedule | halve LR when validation loss has not improved for 5 epochs (plateau schedule; factor 0.5, patience 5) | S13 (factor and patience by S1) | none | V1: "validation loss" on a random 5% subset of training records | p. 19 |
| Minibatch size | 100,000 | S1 | none | n/a | p. 19 |
| Epochs | early stopping; patience 10; cap 100 | S12 (patience and cap by S1) | none | V1: validation loss, random 5% subset of the training set | p. 19 |
| Weight initialisation | not stated (only that it is random) | S19 | — | — | p. 22 |
| Random seed | not stated | S19 | — | — | — |
| Dropout / L1 / L2 / weight decay / normalisation | none mentioned (the only regulariser described is the KL term on the output layers) | S19 | — | — | — |
| Ensemble size | 10 independently trained models, predictions averaged | S15 (size by S1; motivated by random initialisation) | none | n/a | p. 22 |

### Pittarello et al. 2022
**Document.** Gabriele Pittarello, Gian Paolo Clemente, Diego Zappa (September 27, 2022), "An individual model for claims reserving based on Bayesian neural networks". The PDF gives no journal, arXiv or SSRN identifier, so it is a preprint or working paper dated 27 Sept 2022 (venue not printed).

**Network(s).** A system of Bayesian neural networks (multilayer perceptrons trained by Bayes by Backprop with Gaussian variational posteriors and a Normal output for the development factor), one network per development period. Each predicts individual chain-ladder development factors from claim features, following Wüthrich (2018). The data come from the Gabrielli–Wüthrich simulator, and the benchmark is Wüthrich's individual chain-ladder NN.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Neurons per hidden layer | **not stated** | S6? (comparison of combinations from discrete sets; whether the full factorial grid was run is not stated) + S4 (the "most appropriate" combination picked by inspecting TensorBoard; no decision rule given) | {16, 20, 32} | VX/V9: MSEP, MAE and "prediction accuracy" on "the validation data" (construction of validation data not described; section titled "Cross-validation" but no folds described) | p. 10 (Table 2, from table image) |
| Number of hidden layers | **not stated** | as above | {1, 2} | as above | p. 10 |
| Optimiser | **not stated** | as above | {adam, RMSprop} | as above | p. 10 |
| Activation functions | **not stated** | as above | {relu, tanh, exponential, linear} | as above | p. 10 |
| Learning rate | **not stated** | as above | {0.001, 0.01} | as above | p. 10 |
| Batch size | not stated | S19 | — | — | — |
| Epochs / early stopping | not stated | S19 | — | — | — |
| Weight initialisation, random seed | not stated | S19 | — | — | — |
| Variational posterior | Gaussian g(w) ~ N(μ, σ), θ = (μ, σ), per weight | S14 (+S2: Bayes by Backprop of Blundell et al. [1], TensorFlow implementation [9]) | none | n/a (ELBO: "complexity cost" + "likelihood cost") | p. 6–8 |
| Prior on weights P(w) | **not stated** (named "the weights prior" but its form and scale are never given) | S19 | — | — | p. 7 |
| KL weighting | not stated (Eq. 8 adds complexity and likelihood cost with unit weights; no minibatch scaling described) | S19 | — | — | p. 7–8 |
| Weight samples per update | 1 (ε ~ N(0,1) drawn once per update in the algorithm as written) | S2 (Bayes by Backprop as in [1], [9]) | none | n/a | p. 8 |
| Posterior samples at prediction | not stated (only "mean predictions" reported) | S19 | — | — | p. 4, p. 10 |
| Which layers are Bayesian | not stated (exposition covers "the first hidden layer" weights only) | S19 | — | — | p. 6 |
| Dropout / L2 / ensembles | none mentioned | S19 | — | — | — |

### Schneider–Schwab 2025
**Document.** Judith C. Schneider and Brandon Schwab (2025), "Advancing loss reserving: A hybrid neural network approach for individual claim development prediction", *Journal of Risk and Insurance* 92(2):389–423, DOI 10.1111/jori.12501. Received 21 March 2024, revised 27 November 2024, accepted 29 November 2024. Open-access journal version (Wiley). Code for a synthetic dataset: github.com/brandonschwab/advancing_loss_reserving.

**Network(s).** A multi-task hybrid network for RBNS individual incurred development. Static features pass through 2-d embeddings and a ReLU FC layer. Dynamic features pass through one LSTM layer with Lai et al. (2018) dot-product attention. The two are concatenated into a ReLU FC layer with two heads: an identity-activation regression head (next-period cumulative incurred, MSE) and a sigmoid classification head (probability of change, BCE). Task weights are balanced by GradNorm, and predictions are combined by a threshold rule. The model is fitted to proprietary property and liability data from an industrial insurer, in cumulative and incremental versions. The C-LSTM of Chaoubi et al. (2023) is a further NN benchmark.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Learning rate (lr) | Property cum. 0.004; Property incr. 0.00043; Liability cum. 0.0851; Liability incr. 0.0273 (Table B3) | Two-stage S7 → S8: random search (32 configs), then Bayesian optimisation (32 further configs) over a box spanned by the top-3 random-search configs; tuned separately per dataset × cumulative/incremental | Random stage: log-uniform on [1e−5, 0.1]; Bayesian stage: [min, max] of top-3 random configs | V1: validation loss (the only validation criterion named; the metric used to rank "top three configurations" is not stated explicitly), random 20% of claims within the training (upper-triangle) data | p. 13, 33, 34–35 |
| Static hidden size q_static (FC after embeddings) | Property cum. 128; Property incr. 256; Liability cum. 128; Liability incr. 64 | S7 → S8 as above | {32, 64, 128, 256} | V1 as above | p. 33, 35 |
| LSTM hidden size q_lstm | 128 in all four settings | S7 → S8 as above | {32, 64, 128, 256} | V1 as above | p. 33, 35 |
| Combined-vector hidden size q_comb | 128 in all four settings | S7 → S8 as above | {32, 64, 128, 256} | V1 as above | p. 33, 35 |
| Batch size | 1024 in all four settings | S7 → S8 as above (every top-3 random-search config already had 1024, so the Bayesian stage bounds are the single value 1024) | {1024, 2048} | V1 as above | p. 33, 34, 35 |
| Dropout rate | Property cum. 0.378; Property incr. 0.338; Liability cum. 0.458; Liability incr. 0.2509 | S7 → S8 as above; where dropout is applied is not stated | uniform on [0.1, 0.5] | V1 as above | p. 33, 35 |
| Number of LSTM layers / FC layers | one LSTM layer; one FC layer on static features; one FC layer after concatenation; two single-FC heads | S1 (architecture fixed, not tuned; "inspired by" Chaoubi et al. 2023) | none | n/a | p. 10–12 |
| Attention | dot-product attention "identical to that used by Lai et al. (2018)" | S2 | none | n/a | p. 12 |
| Embedding dimension | 2 for every categorical variable | S2: "According to Kuo (2020) and Gabrielli (2021)" | none | n/a | p. 11 |
| Activation functions | ReLU (FC layers); identity (regression head); sigmoid (classification head) | S1 | none | n/a | p. 11–12 |
| Optimiser | Adam, default parameters, only lr tuned | S3 (Adam defaults "recommended by the authors") | none | n/a | p. 32 |
| LR schedule | step decay: × 0.1 every 10 epochs | S13 (+S3: "we use the default settings") | none | n/a | p. 32 |
| Epochs / early stopping | max 100 epochs; stop if validation loss does not improve for 10 consecutive epochs | S12 (cap and patience S1) | none | V1: validation loss, random 20% of claims | p. 33 |
| Refit | final model retrained with best hyperparameters on training + validation data | (refit step; epoch count for the refit not stated) | — | — | p. 35 |
| Weight initialisation, random seed | not stated | S19 | — | — | — |
| L1/L2 / weight decay / batch-norm | none mentioned | S19 | — | — | — |
| Bagging ensemble (robustness study) | 100 bootstrap resamples of claims; models trained with the *random-search-best* hyperparameters; point estimate = average of 100 reserves | S15 (size 100 by S1) + S18 (used as robustness/sensitivity check) | none | n/a | p. 21–22 |
| C-LSTM benchmark hyperparameters | not reported (text says the "best hyperparameters identified by Random Search" were used for C-LSTM in the bootstrap) | S7 (implied); values not given | not stated | not stated | p. 14, 22 |

### Schwab PhD 2025
**Document.** Brandon Schwab (2025), *Robust and Explainable AI for Risk Prediction in Insurance and Finance*. Doctoral dissertation (Dr. rer. pol.), Wirtschaftswissenschaftliche Fakultät, Gottfried Wilhelm Leibniz Universität Hannover. Referees: Prof. Dr. Judith Christiane Schneider and Prof. Dr. Alexander Szimayer. Date of defence 25.09.2025. PhD thesis made of three papers: - Ch. 2 is the JRI 2025 article (item 3 above); - Ch. 3 is based on Schwab & Kriebel, *EJOR* 2025; - Ch. 4 is based on a 2025 working paper by Schneider & Schwab.

**Network(s).** - **Ch. 2:** the hybrid LSTM–attention multi-task reserving network, identical to Schneider–Schwab 2025. - **Ch. 3:** fine-tuned BERT ("BERT" and adversarially trained "Robust BERT") classifiers for P2P-loan default from loan descriptions (Lending Club). Their outputs enter logistic regressions. - **Ch. 4:** an Interpretable Mixture-of-Experts (IMoE): a soft-decision-tree router with Neural Additive Model (NAM) experts. It is benchmarked against an MLP, a NAM and XGBoost on Lending Club credit data and a proprietary German motor-frequency dataset (Poisson).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| **Ch. 2 (reserving)**, all in-scope hyperparameters | Identical to Schneider–Schwab 2025 Tables B1–B3 (Tables A.3–A.5 here) | Same two-stage S7 → S8 procedure, same wording | Same | Same (V1) | p. 42, 69–74 |
| Ch. 2: *difference only*, Table A.6 caption | Same seconds as JRI Table B4 (11,764 … 39,854) | Caption now says these are "training time ... for the final models using the best hyperparameters", whereas the chapter text (p. 42) presents them as tuning cost | — | — | p. 42, 74 |
| **Ch. 3 BERT**: pretrained model and head | BERT plus an added classification layer; BERT variant (base/large, cased/uncased) not stated | S2 (pretrained BERT, Devlin et al. 2019); variant S19 | — | — | p. 85–86 |
| Ch. 3 BERT: learning rate | 2e-5 (BERT); 3e-5 (Robust BERT) | S6 grid, with the grid taken from Devlin et al. (2019) guidelines (S2) | {5e-5, 3e-5, 2e-5} | V1: "best performance on the validation set" (metric not named); 10,000-observation validation set (random split, per Ch. 4's description of the same partition) | p. 87, 116–117 |
| Ch. 3 BERT: number of epochs | 4 (BERT); 2 (Robust BERT) | S6 grid (epochs are a grid dimension; no early stopping mentioned) | {2, 3, 4} | V1 as above | p. 87, 117 |
| Ch. 3 BERT: batch size | printed as **0.5** (BERT) and **0.4** (Robust BERT), values that are not in the search space | S6 grid | {16, 32} | V1 as above | p. 117 (table image) |
| Ch. 3 BERT: optimiser, warm-up, weight decay, dropout, max sequence length, seed | not stated | S19 | — | — | — |
| Ch. 3 Robust BERT | re-tuned on the same grid after adversarial augmentation of the training set | S6 (separate grid search per model) | as above | V1 as above | p. 90, 117 |
| **Ch. 4 MLP**: depth × width | 10 hidden layers × 100 units | S1 (fixed, not tuned; no source given) | none | n/a | p. 159 |
| Ch. 4 MLP: activation / output | ReLU; exponential output for Poisson | S1; exponential output justified by the canonical log link (S5-like rule) | none | n/a | p. 138, 159 |
| Ch. 4 MLP: dropout | not reported | S6 ("light grid search") | {0.0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5} | V1: validation AUC (credit) / validation Poisson deviance (frequency) | p. 159 |
| Ch. 4 MLP: learning rate; optimiser | lr not reported; Adam | lr S6; Adam S1 | {0.0001, 0.001, 0.01} | V1 as above | p. 159 |
| Ch. 4 NAM: subnetwork size | 5 layers × 40 units per feature | S2: "following Yang et al. (2021)" | none | n/a | p. 161 |
| Ch. 4 NAM: dropout, lr, optimiser | not reported; Adam | S6 grid (same ranges as MLP); Adam S1 | dropout {0.0 … 0.5}; lr {0.0001, 0.001, 0.01} | V1 as above | p. 161 |
| Ch. 4 IMoE: expert subnetworks | 5 × 40, ReLU, exponential output for counts | S2 (same as NAM / Yang et al. 2021) | none | n/a | p. 161 |
| Ch. 4 IMoE: dropout; lr (experts and router) | not reported | S6 grid | dropout {0.0, 0.05, …, 0.5}; lr {0.0001, 0.001, 0.01} | V1 as above | p. 161 |
| Ch. 4 IMoE: number of experts | credit: 2 (text refers to "the two experts"); frequency: 3 | S6 grid | {2, 3, 4} | V1 as above | p. 141, 144, 146, 161 |
| Ch. 4 IMoE: router tree depth | credit: 2; frequency: 3 | S6 grid | {2, 3, 4} | V1 as above | p. 141, 146, 161 |
| Ch. 4 IMoE: routing-temperature annealing | T0 = 2, × 0.98 per epoch, lower bound T_min (value not stated) | S1 (a schedule on the routing temperature, not the LR) | none | n/a | p. 134, 161 |
| Ch. 4 IMoE: phase lengths / epochs | warm-up 50, specialisation 100, fine-tuning 100 epochs, "maximum of 500 epochs total"; top-k with "typically k = 1" | S1 | none | n/a | p. 135, 161 |
| Ch. 4 IMoE: structural-regulariser weights λ_g, λ_p, λ_e, λ_lb, λ_eb | all 0.01 | S1 ("weighted equally"), not tuned although called hyperparameters | none | n/a | p. 133, 161 |
| Ch. 4 IMoE: minimum expert usage | 10% | S1 | none | n/a | p. 161 |
| Ch. 4 all NN models: early stopping | patience 100 epochs on validation loss | S12 (patience S1) | none | V1: validation loss | p. 159 |
| Ch. 4 all models: batch size, seed, weight initialisation | not stated | S19 | — | — | — |
| Ch. 4 repetitions | 10 repeated hold-out splits (train/validation reshuffled, test fixed); mean ± sd reported | S15-like averaging of *results* (not an ensemble of predictions) | — | — | p. 138 |
| Ch. 4 XGBoost (non-NN baseline) | eta 0.05 fixed; max depth tuned; 500 rounds; early-stopping patience 1000 rounds | eta S1; depth S6 | depth {3, …, 8} | V1 as above | p. 159 |

### Bücher–Rosenstock 2022
**Document.** Axel Bücher and Alexander Rosenstock, "Supplementary Material: Micro-level Prediction of Outstanding Claim Counts using Neural Networks". The page header reads "Springer Nature 2021 LATEX template", and no journal name, volume or year is printed on the supplement. **Only the supplement is in the folder; the main paper is not available.** The supplement's own §-references ("Section 3.3", Eq. (9)) point to the main paper, which could not be checked.

**Network(s).** A feed-forward network (embedding + scaling head, dense "body", distributional "tail"/adaptor) that maps claim/policy features (x, t, y) to the parameters θ of a reporting-delay distribution (a BDEGP family: Dirac + Erlang mixture + GPD). It is trained with the main paper's loss (9). The supplement gives the architecture template and initialisation; the numerical settings are in the main paper's §3.3, which is not available here.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Embedding dimension d_i (per discrete feature) | not stated in supplement (called "a fixed hyperparameter") | not stated in supplement (S19 here; may be in main paper) | — | — | p. 2 |
| Number of dense layers N_dense | not stated in supplement (Figure A1 *illustrates* three hidden layers) | S19 here ("to be considered as a hyperparameter of the model") | — | — | p. 2, 3 |
| Nodes per dense layer n_j | not stated in supplement | S19 here | — | — | p. 3 |
| Activation (dense layers) | softplus | S4: they "experimented with" ReLU and "found results to be worse than with the smooth softplus" | {softplus, ReLU} | VX: criterion and data not stated ("results") | p. 3 |
| Output/adaptor activations | identity / softplus / sigmoid / softmax per parameter type (dictated by the parameter space Θ) | Set by parameter constraints (structural, not tuned) | none | n/a | p. 4 |
| Weight initialisation, embeddings | U[−0.05, 0.05] | S1 | none | n/a | p. 5 (Algorithm S.1, from page image) |
| Weight initialisation, dense layers | Glorot/Xavier uniform: A ~ U[−l, l] with l = sqrt(6/(n_j + n_{j−1})); biases 0 | S2: cites Glorot & Bengio (2010) [3] | none | n/a | p. 5 (from page image) |
| Weight initialisation, tail | bias b = f_adaptor^{-1}(θ̂) (inverse link of a *global* estimate θ̂); weights A = Diag(b)·U[−0.1, 0.1] | S5-type heuristic: start the network at the homogeneous (global-fit) model | none | n/a | p. 4, 5 |
| Input scaling of continuous features | centred and scaled by empirical mean and sd (motivated by numerical stability under random initialisation) | S1 (cites Ioffe & Szegedy [2] as illustration) | none | n/a | p. 2–3 |
| Optimiser, learning rate, batch size, epochs / early stopping, regularisation, seeds, ensembling | not in the supplement (the supplement defers to main-paper §3.3) | S19 (for this document) | — | — | — |

### Belabed et al. 2025
**Document.** Abdelilah Belabed, Karim Doumi, Oussama Merzguioui, Ahmed Zellou (2025), "Optimizing Non-Life Insurance Technical Reserves: The Contribution of Neural Networks under the Solvency II Directive", *2025 International Conference on Intelligent Systems: Theories and Applications (SITA)*, IEEE, DOI 10.1109/SITA67914.2025.11273366. Peer-reviewed conference paper (IEEE Xplore version).

**Network(s).** "SplineNet", a network for individual incremental claim payments on SPLICE simulated data. Its layers are: - 12 input features, each passed through its own per-feature non-linear map; - a linear–ELU block; - five rational-quadratic "SplineFlowLayer" modules; - a learned sigmoid gate mixing a direct-effects path S(h) and an interaction path I(h); - a Softplus output.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Number of spline (SplineFlowLayer) layers | 5 | S1 | none | n/a | p. 4 |
| Spline bins / knots / tail bounds | not stated | S19 | — | — | — |
| Width of linear–ELU block and of the other dense layers | not stated | S19 | — | — | — |
| Activations | ELU (first block); rational-quadratic spline transforms; sigmoid gate; Softplus output | S1 (Softplus justified by positivity / avoiding gradient saturation; ELU α not stated) | none | n/a | p. 3–4 |
| Per-feature input maps | one map per input feature (12) | S1 | none | n/a | p. 3 |
| Elastic-net penalty weights λ1 (L1), λ2 (L2) | **not stated** | S19 | — | — | p. 4 |
| Epochs | 500 ("full epochs"); no early stopping described | S1; training and validation MSE curves *monitored* as an overfitting check (S18-type diagnostic, not selection) | none | V? "validation set" (construction not described); MSE | p. 6–7 |
| Validation design | a "time-based validation flag and a cross-validation index" were created | S19 (how they were used, and whether any hyperparameter was selected with them, is not stated) | — | V2/V3 mentioned, use not described | p. 2–3 |
| Optimiser, learning rate, batch size, initialisation, seed, dropout, ensembling | not stated | S19 | — | — | — |

### Mahohoho et al. 2023
**Document.** Brighton Mahohoho, Charles Chimedza, Florance Matarise, Sheunesu Munyira (2023), "Artificial Intelligence Based Automated Actuarial Loss Reserving Model for the General Insurance Sector", *Research Square* preprint (labelled "Research Article"), posted 4 July 2023, DOI 10.21203/rs.3.rs-3124884/v1, CC BY 4.0. Preprint, not peer-reviewed in this version.

**Network(s).** An "Artificial Neural Network (ANN)" fitted with the R package **nnet** is one of eight ML regressors (GLM, GAM, CART, RF, XGBoost, LAR, SVM, ANN). Each is used for the frequency, severity and inflation models on simulated car-insurance/microfinance data (40,000 policyholders) and for a second-stage "Robust" reserve regression. Architecture details are not reported. The nnet package itself fits single-hidden-layer networks, which is a property of the package and is not stated in the paper.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Hidden layers | not stated (nnet supports a single hidden layer only; implied by the package, not stated) | S19 (depth implied by software) | — | — | p. 12 |
| Hidden units (nnet `size`) | **not stated** | S19 | — | — | — |
| Weight decay (nnet `decay`) | not stated | S19 | — | — | — |
| Iterations (`maxit`), convergence criteria | not stated | S19 | — | — | — |
| Activation / output unit (linear vs logistic) | not stated | S19 | — | — | — |
| Optimiser, learning rate, batch size, epochs, early stopping, seed, initialisation | not stated | S19 | — | — | — |
| Ensembling / repetitions | none reported | S19 | — | — | — |

## A.6 Master's theses on reserving

### Härkönen MSc 2021
**Document.** Vilma Härkönen (2021), "On Claims Reserving with Machine Learning Techniques", Master Thesis in Actuarial Mathematics, Masteruppsats 2021:4, Mathematical Statistics, Stockholm University, June 2021 (supervisor Mathias Millberg Lindholm). MSc thesis.

**Network(s).** (a) "simple NN": the ODP-embedding cross-classified NN of Gabrielli, Richman & Wüthrich (2020) [ref 5], fitted separately for claim counts and claim amounts (this is the model the brief calls Gabrielli et al.'s bCCNN; the thesis itself calls it the "simple neural network"); (b) "double NN": the neural-network-boosted double ODP model of Gabrielli (2020, ASTIN Bull.) [ref 4] (two FFNs, claim-counts layer, payout-attention layer, joint scaled-deviance loss). Both in R keras; 6 simulated LoBs (Gabrielli–Wüthrich simulation machine) and 3 Folksam LoBs. (Also GBM, not an NN.)

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth, simple NN | H = 3 hidden layers | S2 (section follows [5] "if not stated otherwise") + S4 judgement ("we decide", to capture structure beyond ODP) | none | none | p.14, p.16 |
| Width, simple NN | q1=20, q2=15, q3=10 | S2 (section follows Gabrielli, Richman & Wüthrich 2020 [5]); no justification given for the numbers | none | none | p.14, p.17 |
| Depth / width, double NN (both FFNs) | H = 2; q1=30, q2=25; second FFN re-uses first FFN's architecture | S2: "We follow [4]" (Gabrielli 2020); second FFN "for simplicity" re-uses the first (S1/S2) | none | none | p.19, p.21 |
| Hidden activation | tanh (all hidden layers, both models) | S4/judgement with stated reason (cheap gradient f'=1−f², bounded output) | none | none | p.17, p.19 |
| Output activations | exponential (simple NN, counts layer, amounts output); linear for payout-attention layer | S2 (model structure of [5]/[4]) | none | none | p.17, p.22 |
| Embeddings | 1-d (simple NN) / 2-d for AY and RD, 1-d for PD (double NN), initialised at ODP ML estimates; non-trainable by default | S2 (ODP-embedding design of [5],[4]); non-trainable by judgement (S4). Trainable variant (TW) tried afterwards; for real data TW chosen for simple NN "as the results are much better" | {non-trainable, trainable} | For simulated data: reported as a test on reserve bias vs true reserves; for real data the choice was made on reserve results = V5 (lower triangle / truth) + V7 (relative reserve bias) | p.19, p.35, p.49 |
| Skip connection (CANN-type) | yes, ODP predictor added to NN output (both models) | S2 ([5], [4]) | none | none | p.17, p.20 |
| Dropout | 20 % at every layer (double NN, both FFNs); simple NN: not stated | S2 ("We follow [4]" sentence) / S1 | none | none | p.19, p.21 |
| L2 penalty | λ = 0.001 each hidden layer (double NN); simple NN: not stated | S2 / S1 (same sentence as above) | none | none | p.19, p.21 |
| Batch normalisation | applied to ordered claim-counts layer s_ord (double NN) | S2 (section states "we follow closely the neural network model description in [4]"; cites Ioffe & Szegedy [9]) | none | none | p.18, p.22 |
| Optimiser | RMSProp (R keras) | S2/S4: justified by Goodfellow et al. [7] as "effective" and "widely used" | none | none | p.24, p.25 |
| Learning rate, rho | not stated (refers reader to keras documentation) | S19 (S3 plausible but not stated) | none | none | p.25 |
| Batch size | not stated | S19 | — | — | — |
| Weight initialisation | output weights 0, output bias = ODP intercept, attention bias 1 / weights 0 so training starts at ODP; other weights not stated | S2 (ODP-start initialisation of [5],[4]) | none | none | p.17, p.20, p.22 |
| Max epochs (budget) | 10 000 | S1 | none | — | p.34 |
| Number of epochs (final) | per model × LoB, e.g. simulated data (Table 2): simple NN counts 9 950/9 865/9 266/9 893/4 566/2 567, simple NN amounts 9 560/274/421/9 899/392/326, double NN 7 549/6 285/2 115/7 423/7 935/944 (LoB 1–6); real data (Table 8): simple NN counts 7 227/6 308/8 729, amounts 9 721/8 629/6 526, double NN 3 000/9 565/1 207 (LoB 1–3) | S12: min of a central moving average (window 100) of the validation-loss curve over 10 000 epochs; the epoch count is then reused when refitting on the whole upper triangle (train+validation) | 1 … 10 000 | V1: validation loss (the §2.3.5 Poisson-deviance losses; metric not otherwise named) on a ~50/50 split of the individual claims, aggregated to triangles | p.29, p.34, p.35 (Table 2 from image), p.49 (Table 8 from image) |
| Random seed | 75 for the reported results; 20 extra seeds (65–84 and 1–20) for double NN | S1 (seed 75); S18/S15 robustness with 20 seeds, mean reserve computed | seeds 1–20, 65–84 | V7 (relative reserve bias vs true reserve, shown as boxplot) | p.38, p.39 |
| Ensemble / seed averaging | not used for headline results; 20-seed mean computed for double NN in a side experiment and recommended | S15 (side experiment, recommendation) | 20 seeds | V7 | p.39, p.55 |

### Zelený MSc 2026
**Document.** Ondřej Zelený (2026), "Beyond Chain-Ladder: Claims Reserving in the Machine Learning Era", Master's thesis, Charles University, Faculty of Social Sciences, Institute of Economic Studies, Prague (supervisor Jozef Baruník; dated Prague, May 4, 2026; 75 pp.). MSc thesis. Code: GitHub repo gr33nak/masters-thesis (Appendix B); shipped copy checked at `CODE_Zeleny_2026_masters-thesis-main.zip`.

**Network(s).** (a) a claim-level NN: a two-part MLP (an occurrence classifier plus a log-residual severity regressor) for RBNS, pooled plus Type-specific MLPs, fitted with sklearn MLPClassifier/MLPRegressor according to the code. (b) A "triangle-based NN": for each development transition j→j+1, a separate one-hidden-layer Keras network replaces the chain-ladder link ratio. Both are evaluated in a rolling-origin design over valuation years V = {2021,…,2025} on Gabrielli–Wüthrich simulated data. (XGBoost and classical models are also fitted but are not NNs.)

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Claim-level NN: depth / width | 3 hidden layers, (192, 96, 48), same for occurrence and severity heads | S4 (judgement): "deliberately compact", width-decreasing; no search reported ("not to exhaustively optimise") | none stated in the thesis. In the code the function defaults are (128, 64, 32) and the notebook call overrides them with (192, 96, 48); how the change was made is not documented | none stated | p.44, p.69 |
| Claim-level NN: activation | ReLU | S1 | none | none | p.44 |
| Claim-level NN: optimiser | Adam | S1 | none | none | p.44 |
| Claim-level NN: learning rate | 7 × 10⁻⁴ (initial) | S1 (no justification; code function default 8e-4 is overridden) | none | none | p.44 |
| Claim-level NN: L2 penalty | α = 2 × 10⁻⁴ | S1 (code function default 3e-4 is overridden) | none | none | p.44 |
| Claim-level NN: batch size | not stated in the thesis; the code does not set it, so sklearn's default 'auto' = min(200, n) applies | S19 in the text / S3 in the code | — | — | code `dl_pipeline.py` |
| Claim-level NN: epochs | max 280; early stopping, patience 20 | S1 (max, patience) + S12 (early stopping) | — | V1: 10% "held-out validation split" of the stacked training snapshots. The metric is not stated in the thesis. In the code it is sklearn `early_stopping=True, validation_fraction=0.1, n_iter_no_change=20`, i.e. sklearn's validation score (accuracy for the classifier, R² for the regressor; S3). Early stopping is switched off when there are fewer than 50 samples | p.44; code |
| Claim-level NN: pooled vs Type-specific blend | Type MLP fitted if ≥ 1 500 rows; blend weight α_t ∈ [0.20, 0.60], linear in the count | S1 (fixed rule) | none | none | p.44 |
| Triangle NN: depth / width | 1 hidden layer, 24 units | S1 in the thesis. The code labels it "Tuned default from Section 17.2 anti-overfit sweep" (method name "DL-Triangle-LinkRatio-NN-Tuned"), but that sweep is not in the shipped notebook | not stated | not stated (code label only) | p.45; notebook cell 61 |
| Triangle NN: activations | tanh hidden; exponential output; non-trainable linear offset multiplying by volume weight | S1 / S4 (exponential output "enforces positive outputs") | none | none | p.45 |
| Triangle NN: dropout | 30 % | S1 (hard-coded `Dropout(rate=0.30)` in the code) | none | none | p.45 |
| Triangle NN: L2 penalty | α = 2 × 10⁻³ | S1 in the text; "tuned" per the code comment (see above) | not stated | not stated | p.45 |
| Triangle NN: optimiser / LR | RMSprop, initial LR 10⁻³ | S1 in the text; "tuned" per the code comment | not stated | not stated | p.45 |
| Triangle NN: batch size | not stated in the thesis; code: min(10 000, max(32, n)) | S19 in the text / S1 in the code | — | — | code `dl_triangle.py` |
| Triangle NN: epochs | max 280; early stopping, patience 12 | S1 + S12 | — | V1: "10% validation split". Code: Keras `validation_split=0.1` (the last 10 % of the training rows in array order), monitoring `val_loss` = MSE of the scaled response, `restore_best_weights=True`. Only applied if ≥ 20 rows | p.45; code |
| Triangle NN: min sample threshold | &lt; 20 obs → chain-ladder fallback | S4 ("practical safeguard") | none | none | p.45 |
| Random seed (point forecasts) | not stated in the thesis; code random_state = 42 (triangle NN: seed 42 + j per transition network) | S19 in the text / S1 in the code | — | — | code |
| Seed ensemble size K | K = 20 for both NNs, used as an uncertainty diagnostic at one valuation year. Point forecasts are single fits, not ensemble means | S15-type repetition used for uncertainty (not for selection); K by fiat (S1) | none | V8-ish: CV and 90 % width of the reserve distribution (reported, not used for selection) | p.48, p.61 |
| Bootstrap replications B (NN) | text: B = 100 for both DL models. Table 5.10: B = 50 for both. Notebook: B = 100 for the triangle NN | S1; the text and table contradict each other | — | — | p.48, p.61 (table image) |

### Tavares MSc 2023
**Document.** Amanda Custódio Tavares (2023), "A Machine Learning Approach for Predicting Claims Reserving", Mestrado em Ciência de Dados, Departamento de Ciência de Computadores, Faculdade de Ciências da Universidade do Porto (orientador Rita Paula Almeida Ribeiro; case study with Ageas motor own-damage claims 2019–2022). MSc thesis.

**Network(s).** NONE. The thesis does not fit a neural network. The models are Random Forest, Gradient Boosting and XGBoost regressors of ultimate claim cost, with SHAP and feature importance for explanation. NNs appear only in the literature review and as future work.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Noordhoek MSc 2025
**Document.** Chris Noordhoek (2025), "Hybrid Modeling for Loss Reserving: Integrating Neural Networks with Traditional Techniques in Non-Life Insurance", MSc thesis in Quantitative Finance and Actuarial Science, Tilburg School of Economics and Management, Tilburg University (supervisor Erwin Charlier; dated April 19, 2025; data from Quantum Leben AG). MSc thesis.

**Network(s).** Feed-forward NNs that "boost" an ODP or ODG GLM, following the embedding and skip-connection structure of Gabrielli, Richman & Wüthrich (2018). There are five initialisation and trainability "cases": Case 2 is fully random; Case 3 fixes the GLM embedding; Case 4 uses a fixed GLM weight ω; Case 5 uses a trainable ω. They are fitted on one quarterly absenteeism loss-ratio triangle (I = 16, J = 13).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth / width | 3 hidden layers, (20, 15, 10) | S2: architecture "inspired by the work of Gabrielli et al. (2018)". The thesis itself says depth and width are "best chosen using hyperparameter tuning", but no tuning is done | none | none | p.37, p.39 |
| Hidden / output activation | tanh hidden; exponential output | S2 (Gabrielli et al. 2018 framework) | none | none | p.37, p.39 |
| Embeddings | two 1-d embeddings (accident quarter, development lag) set to the GLM parameter estimates | S2 / S5 (dimension fixed at 1 so that the embeddings equal the GLM parameters) | none | none | p.36, p.39 |
| Skip connection / GLM weight ω (CANN-type blend) and trainability "case" | Cases 2–5 compared; ω_start ∈ {0, 0.5, 1}; ω fixed (Case 4, 0.5) or trainable (Case 5). Preferred: ω_start = 0.5 for ODG; for ODP no boosted model beats the plain ODP | S4 / manual comparison of a handful of configurations (not a formal search) | Case 2 (random), Case 3 (ω = 1 fixed), Case 4 (ω = 0.5 fixed), Case 5 (ω_start ∈ {0, 0.5, 1}, trainable) | V6: in-sample MSE and MAE of the fitted upper triangle, plus visual comparison of development patterns and error heat-maps (Tables 4.1, 4.2); there is no hold-out ("all performance evaluations were performed in-sample") | p.38–39, p.51, p.56, p.59 |
| Dropout | 10 % after each hidden layer | S1 (motivated as reducing overfitting; no source or search) | none | none | p.39 |
| Optimiser | not stated (the literature review lists SGD, mini-batch GD and Adam) | S19 | — | — | p.26 |
| Learning rate | constant η = 0.001 | S1/S4: stated as "moderately small"; no search | none | none | p.40, p.57 |
| Batch size | full batch ("a single iteration per epoch") | S1 | none | none | p.40 |
| Epochs | 500 (§3.3, p.40) **and** 300 (end of §4.2, p.57); contradictory | S1, with no early stopping | none | none | p.40, p.57 |
| Weight initialisation | Xavier for the randomly initialised weights; random part scaled by (1 − ω) in Case 4; GLM estimates for the embeddings | S1 with a textbook reason (Glorot & Bengio 2010); GLM-based start S2 (Gabrielli et al.) | none | none | p.38–40 |
| Loss function (for reference) | not stated for NN training | — | — | — | — |
| Random seed / repetitions | not stated | S19 | — | — | — |
| L2 / weight decay, ensembles | not used / not stated | S19 | — | — | — |

### Qiu MSc 2019
**Document.** Dong Qiu (2019), "Individual Claims Reserving: Using Machine Learning Methods", MSc (Mathematics) thesis, Department of Mathematics and Statistics, Concordia University, Montreal, December 2019 (supervisor José Garrido). MSc thesis.

**Network(s).** A small MLP applied with the "cascading" scheme of Harej et al. (2017). For each development year i = 1…19, a network is trained on the claims whose next-year value is known, and it predicts the missing next column. It is used on individual-claim simulated samples (Samples 3–5 and mock samples c–e) and on NAIC Schedule P data aggregated to company level. It is implemented in R via `mlp()` with SNNS-style arguments plus `normalizeD`/`denormalizeD` (i.e. the RSNNS package, which is not named in the text). Random Forest is also fitted (not an NN).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth / width | 1 hidden layer, 2 neurons (`size = c(2)`) | S1: appears only in the appendix code (RSNNS default would be 5). The text only notes that choosing layers and neurons is "strenuous" | none | none | p.95 (code), p.69, p.76 |
| Activations | logistic hidden and logistic output (`Act_Logistic`) | S3 (these coincide with the RSNNS `mlp()` defaults; the text only reports that Harej et al. chose sigmoid/tanh) | none | none | p.40, p.95 |
| Learning algorithm (optimiser) | Scaled conjugate gradient (`learnFunc = "SCG"`) | S2/S4: the text reviews BA vs SCG from Harej et al. (2017) and says "SCG outperforms BA because it does not need to adjust the learning rate continually" | {standard backprop, SCG} (discussed, not tested) | none | p.44–46, p.95 |
| Learning-function parameters | `learnFuncParams = c(0.2, 0)` | S3 (identical to the RSNNS default for Std_Backpropagation, left unchanged when switching to SCG; not discussed) | none | none | p.95 |
| Epochs / iterations | code: `maxit = 100`; text: "500 epochs are the standard number of times that is used frequently" | S1 / S3 (100 = the RSNNS default); text/code mismatch | none | none (no early stopping, `inputsTest = NULL`) | p.44, p.95 |
| Weight initialisation | `Randomize_Weights` in [−0.3, 0.3] | S3 (RSNNS default) | none | none | p.95 |
| Batch / pattern order | `shufflePatterns = TRUE` (batch size not stated) | S3 | — | — | p.95 |
| Regularisation / pruning | none (`pruneFunc = NULL`) | S3 | — | — | p.95 |
| Random seed | `set.seed(101)` once before the cascade loop | S1 | — | — | p.94 |
| Ensembles / repetitions | none | S19 | — | — | — |

### Jin MSc 2021
**Document.** Fan Fan Jin (2021), "Using decision tree ensemble methods for the estimation of individual claims reserving", Master Thesis Quantitative Finance, Erasmus School of Economics, Erasmus University Rotterdam, June 29, 2021 (academic supervisor A.A. Naghi; external supervisor I.S. Nonneman). MSc thesis.

**Network(s).** NONE. The thesis does not fit a neural network; it uses XGBoost, Random Forest and Extra Trees for RBNS reserves on Gabrielli–Wüthrich simulated data. NNs are mentioned only in the literature review, in the description of the simulation machine (which is itself NN-based), and in future work.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Mayr MSc 2025
**Document.** Elena Mayr (2025), "Development and Optimization of Reserving Models in Actuarial Science: A Python-Based Approach", Master thesis, Institute of Statistics and Mathematical Methods in Economics, Vienna University of Technology, January 25, 2025 (supervisor Stefan Gerhold; Allianz data). MSc thesis.

**Network(s).** NONE. The thesis does not fit a neural network; it confirms that no NN is used. The word "neural" does not occur in the text. The "NN" hits refer to (reverse) nearest-neighbour outlier detection. The candidate models are all Chain-Ladder variants (volume/periods, outlier exclusion, tail, inflation, paid/incurred weighting) built with the Python `chainladder` package.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

## A.7 Guo (2026), Lindholm et al. (2020) and reports

### Guo 2026
**Document.** Qiheng Guo (2026), "Hyperparameters over Architecture: A Controlled Comparison of Neural Networks for Aggregate Loss Reserving", *Risks* 2026, 14, 162 (MDPI), https://doi.org/10.3390/risks14070162. Received 6 May 2026, revised 23 June 2026, accepted 6 July 2026, published 14 July 2026. Journal version (open access). PDF page n = journal page "n of 26".

**Network(s).** (i) GRU Baseline: a re-implementation of Kuo's (2019) DeepTriangle, i.e. a GRU encoder–decoder with a company-code embedding and two dense output heads (paid, case reserve), trained jointly across companies on NAIC Schedule P WC (234 companies) and PPA (284 companies); (ii) GRU + single-head self-attention (masked); (iii) the same without padding masks (ablation). PyTorch.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Architecture family (GRU vs GRU+attention, masked/unmasked) | GRU Baseline recommended | S18/S4: controlled comparison of 3 fixed architectures at one fixed HP configuration over 50 seeds. Welch t-tests with Bonferroni correction and Cohen's d. Attention variants never tuned | 3 architectures; plus 7 further attention variants (multi-head, temperature annealing, identity init of W_Q, W_K; 140 runs) | V5: test MAPE (CY-2011 diagonal) distributions over seeds | 2, 12–13, 15–17, 20 |
| Encoder depth / structure | 1-layer GRU encoder + 1 GRU decoder layer ("single-layer GRU encoder") | S2 (implicit): "an implementation of the Kuo (2019) DeepTriangle". No justification for depth. Not varied in Phase 2 | not searched | VX | 2, 10 |
| GRU hidden units d | Phase 1: 128 (encoder and decoder). Phase 2 winners: WC Config 99 = 256; PPA Config 48 = 128 | Phase 1: S1/S2 (fixed; attributed only generally to Kuo). Phase 2: S7 random search, then top-20 multi-seed re-evaluation (S10-like; fidelity = number of seeds) | {64, 128, 256}, uniform | V5: single-seed test MAPE (screening), then 6-seed mean test MAPE (top 20) | 7, 10, 15, 17, 23 (table image) |
| Dense-head units | Phase 1: 64 (one dense layer per head + linear projection). Phase 2 winners' value: not stated (not reported in Table 4 / Table A1) | Phase 1: S1. Phase 2: S7 → top-20 re-evaluation | {32, 64, 128}, uniform | V5 as above | 10, 15, 17 |
| Activations | ReLU in dense heads; ReLU on output "to enforce non-negativity"; GRU sigmoid/tanh gates | S1 (design choice; output ReLU justified by the non-negativity constraint) | not searched | n/a | 10 |
| Company embedding dimension d_e | 50 | S5 + S2 + S4: start from the Guo & Berkhahn "\|G\| − 1 rule" (\|G\| = 434), lowered to 50 "to match the scale used in Kuo (2019)" and to stay well below the cardinality "which helped prevent overfitting". Not varied in Phase 2 | not searched | VX | 9–10, 7 (Table 1) |
| Attention heads / d_k | 1 head; d_k = d = 128 | S4: single head "to minimize parameter overhead" for 9-step sequences. Multi-head tried afterwards (S18), no improvement. Number of heads tried: not stated | not stated (multi-head among 7 variants) | V5: "convergence" (collapse rate) on test MAPE | 11, 20 |
| Residual connection + LayerNorm (attention variants) | used | S1/S3-like: described as "two standard stabilizers" | not searched | n/a | 5, 11 |
| Padding mask (attention variants) | masked (recommended as "methodologically correct") | S18: masked vs unmasked ablation | {masked, unmasked} | V5: test MAPE, collapse rate | 2, 12, 15–16 |
| Optimiser | Adam with AMSGrad | S1: no justification given | not searched | n/a | 12 |
| Learning rate | Phase 1: 5 × 10⁻⁴. Phase 2 winners: WC 1.07 × 10⁻⁴ (Config 99); PPA 4.76 × 10⁻³ (Config 48) | Phase 1: S1. Phase 2: S7 (log-uniform) → top-20 re-evaluation with 5 extra seeds. Importance ranked by RF surrogate (S18) | log-uniform on [10⁻⁴, 5 × 10⁻³] | V5: single-seed test MAPE, then 6-seed mean test MAPE | 12, 15, 17, 23 (table image) |
| Batch size | Phase 1: 512 ("our default 512"). Phase 2 winners' value: not stated. Kuo's 2250 tried in the ensemble replication (worse) | Phase 1: S1. Phase 2: S7 → top-20. A.4: S18 (512 vs 2250) | {256, 512, 1024}, uniform | V5 | 12, 15, 24 |
| Max epochs | Phase 1: 1000. Phase 2 winners' value: not stated | Phase 1: S1. Phase 2: S7 | {500, 1000}, uniform | V5 | 12, 15 |
| Early stopping | patience 200 epochs, min improvement δ = 0.001, monitoring validation loss | S12 (settings S1). Patience/δ not searched | not searched | V2: validation masked MSE on calendar years 2009–2010 (train ≤ 2008) | 8, 12 |
| Dropout rate | Phase 1: 0.10 everywhere (GRU input and recurrent dropout, attention-weight dropout, between head dense layers). Phase 2 winners: WC 0.015; PPA 0.138 | Phase 1: S1. Phase 2: S7 (log-uniform) → top-20 re-evaluation | log-uniform on [0.01, 0.30] | V5 | 12, 15, 17, 23 (table image) |
| Weight initialisation | not stated (initial GRU hidden state = 0; identity init of W_Q, W_K tried as an attention variant) | S19 for the scheme (PyTorch default presumably, but not stated) | n/a | n/a | 10, 20 |
| Random seed | 50 seeds per architecture × LOB (Phase 1); 1 seed per config (screening); +5 seeds for top 20 (validation); 10 seeds per rolling window; 20-model ensemble in Kuo replication | S15/S18: distribution over seeds reported (mean ± sd), not a selected seed. Recommends ≥10 seeds for architecture selection, 50 for publication | n/a | n/a | 12, 13, 15, 21, 24–25 |
| Ensemble size | 20 models (Kuo-replication check only; §6.2 says "10–20") | S2: "mirroring Kuo's ensemble protocol". Not used for the main results | not searched | n/a | 21, 24 |
| (Out of scope) loss weights | masked MSE, paid and case-reserve terms each weighted ½ | fixed | – | – | 12 |

### Lindholm et al. 2020
**Document.** Mathias Lindholm, Richard Verrall, Felix Wahl and Henning Zakrisson (2020). "Machine Learning, Regression Models, and Prediction of Claims Reserves". *Casualty Actuarial Society E-Forum*, Summer 2020, Reserving Call Paper, pp. 1–47. E-Forum paper (practitioner forum, call paper), not a refereed journal article.

**Network(s).** Feed-forward NNs in the CANN/"GRW" style of Gabrielli, Richman & Wüthrich [11]. They serve as the regression functions of ODP reserving models: - Model 2 (M2-NN): a payment part X_{i,j,k} | N_{i,j} with log(N) offset, plus a reported-claim-count part N_{i,j}. - Model 3 (M3-NN): the payment part alone. The networks are fitted to data from the Gabrielli–Wüthrich simulation machine (6 LoBs) with R keras. GBMs (R gbm) are fitted alongside them.

*NN only; GBM tuning is summarised in the narrative*

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth / widths | 3 hidden layers: 20, 15, 10 units | S2: "we use the architecture of [11]" (GRW). The authors state they did not tune the NNs | none | VX (none) | 86, 93, 96, 101 (Listing 3) |
| Activation | tanh in hidden layers; exponential (`k_exp`) output | S2 (GRW code) | none | n/a | 101–102 |
| Embeddings / skip (CANN) structure | AY, RepDel, PayDel embeddings, dim 1, **non-trainable**, initialised with the ODP (cross-classified) estimates from the training data. Skip connection adds the CC part to the NN part. log N enters as an input | S2 (GRW "bCCNN") | none | n/a | 81, 101–102 |
| Output-layer initialisation | weights (1, 0,…,0, 1) and bias = ODP intercept, so the network starts at the ccODP fit | S2 (GRW) | none | n/a | 102 (Listing 3) |
| Hidden-layer weight initialisation | not stated (keras default, per code) | S3 (evident from code) / S19 | – | – | 81, 101 |
| Dropout | 0.1 after each hidden layer | S2 (GRW code) | none | n/a | 81, 101 |
| Optimiser | RMSprop | S2 (GRW code). Called with no arguments, so the keras defaults apply (S3) | none | n/a | 102 |
| Learning rate | not stated (keras `optimizer_rmsprop()` default) | S3 (evident from code) | none | n/a | 102 |
| Batch size | not stated (code passes a variable `batch_size`) | S19 | – | – | 102 |
| Epochs | upper limit 10,000. Chosen per LoB and per sub-model (Table 3): payment NN 8,825 / 405 / 225 / 9,895 / 331 / 227; count ("incurred claims") NN 9,950 / 9,704 / 9,357 / 9,946 / 9,751 / 1,371 | S12, with a smoothing variant: minimum of the validation loss after a centred simple moving average (window 100), because dropout makes the validation loss volatile. The cap is S4/S1, set by computing time. Otherwise follows [11] "closely" (S2) | 1 … 10,000 | V1: validation Poisson loss on a random 50/50 split of individual claims by LoB and AY, aggregated to X_{i,j,k}, N_{i,j} | 83, 86–87, 90 (table image checked) |
| Refit on train+validation (NN) | not stated for NN (stated for GBM trees) | – | – | – | 90 |
| Random seed (training) | not stated. Data seed 75 for the main dataset; seeds 1–100 generate 100 new simulated datasets | S19 (training seed) | – | – | 83, 92 |
| (Out of scope) dispersion φ, ϕ | Pearson estimators | not a tuning step | – | – | 104–105 |

### Yeo et al. 2019
**Document.** Nicholas Yeo, Raymond Lai, Min Jyeh Ooi, Jie Yin Liew (December 2019). *Literature Review: Artificial Intelligence and Its Use in Actuarial Work*. Society of Actuaries, Actuarial Innovation & Technology. This is a report: a literature review commissioned by SOA, with a Project Oversight Group. Not peer-reviewed research. PDF page = printed page.

**Network(s).** NONE. The paper does not fit a neural network. It is a narrative literature review of AI across motor pricing, loss reserving, mortality, underwriting and fraud, summarising other papers' NN applications, e.g. Mulquiney 2006, Kuo 2019 DeepTriangle, Hainaut 2018, Richman & Wüthrich 2018.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Baeder et al. 2021
**Document.** Larry Baeder, Peggy Brinkmann, Eric Xu (Milliman, Inc.) (April 2021). *Interpretable Machine Learning for Insurance: An Introduction with Examples*. Society of Actuaries, Innovation and Technology; sponsor: Actuarial Innovation and Technology Steering Committee. This is a report (SOA-funded research report), not peer-reviewed. PDF page = printed page.

**Network(s).** NONE. The paper does not fit a neural network. The case-study model is an XGBoost GBM on SOA 2014–15 Individual Life Experience mortality data, used to illustrate interpretability methods (PDP, ICE, ALE, SHAP, H-statistic). Neural networks are mentioned only generically as another "black box" model class (quote 4).

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Mukesh–Aitha 2021
**Document.** Anumandla Mukesh, Avinash Reddy Aitha (2021). "Insurance Risk Assessment Using Predictive Modeling Techniques". *International Journal of Emerging Research in Engineering and Technology* (Pearl Blue Research Group), Vol. 2, Issue 4, pp. 68–79. ISSN 3050-922X, https://doi.org/10.63282/3050-922X.IJERET-V2I4P108. Labelled "Original Article" (journal version). Printed page = PDF page + 67.

**Network(s).** NONE. The paper does not fit a neural network. It is a narrative survey of logistic regression, GLM, survival models, trees, random forests, GBM/XGBoost, NNs and SVMs, with no empirical results. It gives no procedure for choosing NN hyperparameters. It only states generically that: - dropout "prevents overfitting" (quote 1); - architecture is "challenging" to specify, and deep networks are "especially difficult to tune" (quotes 1–2).

*No network fitted: listed for the selection method it describes (Sections 3–4).*

### Zhai MSc 2024
**Document.** Yilong Zhai (April 2024). *Data Imputation for Loss Reserving*. M.Sc. thesis, Mathematics and Statistics, McMaster University. Supervisors: Dr. Anas Abdallah and Dr. Mathieu Pigeon. Thesis (ix + 104 pp.).

**Network(s).** NONE. The thesis does not fit a neural network; confirmed by searching the full text for "neural" and "network", with zero hits. The models are: - imputation models (decision tree, random forest, linear/logistic regression, GLM); - reserving by Mack and a GLM, on simulated individual-claims data.

*No network fitted: listed for the selection method it describes (Sections 3–4).*

## A.8 Pricing and tabular-benchmark networks

### Ferrario et al. 2020
**Document.** Ferrario, A., Noll, A., Wüthrich, M.V. (2020). "Insights from Inside Neural Networks". Tutorial for the Fachgruppe "Data Science", Swiss Association of Actuaries SAV, "Version of April 23, 2020"; SSRN preprint (abstract 3226852). SSRN working paper / tutorial, not a journal version.

**Network(s).** Fully connected feed-forward Poisson-regression networks (log/exponential output) for French MTPL claim frequency (freMTPL2freq), fitted in R keras: shallow nets (q1 = 10…50) and deep nets with K = 2, 3, 4 hidden layers; plus a blend (average) of 12 bias-regularised K = 3 nets.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth K | Warm-up and Sections 4: K = 1; Sections 5–6 and blend: K = 3; K = 3 "sufficient" | S2 for the warm-up (copied from Noll et al. [22] Section 6); S4 manual comparison of a hand-picked set of architectures, argued with complexity theory (universality theorems, Montúfar bounds, Example 6.2) | K ∈ {1, 2, 3, 4} (Table 11) | V1 used only to early-stop each net (callback on 20% validation split); the comparison *between* architectures is argued on test-set ("out-of-sample", data T) Poisson deviance in Table 11 → V5 | pp. 5–7, 16, 37–46 |
| Width (shallow, q1) | q1 = 20 (warm-up/Sec. 4); conclusion "q1 = 20 or 30" | S2 (q1 = 20 from Noll et al. [22]); S5 rules of thumb: q1 > q0 (counting a categorical feature as dimension 1) and q1 slightly below the CV-optimal number of leaves (33) of a regression tree from Noll et al.; plus inspection of PCA singular values of hidden activations and of over-fitting in loss curves (S4) | q1 ∈ {10, 20, 30, 40, 50} | V9 (singular values of neuron activations, in-sample) + visual over-fitting in training/validation curves; test losses reported (V5) | pp. 5, 7, 42–44 |
| Widths (deep) | (20, 15, 10) used as the working deep net (Secs. 5, 6.3, 6.4); (10, 15, 10) is the single net shown in the final comparison Table 17; all 12 K = 3 nets are blended | S4 manual/judgement ("first hidden layer should be sufficiently large", successive compression); candidate set is a small full grid for K = 3 (q1 ∈ {10, 20}, q2 ∈ {10, 15, 20}, q3 ∈ {10, 20}) but it is used for comparison and blending, not for formal selection | K = 2: q1, q2 ∈ {10, 20}; K = 3: 12 combos above; K = 4: 4 combos (Table 11) | Authors say picking "the best" is "not a sensible thing to do"; (10, 15, 10) chosen for Table 17 without stated reason — it has the lowest test loss in Tables 11/14 → V5 implicit | pp. 41–46, 53, 59 |
| Activation (hidden) | tanh | S2 (Noll et al. set-up) + S4 comparison of tanh / ReLU / hard sigmoid on the (20, 15, 10) net; step function rejected on theory | {tanh, ReLU, hard sigmoid}; step and sigmoid discussed | Test ("out-of-sample") loss and run time/convergence speed, Table 12 (V5); each run early-stopped on validation (V1) | pp. 6–7, 46–48 |
| Activation (output) | exponential | S1/theory: canonical log link, positivity of frequencies | — | — | pp. 6, 18 |
| Optimiser | 'nadam' | S4: one-shot comparison of 7 Keras optimisers at their pre-specified settings (same init, 200 epochs, batch 10,000); 'sgd' not tuned because "too time-consuming" | sgd, adagrad, adadelta, rmsprop, adam, adamax, nadam | In-sample (V6) and test ("out-of-sample", V5) Poisson deviance, Table 5; nadam best on both | pp. 17–20 |
| Learning rate / momentum | Keras pre-specified values (value for nadam not stated; Listing 2 shows sgd defaults lr = 0.01, momentum = 0) | S3 library defaults; S13 adaptive optimiser used instead of tuning the rate | none searched | — | pp. 17–19 |
| Batch size | 10,000 (Table 5); 5,000 in Secs. 5–6; "optimal" ≈ 6,000 | S4 one-dimensional sweep (Table 6: fixed 100 epochs; Table 7: fixed ≈ 90 s run time) + S5 statistical heuristic (eq. 4.5: 2-s.d. precision of µ = 5% for batch 6,000 ≈ ±10%) | 610,212; 122,043; 61,022; 12,205; 6,103; 1,221; 611; 123 | Run time vs test ("out-of-sample") loss (V5) | pp. 23–25 |
| Stratified batches / under-over-sampling | not adopted (factor 2 tried) | S18 exploratory comparison with own R code | stratified vs non-stratified; under/over-sampling factor 2 | In-sample losses (V6), Table 8 | pp. 26–27 |
| Epochs / early stopping | Callback keeps weights with the lowest validation loss; max epochs 1,000 (Listing 5), 2,000 (Table 11), 500 (Tables 12–13); early stop ≈ 150 epochs for (20, 15, 10) | S12 early stopping (Keras `callback_model_checkpoint`, save_best_only); earlier illustration (Fig. 14 lhs) reads "150 to 200 epochs" off the test-loss curve | — | V1: Keras `validation_split = .2` of the learning data D (8:2), Poisson deviance (Keras 'poisson' loss); test set T kept disjoint | pp. 20, 29–31, 41, 44, 47 |
| Weight initialisation | Hidden layers: Keras default "glorot uniform"; output layer: weights 0 and bias log(homogeneous MLE λ) | S3 default + S5/S2 initialise at the homogeneous model (refers to Schelldorfer–Wüthrich [31]) | — | — | pp. 27–29 |
| Random seed | one seed per fit, value not stated (set.seed(seed) in listings) | S1/S19 | 50 seeds studied as sensitivity (Fig. 13) | — | pp. 18, 28, 31 |
| L2 (ridge) penalty η | η = 10−5 on all hidden-layer kernels (not intercepts, not output); **not used later** | S4 "trial and error on a few selected values"; CV rejected as too slow | "a few selected values" (not listed) | Not stated; the displayed evidence (Fig. 15, Table 10) is test loss, which the authors themselves call "not fully sound" → VX/V5 | pp. 31–33 |
| Dropout rate | p = 5% in Listings 7–8; **not used for final models** | S4/S18 comparison of four rates (a small grid); recommend CV but consider it too slow | p ∈ {1%, 2%, 5%, 10%} | Test ("out-of-sample") loss curves and Table 10 (V5), authors concede should use a validation split | pp. 33–35, 48–49 |
| Batch normalisation | not adopted | S18/S4 comparison (tanh and ReLU, with/without dropout 2/5/10%) | with / without normalisation layers | Test loss + run time, Table 13 (V5); each run early-stopped on validation (V1) | pp. 48–49 |
| Ensemble size (blend) | 12 (all K = 3 architectures of Table 11, bias-regularised), averaged on the response scale | S15 blending across architectures instead of selecting one; size = every K = 3 net already fitted (no selection of members) | arithmetic mean on response scale vs mean on canonical (log) scale (latter rejected by Jensen argument) | Test loss reported (Table 15) | pp. 52–54 |

### Spedicato–Richman 2025
**Document.** Spedicato, G.A., Richman, R. (2025). "Comparing Predictive Models for Dependent Risk Pricing." Variance 18 (November), https://doi.org/10.66573/001c.146234 (CAS/SOA-funded research). Journal version.

**Network(s).** (i) Multi-output MLP in Keras-TensorFlow with shared hidden layers and peril-specific branches (Poisson loss for counts, RMSE for severities; embeddings for high-cardinality categoricals; log-exposure branch); (ii) a multi-target transformer (target-specific embeddings, small FFNs with normalisation and dropout, multi-head self-attention with a CLS token, sigmoid outputs). Compared with CatBoost GBTs on three datasets (health HID, Italian MTPL, telematics TLM).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| MLP depth (shared layers) | not stated per dataset ("two or three" shared layers) | S4 expert judgement + S2 literature (Holvoet et al. 2023) + S8 Optuna "layer configurations" | shared layers 1–3 ("explored variations") | not stated (VX); a 10% random validation split exists (V1) but the Optuna objective is not given | p. 11 |
| MLP branch depth (outcome-specific) | "one or two" additional hidden layers | same as above | 1–3 ("similarly for the outcome-specific layers") | VX | p. 11 |
| MLP widths | not stated (Figure 6 example shows Dense layers of output shape 8) | S4 + S2 + S8 (Optuna) | not stated | VX | pp. 11–12 (Fig. 6 from image) |
| MLP activation | "gelu" in hidden layers; output exponential via log-exposure added before exponentiation | S1/S2 fixed by choice ("consistently employed", cites Hendrycks & Gimpel) | — | — | p. 11 |
| Embedding dimension | fourth root of the cardinality; embeddings only if cardinality > 6 (else one-hot) | S5 rule of thumb; threshold 6 "judgmentally chosen" (S4) | — | — | pp. 6, 11 |
| L1 / L2 penalties (intermediate layers) | not stated | S8 Optuna | not stated | VX | p. 11 |
| Dropout, BatchNormalization | used (Fig. 6 shows BatchNormalization in each branch); rates not stated | S4 expert judgement + S2 (Holvoet et al. 2023), possibly within Optuna ("and other parameters") | not stated | VX | pp. 11–12 |
| Optimiser | Adam | S1 (no justification) | — | — | p. 11 |
| Learning rate, batch size | not stated | S19 | — | — | — |
| Epochs / early stopping | early stopping on a 10% validation set; patience not stated for the NNs (GBT: 50-round window) | S12 | — | V1: random 10% validation group (row-level "group" column); metric not stated | p. 10 |
| Transformer sizes (heads, embedding dims, widths), piecewise-linear encodings, dropout | not stated | Encodings "chosen heuristically" (S4/S5); widths/embedding dims "can be adjusted based on data size..." (S4); authors say TRF achieved results "even without hyperparameter tuning" | not stated | VX | pp. 14, 20 |
| Seeds / ensembles | single fit per model implied; no ensemble | S19 (authors recommend averaging runs/ensembling but do not report doing so) | — | — | pp. 6, 9 |
| (Out of scope, not NN) CatBoost | learning_rate 0.01–0.1, depth 2–11, random_strength 0.001–10 (log), l2_leaf_reg 0.001–1 (log), min_data_in_leaf 2–20, boosting_type, bootstrap_type; up to 2,000/5,000 trees with early stopping (50 rounds) | S8 Optuna + S12 | as listed | VX (early stopping on validation) | pp. 10–11 |

### Rügamer et al. 2023
**Document.** Rügamer, D., Pfisterer, F., Bischl, B., Grün, B. (2023/2024). "Mixture of experts distributional regression: implementation using robust estimation with adaptive first-order methods." AStA Advances in Statistical Analysis 108(2): 351–373, https://doi.org/10.1007/s10182-023-00486-8 (published online 15 Nov 2023; EconStor copy of the published version). Journal version.

**Network(s).** Mixture-of-experts distributional regression models written as a (structured, mostly shallow) neural network in TensorFlow (R package mixdistreg): one subnetwork per distribution parameter (fully connected layers "with only one neuron", i.e. linear or spline-basis additive predictors), distribution layers, and a mixture-weight subnetwork; trained by mini-batch first-order optimisers ("NMDR"). Deep subnetworks are possible but "not further discussed".

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Architecture (subnetworks) | one subnetwork per additive predictor; single-neuron dense layers (linear / spline basis) | S1 fixed by model structure (the network *is* the statistical model) | — | — | pp. 9–10 |
| Optimiser | RMSprop default (Sect. 4.2); Adam in Appendix B | S4/S18 small benchmark "to find a good default" (Appendix A) + S1 | Adadelta, Adam, Ranger, RMSprop, SGD, each at LRs {0.01, 0.1} (Adadelta also 1), with/without cyclic LR (21 configs, from Fig. 7 image) | Ranks of RMSE of coefficients and mixture probabilities (vs the true simulated values), test-set PLS, ARI, ACC, averaged over 3 repetitions across 48 simulation settings of Sect. 4.3 → V9 (oracle truth) + V8 (predictive log score on independent test data) | pp. 11, 13, 20–21 |
| Learning rate | 0.001 (RMSprop, Sect. 4.2); 1e-3 (Adam, App. B) | S1 (stated "if not specified otherwise") / S3-like default; LR benchmark in App. A did not include 0.001 | 0.01, 0.1 (1 for Adadelta) in App. A | as above | pp. 13, 20–22 |
| LR schedule | reduce LR on plateau after 150 epochs; cyclic LR (CLR) examined in benchmark | S13 | with/without CLR | as above | pp. 13, 21 |
| Batch size | 32 (Sect. 4.2, App. B); 50 in App. A benchmark | S1 | — | — | pp. 13, 20, 22 |
| Epochs / early stopping | max 10,000 iterations, early stopping patience 250 epochs on a 10% validation split; App. A: max 1,500 epochs | S12 early stopping; patience S1 | — | V1: 10% random validation split (loss = negative log-likelihood, implied) | pp. 13, 20, 22 |
| Initialisation | Xavier/Glorot uniform | S3/S1 | — | — | pp. 11, 13 |
| Restarts (random initialisations) | 1 or 3 | S23 (NEW: best-of-N restarts, selection not averaging); compared as an experimental factor | {1, 3} (EM gets 20) | best restart chosen by in-sample log score (V6) | pp. 13–15 |
| Smoothing penalties λ_l (spline smooths) | all λ_l fixed a priori via a shared df: df = 9 suggested; 10 (normal) and 6 (Poisson) in Sect. 4.4 | S5/S2 heuristic: map λ_l to degrees of freedom (Rügamer et al. 2023b) to avoid tuning; S17 mentioned (Fellner–Schall) but not used | — | none (fixed a priori) | pp. 11, 15 |
| Entropy penalty ξ on mixture weights (regularisation; borderline in-scope) | not fixed; studied | S18 sensitivity over a grid; recommend CV along a grid of ξ (S6 + V3) "in practice" | ξ ∈ {0, 1e-05, 0.001, 0.01, 0.1, 0.3} (Fig. 4 legend, from image); coefficient path 0 to 1 on log scale (Fig. 5) | Test PLS and RMSE vs truth (V8/V9); Fig. 5 "best trade-off" ≈ 1e-02 judged against true probabilities | pp. 12, 17–18 |
| (Out of scope) number of mixture components M | simulation design / M = 6 from Spellman et al. for yeast | S2 | — | — | pp. 13, 18 |

### Gorishniy et al. 2025 TabM
**Document.** Gorishniy, Y., Kotelnikov, A., Babenko, A. (2025). "TabM: Advancing Tabular Deep Learning with Parameter-Efficient Ensembling." Published as a conference paper at ICLR 2025; this file is arXiv:2410.24210v3 (18 Feb 2025). Conference paper (arXiv version of the ICLR paper).

**Network(s).** TabM — an MLP backbone (blocks Dropout(ReLU(Linear))) turned into a parameter-efficient ensemble of k implicit submodels via BatchEnsemble-style adapters (variants TabM, TabM_mini, TabM_packed, with/without piecewise-linear feature embeddings), benchmarked on 46 public tabular datasets against MLP, MLP×k deep ensembles, FT-Transformer, SAINT, T2G-Former, ExcelFormer, TabR, ModernNCA, AutoInt, etc., and GBDTs.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Ensemble size k (TabM) | k = 32 always | S1/S5 "heuristically set", not tuned; S18 post-hoc analysis over k | k ∈ {1, 2, 4, 8, 16, 32, 64, 128} × n ∈ {1, 2, 3} layers × d ∈ {64, 128, 256, 512} in Fig. 7 (from image); dropout 0.1, LR tuned per k, 5 seeds, 17 datasets | Sensitivity reported as mean test improvement over MLP (evaluation, not selection) | pp. 4, 6, 10, 20 |
| Deep-ensemble size (MLP×k, TabM×N) | MLP×32 (k = 32 seeds); TabM†mini×5 | S15; sizes fixed (S1) | — | — | pp. 4–6 |
| Submodel pruning (TabM[G], analysis only) | 8.8 ± 6.6 of 32 kept on average | S15/S16 greedy forward selection of submodels | subsets of the 32 submodels | V1: validation metric of the collective prediction | pp. 9, 20 |
| Depth (# layers) | tuned per dataset (values in repo TOML files) | S8 TPE (Optuna) | TabM/TabM_mini: UniformInt[1, 5]; TabM†: UniformInt[1, 4]; MLP: UniformInt[1, 6]; MLP†/MLP‡: UniformInt[1, 5] | V1 on 37 random-split datasets / V2 on 9 "domain-aware" (e.g. time-aware) splits: validation RMSE (regression), accuracy or ROC-AUC (classification) | pp. 3, 18–19, 21–22 |
| Width | tuned | S8 TPE | UniformInt[64, 1024] (TabM, MLP variants) | as above | pp. 21–22 |
| Activation | ReLU | S1 (fixed in MLP definition) | — | — | p. 4 |
| Dropout rate | tuned | S8 TPE | {0.0, Uniform[0.0, 0.5]} | as above | pp. 21–22 |
| Learning rate | tuned; no LR schedule | S8 TPE; S13 not used ("We do not apply learning rate schedules") | TabM: LogUniform[1e-4, 5e-3]; TabM†: LogUniform[5e-5, 3e-3]; MLP (all variants): LogUniform[3e-5, 1e-3] | as above | pp. 14–15, 18, 21–22 |
| Weight decay | tuned | S8 TPE | {0, LogUniform[1e-4, 1e-1]} | as above | pp. 21–22 |
| Feature-embedding sizes (PLE bins, d_embedding, n_frequencies, frequency scale) | tuned | S8 TPE | e.g. TabM† # PLE bins UniformInt[8, 32]; MLP† d_embedding UniformInt[8, 32], n_bins UniformInt[2, 128]; MLP‡ n_frequencies UniformInt[16, 96], d_embedding UniformInt[16, 32], frequency init scale LogUniform[1e-2, 1e1] | as above | pp. 21–22 |
| Optimiser | AdamW; gradient clipping 1.0 | S2 (setup of Gorishniy et al. 2024) / S1 | — | — | p. 18 |
| Batch size | dataset-specific, predefined (128–1024), same for all DL models | S2 (tables "taken from" Gorishniy et al. 2024; TabReD protocol) | — | — | p. 18 |
| Epochs / early stopping | train until patience = 16 consecutive epochs without validation improvement | S12 | — | V1/V2: validation metric | p. 18 |
| Tuning budget (# TPE iterations) | TabM: 100 on most datasets, 50 on Covertype, Microsoft and TabReD (Table 5); MLP: 100; "typically, 50-100"; 25 on some TabReD datasets (following Rubachev et al. 2024) | S8 budget fixed by fiat / S2 | — | — | pp. 18–19, 21–22 |
| Initialisation | BatchEnsemble adapters normally random ±1; in TabM all multiplicative adapters except the first initialised to 1; TabM† first adapter R ~ N(0, 1) | S4 design choice (ablation TabM_naive vs TabM) | — | Test-based mean relative improvement over MLP (Fig. 2, V5 for design choices) | pp. 4, 6, 14 |
| Seeds | 15 seeds for final evaluation (3 for large-dataset runs; FT-T 1) | S15-like averaging of test metric over seeds (reporting) | — | — | pp. 3, 19 |

### Ye et al. 2025
**Document.** Ye, H.-J., Liu, S.-Y., Cai, H.-R., Zhou, Q.-L., Zhan, D.-C. (2025). "A Closer Look at Deep Learning Methods on Tabular Datasets." arXiv:2407.00956v4 [cs.LG], 7 Nov 2025 (journal-style template with placeholder "Editor: My editor"). arXiv preprint.

**Network(s).** Benchmark (Talent, 300+ datasets) of many deep tabular models — MLP, ResNet, SNN, MLP-PLR, RealMLP, DCNv2, TabCaps, AutoInt, TabTransformer, FT-Transformer, ExcelFormer, TANGOS, SwitchTab, PTaRL, NODE, GrowNet, TabNet, DANets, TabR, ModernNCA (and MNCA-ens), TabM, pretrained TabPFN/TabPFN v2/TabICL and adaptations — against classical and tree methods; plus a four-layer MLP "meta-mapping" h that forecasts validation curves from meta-features.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| All tunable hyperparameters of each non-pretrained method (architecture, regularisation, LR, etc.) | per method–dataset best configuration (not reported in paper) | S8 Optuna (sampler not named in the text; Optuna's default is TPE) with a fixed budget of 100 trials per method–dataset pair; budget 100 adopted "following Gorishniy et al. (2021)" (S2) | "complete search spaces" only in the GitHub configs, not in the paper | V1: random 16% validation split; accuracy (classification) / RMSE (regression) | pp. 14, 40 |
| Number of tuning trials (budget) | 100 | S2 + S18 sensitivity (MLP only) | 50, 100, 150, 200 trials | Average rank of MLP across methods on test results, by dataset-size group (Table 4) — evaluation of budget, not re-selection | p. 40 |
| Epochs / early stopping | early stopping "triggered by the task metric on validation"; patience not stated | S12 | — | V1: validation accuracy / RMSE (same split as HPO) | p. 14 |
| Optimiser | AdamW for all deep methods | S1 | — | — | p. 14 |
| Batch size | 1024 "unless noted otherwise" | S1 | — | — | p. 14 |
| Seeds | 15 seeds after tuning; mean reported | S15-like averaging for evaluation | — | — | pp. 14, 48 |
| Pretrained models (TabPFN v2, TabICL, ...) | public checkpoints, "default inference hyperparameters" | S3 defaults, no per-dataset tuning | — | — | p. 14 |
| High-dimensional Talent-extension datasets | default hyperparameters with aggregated CV | S3 defaults (because of small sample sizes) | — | V3 (cross-validation, aggregated results) | p. 41 |
| Ensembling (TabM, MNCA-ens; CV+ensemble protocol) | TabM/MNCA-ens use internal ensembles; CV+ensemble protocol on Talent-tiny (45 datasets) | S15 (evaluated as alternative protocol) | hold-out vs CV + ensembling | V3 in the CV variant; number of folds not stated | pp. 9, 38–39 |
| Meta-mapping MLP h (analysis tool) | four layers; input 24 (5 early validation points + 19 meta-features); output 4 curve parameters | S1 (widths, optimiser, epochs not stated) | — | Trained on 80% of validation curves, tested on 20% (no dataset overlap); MAE / OVD | pp. 30–31, 50 |
| MLP runs used for curve forecasting | "default hyperparameters" (Sect. 6.2) vs "best hyperparameters ... predetermined" (Sect. 6.1) | S3 (defaults) — see flag | — | — | p. 30 |

### Usman PhD 2024
**Document.** Usman, F. (2024). "Advancing Insurance Intelligence: Integrated Statistical and Machine Learning Models in Loss Reserving and Auto Insurance Claim Prediction using Telematics Data." PhD thesis, Department of Mathematics & Statistics, The University of Sydney (supervisor A/Prof. Jennifer S. K. Chan). Thesis.

**Network(s).** Chapter 4 only: a two-group Poisson-mixture deep feed-forward network ("PM DLNN") in Keras/TensorFlow for telematics claim counts (N = 14,157 drivers, 45 driving-variable inputs), 5 hidden layers (45, 30, 15, 10, 5) with BatchNormalization and Dropout, two constrained output neurons (safe/risky annual claim rates), PM negative log-likelihood loss. Chapter 2 (Bayesian trapezoidal loss-reserve models in Stan) and Chapter 3 (lasso/adaptive-lasso/elastic-net two-stage Poisson, Poisson-mixture and ZIP regressions) fit no neural network; their tuning is noted in one line in the narrative.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth L | 5 hidden layers | S5 literature rule ("L is suggested to be 3 to 5" for many features) + S4 manual; BO is described as tuning L but its search space (4.24) and code keep L fixed | — | none stated for L | pp. 142–143, 155, 158 |
| Widths m | (45, 30, 15, 10, 5) | S5 rules of thumb: m1 = m0 = 45, then alternately ×2/3 and ×1/2 (Table 4.1), citing literature rules (m1 &lt; 2M, m1 = (2/3)M, m1 = M/2, 0.7M–0.9M, ...), and total parameters M = 4,322 must be &lt; training size NT (S5) | — | none | pp. 143, 155–156, 158 |
| Activations | hidden layers 1–4 linear, layer 5 ELU; outputs tanh (safe) and softplus (risky) with scaling/capping constraints | S1/S4 by fiat ("to ensure the output neurons are non-negative"); output-range variants (shift 0.4ā vs 0.5ā) chosen "with MSE" (S4) | ReLU, ELU, LeakyReLU (ξ = 0.01), tanh, softplus reviewed | output-shift choice: MSE (data not stated) | pp. 143–146, 158, 160–161 |
| Optimiser | Manual: AdaDelta (fixed at start); BO-selected: SGD | Manual: S1/S4 ("due to its efficiency"); BO: S8 (GP-based `bayes_opt`) | {SGD, Adam, AdaDelta, AdaGrad} | BO: V3 5-fold CV on the training split, custom PM MSE | pp. 158–159, 166, 174–176 |
| Learning rate ζ | Manual: 0.0097 or 0.01; BO models 0.0096–0.0099 | Manual S4; BO S8 over a very narrow range | Manual {0.0097, 0.01}; BO [0.0097, 0.01]; DP-BO [0.0095, 0.01] | as above | pp. 158–159, 164, 166 |
| Batch size B | Manual 110 (DP-MAN 120); BO models 93–120 | Manual S4 ("close to 128"); BO S8 | Manual {100, 110}; BO [75, 120]; DP-BO [90, 150] | as above | pp. 156, 158–159, 164, 166 |
| Epochs E | Manual 400 (DP-MAN 300, ICO 80); BO models 232–396 | Manual S1/S4 fixed; BO S8 treats E as a tuned hyperparameter; plus S12 early stopping | BO [250, 450]; DP-BO [200, 350] | Early stopping monitors val_pmmse on the 20% held-out split (code) → V5 | pp. 158–159, 164, 166, 178 |
| Early-stopping patience P / start epoch | P = 1 (DP-MAN; code patience = 1); "activated only after the 50th epoch" (text) | S4 "experiments ... to identify the optimal patience value" + S12 | P ∈ {1, 2, 3} | not stated for P; stopping signal = val_pmmse on held-out 20% (V5) | pp. 155, 158, 163, 176, 178 |
| Dropout rate p | Text/Table 4.2: 0.20 (MAN), 0.10–0.20 (BO); code listings use 0.05; Table 4.1 shows 0.20 | S4 manual (also listed in BO space but not in BO code) | {0.05, 0.10, 0.20} | not stated | pp. 143, 158–159, 166, 175, 177 |
| Batch normalisation | after hidden layer 1 | S2/S1 ("BatchN is suggested to apply to layer 1") | — | — | pp. 153, 160 |
| L1/L2 penalties | described, not used in the reported networks | S19 | — | — | p. 154 |
| Weight initialisation | not stated (Keras default implied by code) | S19/S3 | — | — | — |
| Seeds / repeats | 10 repeats × 2–3 trials, each with a new seed; best single run kept (no averaging) | NEW S23: best-of-N random restarts selected by a score | seeds drawn by `np.random.randint(40, 50)` | PM MSE (4.9) + visual convergence of epoch history; code computes PM MSE on predictions for the full data XX (train + held-out) → V5/V6 | pp. 162, 166, 178–181 |
| (Out of scope) mixture prior π | MAN-0.88, BO-0.89 selected; ICO π̂ = 0.92; DP π̄ = 0.93 | S6 grid, tuned in the same loop as the repeats; ICO and dynamic-π alternatives | text {0.88, …, 0.92}; Table 4.2 0.88–0.93 | PM MSE (V5/V6 as above) | pp. 162–166 |

## A.9 Generative models and methodological papers

### Côté et al. 2025
**Document.** Côté, M.-P., Hartman, B., Mercier, O., Meyers, J., Cummings, J. and Harmon, E. (2025). "Synthesizing Property & Casualty Ratemaking Datasets using Generative Adversarial Networks." *Variance* 18 (September). https://doi.org/10.66573/001c.144283. Journal version (submitted 14 Aug 2020, accepted 21 Jan 2022, published 29 Sep 2025).

**Network(s).** Three GANs trained on the French MTPL data (412,748 policies): (i) MC-WGAN-GP (multicategorical Wasserstein GAN with gradient penalty; FC+BN+ReLU generator, FC+LeakyReLU critic); (ii) CTGAN (Kuo's R wrapper of Xu et al. 2019); (iii) MNCDP-GAN (autoencoder + WGAN, optionally trained with DP-SGD). The GANs are the object of study; downstream models (Poisson GLM, random forests) are not NNs.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| MC-WGAN-GP: generator hidden layers / widths | Figure 2 shows hidden layers "FC+BN+ReLU" of width 100 ("…" between two such layers, so the exact count is not given in the text); noise dimension 10 | S2 for output head (one dense+softmax per categorical variable "as in Camino, Hammerschmidt, and State (2018)") plus one linear dense layer for continuous variables; hidden sizes S1 (shown in figure only) | not stated | VX: not stated | p. 3-4 (Fig. 2, from figure image p. 4) |
| MC-WGAN-GP: critic layers / widths / activations | FC+LeakyReLU 256, FC+LeakyReLU 128, FC 1 (inputs X + minibatch column average) | S1 (figure only) | not stated | VX | p. 4 (Fig. 2, from figure image) |
| MC-WGAN-GP: learning rate | 0.01 | S7: random search | {0.001, 0.005, 0.01} (chosen value is the largest candidate, i.e. edge of the space) | VX: selection metric not stated | p. 15 (Table A.1, App. A) |
| MC-WGAN-GP: generator batch-norm decay (gen_bn_decay) | 0.90 | S7: random search | {0, 0.10, 0.25, 0.45, 0.50, 0.90} (chosen value at edge of space) | VX | p. 15 (Table A.1) |
| MC-WGAN-GP: discriminator batch-norm decay (disc_bn_decay) | not stated (listed as tuned in App. A text, absent from Table A.1) | S7 (per text) | not stated | VX | p. 15 |
| MC-WGAN-GP: generator L2 regularisation (gen_L2_reg) | 0 | S7: random search | {0, 0.00001, 0.0001, 0.001, 0.01} | VX | p. 15 (Table A.1) |
| MC-WGAN-GP: discriminator L2 regularisation (disc_L2_reg) | 0 | S7: random search | {0, 0.00001, 0.0001, 0.001, 0.01} | VX | p. 15 (Table A.1) |
| MC-WGAN-GP: batch size, epochs/iterations, optimiser, number of random-search trials | not stated | S19 | not stated | VX | – |
| CTGAN: generator | two FC+BN+ReLU layers of width 256 (residual-style concatenation of inputs shown in figure), Gumbel-softmax outputs | S2: Kuo (2019) code reused ("the overall code remained the same"), which wraps Xu et al. (2019) | none | none (no tuning described) | p. 4-5 (Fig. 4 from figure image p. 5) |
| CTGAN: critic | two FC+LeakyReLU+dropout layers of width 256, FC 1; PacGAN with 10 samples per pac | S2: Kuo (2019)/Xu et al. (2019) | none | none | p. 4-5 |
| CTGAN: dropout rate, learning rate, batch size, epochs | not stated | S19 (implicitly Kuo/CTGAN code defaults, not stated as such) | – | – | – |
| MNCDP-GAN: network "basic architecture (the number and sequence of layers)" | as in Tantipongpipat et al. (2019); layer sizes vary with input size and latent dims | S2: Tantipongpipat et al. (2019) | not searched | – | p. 15 (App. B.2) |
| MNCDP-GAN: activations | LeakyReLU, negative slope 0.2 (slope from page image); linear output layer of discriminator | S2 (linear output + RMSProp "as recommended" by Arjovsky et al. 2017); LeakyReLU S1 | – | – | p. 15 (App. B.2) |
| MNCDP-GAN: normalisation | layer normalisation (not batch norm) in generator | S2: "following the recommendations of Gulrajani et al. (2017)" | – | – | p. 16 (App. B.2) |
| MNCDP-GAN AE: compression (latent) dimension | 25 (baseline, all_cat), 50 (bin) | S7: several successive random searches over a grid, the space narrowed each time (coarse-to-fine) | grid not stated | V1: lowest final validation loss (binary cross-entropy), random 1/3 validation split | p. 16-17 (App. B.3, Table B.1) |
| MNCDP-GAN AE: minibatch size | 64 (baseline, all_cat), 128 (bin) | S7 as above | not stated | V1: lowest final validation BCE loss | p. 16-17 |
| MNCDP-GAN AE: learning rate | 0.01 (all configs), reduced ×0.2 on validation-loss plateau (tolerance 1e-4, patience 1,000 iterations, floor = 1/100 of initial rate) | S7 for initial value; S13: ReduceLROnPlateau-style schedule | not stated | V1: validation loss (for both search and plateau schedule) | p. 16-17 |
| MNCDP-GAN AE: Adam β1, β2, weight-decay L2 | 0.9, 0.999, 0 | S4 then S3: tested in "first experiments", no material effect, so left at "usual default values" | not stated | VX (qualitative "did not materially affect") | p. 16 |
| MNCDP-GAN AE: training iterations | "over 20,000" | S4: "determined to be sufficient for convergence" (criterion not stated) | – | VX | p. 15 |
| MNCDP-GAN GAN: optimiser | RMSProp (Adam tested as alternative, "almost the same results") | S2 (Arjovsky et al. 2017 recommendation) + S18 check | {RMSProp, Adam} | V9: final-results comparison, same seed | p. 15-16 |
| MNCDP-GAN GAN: learning rate | 4.5e-5 (baseline, all_cat), 3.9e-5 (bin) (from table image p. 17; values garbled in text) | S7 staged random search + S10-like truncated screening (100,000 iterations per combination) + visual loss-curve heuristic (NEW code S26: "visual inspection of adversarial loss curves") | not stated | V9: shape of discriminator/generator training-loss curves; then, for "a couple" of finalists trained 2 million iterations, fidelity of synthetic data (univariate distributions vs real; random-forest predictions of ClaimNb on generated vs real samples) | p. 16-17 |
| MNCDP-GAN GAN: minibatch size | 128 | as above | not stated | as above | p. 16-17 |
| MNCDP-GAN GAN: generator latent dimension | 25, 25, 30 | as above | not stated | as above | p. 16-17 |
| MNCDP-GAN GAN: discriminator updates per generator update | 10, 10, 5 | as above (Arjovsky et al. recommend training discriminator more often) | not stated | as above | p. 15-17 |
| MNCDP-GAN GAN: RMSProp α, weight-decay L2 | 0.99, 0 | S4 then S3: "did not materially affect the results, so they were left at 0 and 0.99" | not stated | VX | p. 16 |
| MNCDP-GAN GAN: training iterations | 2 million | S4: "empirically determined based on obtained results" | – | VX | p. 15 |
| MNCDP-GAN: weight initialisation | default PyTorch initialisation (Kaiming uniform tested, "did not improve the results") | S3 + S4 check | {PyTorch default, Kaiming uniform} | VX ("results") | p. 16 |
| MNCDP-GAN: gradient clipping (WGAN clip value; DP L2 norm clips) | clip 0.01; L2 norm clip 0.022 (AE), 0.027 (GAN) | S2: norm clips computed "as recommended by Abadi et al. (2016)" | – | – | p. 16-17 |
| MNCDP-GAN: random seed | best of ≥3 runs of the chosen combination | NEW code S23: "best-of-seeds selection" (re-train with ≥2 more seeds, keep the best run) | ≥3 seeds | V9: same fidelity criteria ("gave the best results") | p. 16 |
| MNCDP-GAN (DP versions, ε = 100k, 10k, 5): all hyperparameters | same as non-private configuration | NEW code S24: "transferred from a related (non-private) configuration" | – | tuning done with ε = ∞ only | p. 16 |
| MNCDP-GAN all_cat configuration: all hyperparameters | same as baseline | S24-type transfer: "using the values of the first on the second gave good results" | – | VX | p. 16 |

### Xu et al. 2019 CTGAN
**Document.** Xu, L., Skoularidou, M., Cuesta-Infante, A. and Veeramachaneni, K. (2019). "Modeling Tabular Data using Conditional GAN." 33rd Conference on Neural Information Processing Systems (NeurIPS 2019), Vancouver. The file is the arXiv preprint arXiv:1907.00503v2 [cs.LG], 28 Oct 2019, with supplementary material (dataset details, Tables 4-6, Algorithm 1) appended.

**Network(s).** CTGAN (conditional generator + PacGAN critic, WGAN-GP loss) and TVAE (a tabular VAE: encoder and decoder MLPs). Both are benchmarked against MedGAN, VeeGAN and TableGAN (NN baselines) and CLBN, PrivBN (Bayesian networks) on 7 simulated and 8 real datasets. Downstream "machine learning efficacy" evaluators include MLPs (MLP(50), MLP(100)).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| CTGAN network type | fully connected (no conv) | S4 (design rationale: "columns in a row do not have local structure") | – | – | p. 6 (§4.4) |
| CTGAN generator depth / width | 2 hidden FC layers, 256 units each, with residual-style concatenation (h1 = h0 ⊕ …, h2 = h1 ⊕ …) | S1: stated without tuning | none reported | VX | p. 6 (§4.4) |
| CTGAN generator activations / normalisation | BN + ReLU in hidden layers; outputs tanh (α) and Gumbel-softmax with τ = 0.2 (β, d) | S1 | – | – | p. 6 (§4.4; τ = 0.2 from page image) |
| CTGAN critic depth / width | 2 hidden FC layers of 256, output FC 256→1 | S1 | – | – | p. 6 |
| CTGAN critic activation | leaky ReLU, leaky ratio 0.2 | S1 | – | – | p. 6 |
| CTGAN critic dropout rate | dropout on each hidden layer; rate not stated | S19 (rate) | – | – | p. 6 |
| PacGAN pac size | 10 | S2: PacGAN framework [17] (Lin et al.) "to prevent mode collapse"; value S1 | ablation: with/without PacGAN (see below) | test-set ML-efficacy (ablation, after the fact) | p. 6, 9 |
| Loss / GP weight | WGAN-GP loss [11]; gradient-penalty weight 10 in Algorithm 1 | S2: Gulrajani et al. [11] | ablation of loss type | – | p. 6, 15 |
| Optimiser, learning rate (CTGAN) | Adam, 2·10^-4 (0.0002 in Algorithm 1) | S1 | none reported | VX | p. 6, 15 |
| Critic steps per generator step | 1 (Algorithm 1 alternates one critic update and one generator update) | S1 (from algorithm) | – | – | p. 15 (Algorithm 1, page image) |
| Noise dimension \|z\| | not stated | S19 | – | – | – |
| TVAE architecture | encoder and decoder each 2 hidden layers of 128 ReLU units; latent dim 128 (FC128→128 for µ, σ) | S1 | – | – | p. 6 (§4.5) |
| TVAE optimiser / learning rate | Adam, 1e-3 | S1 | – | – | p. 7 |
| Batch size (all methods) | 500 | S1: one value for every model and dataset | – | – | p. 8 (§5.3) |
| Epochs (all methods) | 300 (each epoch N/batch_size steps) | S1: fixed for every model and dataset; no early stopping | – | – | p. 8 (§5.3) |
| Seed / repetitions | not stated | S19 | – | – | – |
| Evaluation MLPs (downstream classifiers/regressors) | MLP(50) on adult; MLP(100) elsewhere | S4: chosen because they "achieve reasonable performance on each data" (details in supplementary material/benchmark code) | not stated | V9 (performance of real-data-trained evaluator, Table 5) | p. 7, 12-13 |

### Kuo 2020 generative
**Document.** Kuo, K. (2020). "Generative Synthesis of Insurance Datasets." A Preprint, arXiv:1912.02423v2 [stat.AP], 6 Aug 2020 (dated August 7, 2020). arXiv preprint.

**Network(s).** CTGAN (Xu et al. 2019), trained through the author's R interface (`ctgan` package), once per fold of 10-fold cross-validation on (i) French TPL frequency data and (ii) SOA 2014 post-level-term shock-lapse data. Downstream predictive models are Poisson GLMs (not NNs).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| All CTGAN architecture / optimisation hyperparameters (layers, widths, activations, dropout, learning rate, pac size, epochs) | "default hyperparameters specified in the CTGAN paper" (values not restated) | S2 + S3: adopted from Xu et al. (2019) / CTGAN defaults; explicitly no tuning | none | none ("we do not perform hyperparameter tuning of CTGAN") | p. 4, 7 |
| Minibatch size (TPL example) | 10,000 | S1 / S4: stated without justification; departs from the CTGAN paper's 500 | none | VX | p. 4 (§3.2) |
| Minibatch size (shock-lapse example) | not stated | S19 | – | – | – |
| Number of epochs / training iterations | not stated (TPL training time "approximately 10 minutes") | S19 (implied CTGAN default) | – | – | p. 4 |
| Training-set size per fold (TPL) | random subsample of 100,000 rows of the analysis set | S4: judgement, "to constrain training time", "reasonable for users to experiment with" | – | V9: wall-clock time | p. 4 (§3.2) |
| Seed | not stated | S19 | – | – | – |

### Gueye et al. 2023
**Document.** Gueye, M., Attabi, Y. and Dumas, M. (2023). "Row Conditional-TGAN for Generating Synthetic Relational Databases." ICASSP 2023 – IEEE International Conference on Acoustics, Speech and Signal Processing, DOI 10.1109/ICASSP49357.2023.10096001. Conference paper (4 pages + references), IEEE Xplore version.

**Network(s).** RC-TGAN1 (CTGAN whose generator is conditioned on parent-row features) and RC-TGAN2 (also conditioned on grandparent-row features), one GAN per table, on eight public relational databases; baseline SDV (Gaussian-copula, not an NN).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| All RC-TGAN hyperparameters (layers, widths, activations, learning rate, batch size, epochs, dropout, pac size) | not stated | "hyperparamater tuning … carried out separately for each single table"; method not stated (S19 for method; per-table re-tuning noted) | not stated | VX: not stated | p. 4 (§4.2) |
| Base architecture | CTGAN source code as packaged in the SDV library, modified to take parent (and grandparent) row features as generator input | S2/S3: CTGAN (Xu et al.) implementation in SDV | – | – | p. 4 (§4.2) |
| Seeds / repetitions | not stated | S19 | – | – | – |

### Fang et al. 2022
**Document.** Fang, K., Mugunthan, V., Ramkumar, V. and Kagal, L. (2022). "Overcoming Challenges of Synthetic Data Generation." 2022 IEEE International Conference on Big Data (Big Data), pp. 262-270, DOI 10.1109/BigData55660.2022.10020479. Conference paper (IEEE Xplore version).

**Network(s).** UniformGAN, a DCGAN/TableGAN-style convolutional GAN (CNN discriminator, deconvolutional generator, SELU activations, Dense-Sparse-Dense training, uniform-loss term, DP noise on the discriminator), compared with CTGAN and TableGAN on five datasets (Adult, Credit, Covertype, Kaggle Fire, Kaggle Hazards).

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Architecture family | CNN discriminator on input reshaped to "closest-sized square matrices"; generator of "multiple deconvolutional layers" + final linear layer + tanh; strided convolution, batch normalisation | S2: adopted from DCGAN [17] and TableGAN | – | – | p. 3-5 (§IV, IV-B, IV-C) |
| Number of layers / filters / kernel sizes | not stated ("Each layer doubles the amount of filters") | S19 (counts); S5-like rule (filters double as spatial size halves, DCGAN convention) | – | – | p. 4 (§IV-B) |
| Activation function | SELU replacing all ReLU/LeakyReLU; sigmoid output for BCE loss (removed for Wasserstein); tanh generator output | S2 + S4: justified by the SELU paper [11] ("significantly outperform all competing" FNN methods) | ReLU/LeakyReLU (not compared empirically) | VX | p. 3, 5 |
| Dropout | used between each step in discriminator; rate not stated | S19 (rate) | – | – | p. 5 (§IV-B) |
| Batch normalisation | used between layers in discriminator and generator | S2 (DCGAN; Ioffe & Szegedy [8]) | – | – | p. 3, 5 |
| Pruning / sparsity (Dense-Sparse-Dense training) | DSD applied; "a minority selection of the smallest weights" zeroed in sparse phase; sparsity ratio and phase lengths not stated | S2: DSD of Han et al. [7] (S16-type pruning used as regulariser) | – | – | p. 3 (§IV) |
| Batch size | 200 (mentioned only as the basis for choosing N) | S1 (with the remark that it "should not be small" because the uniform loss uses the whole batch) | – | – | p. 5 (§IV-E) |
| Loss choice | BCE with one-sided label smoothing [19] (label 0.9 in formula) or Wasserstein loss [1] | S2 (Salimans et al.; Arjovsky et al.) | {BCE+label smoothing, Wasserstein} | VX: which one produced the reported results not stated | p. 5 (§IV-E) |
| Optimiser, learning rate, epochs, weight init, seed | not stated | S19 | – | – | – |
| DP noise level ε | 0.01, 0.1, 1 (all reported) | S18: sensitivity sweep, not selection | {0.01, 0.1, 1} | – | p. 6 (§V-B) |
| Repetitions | 3 runs per experiment, averaged | S15-like averaging over runs (reporting only) | – | – | p. 6 |
| Baseline CTGAN / TableGAN settings | not stated | S19 | – | – | – |

### Swallow MSc 2023
**Document.** Swallow, R. (2023). "An Application of Generative Adversarial Networks to One-Dimensional Value-at-Risk." Minor Dissertation (FTX5052W), University of Cape Town, dated December 12, 2023; supervisor Dr Obeid Mahomed. Master's minor dissertation (thesis).

**Network(s).** Three GAN loss variants (non-saturating NS GAN, WGAN with weight clipping, MMD GAN with encoder/decoder "discriminator"), all with fully-connected generator and discriminator (PyTorch). They are trained to sample from three 1D targets (N(23,1), a two-component GMM, and a three-component GMM fitted to FTSE/JSE Top40 returns), and the generated samples are used for historical VaR with backtesting.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| GAN loss variant | NS, WGAN, MMD (MM GAN and WGAN-GP described but not implemented) | S2/S4: MM GAN dropped because NS "is the recommended variant" | {MM, NS, WGAN, WGAN-GP, MMD} described | – | p. 28 (§3.1.1) |
| Number of hidden layers | final architectures G1: 4 hidden (n,128,248,496,992,1); G2: 3 hidden (n,128,128,128,1); D1: 3 hidden (1,128,128,128,1) (per Table 3/4) | S4: manual "brute force" trial and error, guided by prior work [4] Fiechtner and [26] Zaheer & Póczos (S2) | 2, 3 and 4 hidden layers | V9 (+V5 overlap): "best-tuned models (based on a combination of result metrics)", i.e. KS/CVM two-sample tests, Wasserstein distance and moment scores of 10,000 generated draws vs 10,000 draws from the known target Px; described as "training set results" | p. 29 (§3.1.3, Tables 3-4 from table image), p. 37 |
| Neurons per layer | as above; also G3/D2 (·,7,13,7,1); MMD encoder (1,11,29), decoder (29,11,1) from [26] | S4 + S2 ([4], [26]) | "A huge variety of unit numbers were tested" (not listed) | as above | p. 29 |
| Chosen architecture per target | Normal: NS G2/D1, WGAN G2/D1, MMD G1/D1; 2-GMM: G2/D1 for all three; 3-GMM: NS G2/D1, WGAN G2/D1, MMD G1/D1 | S4 per variant × target (re-tuned per target distribution) | G1-G3 × D1-D2 | as above | p. 37 (Table 6), p. 43 (Table 11), p. 47 (Table 17), from table images |
| Activation function | ReLU (G1), LeakyReLU (G2, D1, D2), ELU (G3, encoder, decoder); appendix code: LeakyReLU slope 0.2 in discriminators, 0.01 in "GeneratorLeak", ELU α = 1.0 | S4 over candidates suggested by [4] (LeakyReLU) and [26] (ELU) | {ReLU, LeakyReLU, ELU} | as above | p. 29-31 (§3.1.4), p. 62-64 (App. A.2 from page images) |
| Latent dimension (called "batch size of the latent vector" n) | Normal: NS 20, WGAN 20, MMD 1; 2-GMM: NS 10, WGAN 20, MMD 20; 3-GMM: NS 20, WGAN 20, MMD 10 | S4 | n ∈ {1, 10, 20} | as above | p. 28 (§3.1.2), Tables 6, 11, 17 |
| Latent distribution | N(0,1) or U(−1,1), chosen per variant/target (e.g., 2-GMM WGAN: U(−1,1)) | S4 | {N(0,1), U(−1,1)} | as above | p. 28; Tables 6, 11, 17 |
| Optimiser | Adam (generator and discriminator), incl. for WGAN | S1 (RMSProp noted as the suggestion in [2] but not stated as tried) | – | – | p. 31 (§3.1.5) |
| Learning rate | Table 5: α = 0.001 "selected from research" [13]; §3.1.5: "experimented with … varied between 0.01 and 0.0001" | S2 ([13] = Chun-Liang Li, CMU thesis 2019) and S4 (contradictory statements) | 0.01 to 0.0001 | not stated | p. 31-32 |
| Discriminator updates per generator update k | 5 | S2: "as suggested in [2]" (Arjovsky et al.), after S4 check ("varied in the initial stages") | not stated | V9: "gave satisfactory results" | p. 31 (§3.1.6), p. 32 (Table 5) |
| Training length | 10,000 iterations | S2: [13] | – | – | p. 32 (Table 5) |
| WGAN weight clipping c | [−0.01, 0.01] | S2: [2] | – | – | p. 32 (Table 5) |
| Mini-batch size (true SGD batch) | not clearly stated; Figure 3 shows the encoder with "a batch-size of 128" | S19 / S1 | – | – | p. 30 (Fig. 3) |
| Training sample size s (treated as a hyperparameter) | Normal: NS 1280, WGAN 320, MMD 640; 2-GMM: 1280/640/320; 3-GMM: 640/640/320 | S4 | {320, 640, 1280} | as above | Tables 6, 11, 17 |
| Weight init, seed, dropout, regularisation | not stated | S19 | – | – | – |

### Andersen–Roed-Sørensen MSc 2021
**Document.** Andersen, M. R. and Roed-Sørensen, U. (2021). "Bayesian Neural Networks: Theory and Applications." Master's thesis, Copenhagen Business School, Cand.merc.(mat.), supervisor Peter Dalgaard, submitted May 17 2021. Master's thesis. PDF page numbers are used below; printed page = PDF page − 18 in the body.

**Network(s).** (i) Non-Bayesian feedforward NNs in Keras/TensorFlow: 0 or 1 hidden layer of 10 units, with no regularisation, L2 weight decay or early stopping, on Boston housing (regression, ReLU) and a 400-row subsample of Taiwan credit-card default data (classification, tanh). (ii) MCMC (NUTS, PyMC3) Bayesian NNs with the same shapes: 0 hidden layers (Bayesian linear/logistic regression), 1 hidden layer with a fixed Gaussian prior, and 1 hidden layer with a hierarchical prior. (iii) A toy rejection-sampling BNN (Neal 1996 style) in §4.3.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth (NN and BNN) | 0 or 1 hidden layer (both reported as a comparison, not selected) | S18-type comparison of fixed designs; S1 | {0, 1} | test MSE / test cross-entropy reported (comparison only) | p. 84, 88, 93, 97 |
| Width (NN and BNN) | 10 neurons | S4: "found to provide acceptable results after experimenting with several other options"; reused across all models "to make them more suitable for comparison" | not listed | VX: criterion not stated | p. 84 (Boston), p. 93 (credit), p. 88 (BNN "for ease of comparison") |
| Activation | Boston: ReLU hidden, linear output; credit: tanh hidden, sigmoid output | S4 (same "experimenting" statement) | not listed | VX | p. 84, 93, 97 |
| Optimiser | Adam (Keras `optimizer = 'adam'`) | S1; with the learning rate at the library default (S3, evident from printed code; Keras default 0.001 not stated in text) | – | – | p. 84, 93; code p. 122, 134-137 |
| Learning rate | not stated in text (Keras Adam default, code passes no rate) | S3 (evident from code) | – | – | code p. 122 |
| Batch size | not stated in text (code passes no batch_size, so Keras default) | S3 (evident from code) | – | – | code p. 122, 135 |
| Epochs (max) | Boston 300; credit 1000 | S4: "experimenting"; for Boston, longer runs were checked and losses "continued to be around the same level as in epoch 300" | "training periods with more epochs" | V1: training/validation loss curves (random 30% validation split of the training part) | p. 84-85, 93 |
| Early-stopping patience φ and δmin | Boston: patience 10, δmin 0.1 (stopped at epoch 255); credit: patience 0, δmin 0 (stopped at epoch 194) | Boston S1; credit S4: chosen "by seeing that the validation error was smoothly increasing when training the network with no regularization"; epochs themselves S12 | – | V1: validation MSE / cross-entropy on 30% validation split (Keras `validation_split = 0.3`) | p. 85, 87, 93-96; code p. 122, 135 |
| L2 weight decay α (kernel and bias) | Boston α = 0.3 (text and code); credit 0.1 (code only, `reg_const = 0.1`; not stated in text) | S1: "we select α = 0.3" with no procedure (the thesis's own §2.3.1 recommends CV for α) | none | VX | p. 85 (Table 5.2 caption); code p. 123, 136 |
| Weight init (NN) | Keras default (not stated) | S3 (implicit) | – | – | – |
| Seeds | tf.random.set_seed(40) for NNs; 42 for BNN scripts; data split seed 3030; PyMC `random_seed = 42` in the Boston 1-hidden BNN | S1 (from code) | single seed per model | – | code p. 122-146 |
| BNN prior, 1-hidden (Boston) | weights ~ N(0, 0.1) (code `prior_std = .1`, i.e. sd 0.1) | S2 for the Gaussian form ("follow the example of MacKay (1991) and MacKay (1992)") + S1 for the scale | – | – | p. 88; code p. 131 |
| BNN prior, 1-hidden (credit) | weights ~ N(0, 1) (code `prior_std = 1`) | S1 | – | – | p. 97; code p. 146 |
| BNN hierarchical prior | w ~ N(µ, σ), µ ~ Cauchy(α = 0, β = 1), σ ~ Half-Normal(ν = 1); in code µ and σ have one value per weight (shape = weight-matrix shape) | S14 (hierarchical prior, citing Neal 1996 / MacKay) with hyper-prior parameters by S4: "After experimenting with different choices" | not listed | VX | p. 78-79 (§4.6), p. 88, 97; code p. 126-127, 140-141 |
| BNN likelihood scale (regression) | Gaussian likelihood, σ = 1 fixed | S1 | – | – | p. 88 (out of scope, noted) |
| NUTS target acceptance δ | 0.90 | S4: "as it provided us with most acceptable results" (the thesis itself reports the Hoffman & Gelman recommendation δ ≈ 0.6) | not listed | VX | p. 76, 88, 97 |
| NUTS step size ε, tree depth, mass matrix | adapted by dual averaging during warm-up / PyMC3 defaults | S13-analogue for MCMC (automatic step-size adaptation) + S3 ("default settings in PyMC3") | – | target acceptance rate | p. 75-76, 88 |
| MCMC draws / burn-in / chains | Boston: 3 chains × 3000 draws, burn-in (tune) 1000; credit: 3 × 1500, burn-in 1000 | S4: draws for credit limited by memory; burn-in 1000 "since we believe the Markov chains must have converged" (no diagnostic reported); chains S2 (Goodfellow et al.: run several chains) | – | none (no R-hat/ESS reported) | p. 62, 88, 97 |
| Toy BNN (§4.3) priors | standard normal priors on weights and biases; output-weight sd 1/√16 for a 16-unit hidden layer; likelihood sd σk = 0.1 | S2 (Neal 1996) + S5 (output-weight prior scaled by 1/√width) | – | – | p. 57-58 |

### Dong et al. 2020
**Document.** Dong, C., Liu, L., Li, Z. and Shang, J. (2020). "Towards Adaptive Residual Network Training: A Neural-ODE Perspective." Proceedings of the 37th International Conference on Machine Learning (ICML), PMLR 119, 2020. Conference proceedings version (main paper only; the appendix referred to in the text is not in this file).

**Network(s).** ResNets / pre-activation ResNets (convolutional, 3 subnetworks for CIFAR, 4 for Tiny-ImageNet) trained with LipGrow, a constructive method that starts shallow and doubles the depth during training when a scaled Lipschitz constant of the residual blocks exceeds a tolerance r_tol. Compared with fixed-depth "Vanilla" ResNets and "Hand-Tuned" growth schedules on CIFAR-10, CIFAR-100 and Tiny-ImageNet.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Depth schedule (when to grow) | grow when L(F)/L0 > r_tol; exactly 2 growths per run | S16: constructive depth growth during training driven by a Lipschitz-based scheduler (the proposed method); explicitly "different from Neural Architecture Search" | growth epoch is data-driven; compared against grid search over first-growth epoch and sampled hand-tuned schedules | V9: scaled Lipschitz constant of residual blocks (computed from weights via power iteration, averaged over blocks, 10-epoch smoothing), no validation data | p. 4-6 (§3.1, §4.2, Alg. 2), p. 8 |
| Growth tolerance r_tol | 1.4 (CIFAR), 1.3 (Tiny-ImageNet); "typically chosen around 1.4" | stated as "the only hyper-parameter that needs to be tuned"; how tuned is not stated in the main text (sensitivity "in the appendix", not in this file) | not stated | VX | p. 7 (§5.2, footnote 8) |
| Growth operator / depth increment | clone nearest residual blocks; depth doubled at each growth | S4/S5: doubling chosen "to facilitate the efficiency of the training and balance the optimization of each residual function"; cloning justified by the theory (Theorem 2) | cloning vs other initialisations discussed (appendix) | – | p. 4-5 (§3.2, §4.1) |
| Final depth | ResNet-50, ResNet-74 (CIFAR); ResNet-66 (Tiny-ImageNet); initial depth implied by N = 2^m(N0 − 2) + 2 with m = 2 | S1: target depths fixed in advance (standard ResNet sizes); Vanilla depths 14/20/50/74 compared | {14, 20, 50, 74} for Vanilla | test/val accuracy reported | p. 7-8 (§5.2, §5.3, Tables 2-3) |
| Step-size scaling after growth | "implicit step size": scale conv and BN weights/bias by N/N⁺ | S4: "slightly better than introducing explicit step size in our experiments" | {implicit, explicit step size} | VX | p. 5 (§4.1) |
| Reserved final-model epochs | 30 of 164 (CIFAR), 20 of 90 (ImageNet-like) | S1 | – | – | p. 5 (footnote 3) |
| Lipschitz smoothing window / power iterations | 10 epochs; 100 power iterations per conv filter per epoch (1 said to be often sufficient) | S1 (power-iteration count with S2 note from Yoshida & Miyato 2017) | – | – | p. 5-6 (§4.2, §4.3, footnote 4) |
| Learning-rate schedule | adaptive cosine annealing, cycle reset to remaining epochs after each growth; ηmin, ηmax values not stated | S13 (proposed variant of cosine annealing; also applied to Vanilla and Hand-Tuned) | vs cosine annealing and cosine with restarts (appendix; "Generally they all have similar performance") | VX | p. 6 (§4.4) |
| Epochs | 164 (CIFAR), 90 (Tiny-ImageNet) | S1 | – | – | p. 7 (§5.2) |
| Batch size | 128 train, 100 validation | S1 | – | – | p. 7 (§5.2) |
| Weight decay, momentum | 2 × 10^-4, 0.9 (optimiser implied SGD with momentum, not named) | S1 | – | – | p. 7 (§5.2) |
| Repetitions | 3 runs, mean ± std | – | – | – | p. 7-8 |

### Yu–Tomasi 2019
**Document.** Yu, S. and Tomasi, C. (2019). "Identity Connections in Residual Nets Improve Noise Stability." ICML 2019 Workshop on Understanding and Improving Generalization in Deep Learning, Long Beach, California. Workshop paper (4 pages + references + supplementary material).

**Network(s).** Simplified plain CNNs (PlnNets) and simplified residual CNNs (ResNets, identity skip across single conv layers, no batch norm), depths 20/32/44, on CIFAR-10. Also "fully-fledged" ResNet-20 blocks (conv-BN-ReLU) for the noise-stability measurement. The residual/identity connection is the object of study.

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Skip connection (residual vs plain) | both, compared; identity across a single conv layer | S18: the controlled comparison is the research question; simplified block justified as preserving the phenomena | {plain, residual} | training loss and test error reported (comparison, not selection) | p. 1-2, 6-7 |
| Depth | L = 3N + 2 ∈ {20, 32, 44} | S1 / S18 (varied to show degradation) | {20, 32, 44} | – | p. 6 (App. A) |
| Width / kernel size | 16, 32, 64 filters in three groups; all filters 3 × 3; 8 × 8 average pooling; FC 64 × 10 | S1 (CIFAR ResNet-style layout, not justified) | – | – | p. 2, 6 (App. A, Figure 4) |
| Activation | ReLU | S1 | – | – | p. 2 |
| Batch normalisation | removed in simplified nets; present in fully-fledged blocks | S4 (design simplification) | – | – | p. 1, 4 |
| Weight initialisation | plain: Kaiming (σp = √(2/S)); residual: Hardt-Ma (σr = 1/S, from page image; S = CUV); equivalent init via transformation T in Table 2 | S2: He et al. (2015), Hardt & Ma (2017); initialisation is itself the studied factor | {KWI, HMWI, T-equivalent} | – | p. 3, 6 (App. A) |
| Initial learning rate | 10^-2 for five networks; 10^-3 for depth-44 plain | S4: the exception was made because "the training loss for the depth-44 plain network does not decrease with larger learning rates" | {10^-2, 10^-3} (implied) | V6: training loss | p. 7 (Table 1 caption) |
| Learning-rate schedule | ÷10 after epochs 120 and 160 | S1 (step schedule, S13-type) | – | – | p. 7-8 (Tables 1-2) |
| Epochs | 200 (Tables 1-3); 1200 in Figure 2 | S4: "after 200 epochs of training, when the loss stabilizes" | – | V6: training-loss stabilisation | p. 4, 6 |
| Weight decay λ | 10^-4 (for residual-equivalent plain nets the penalty is ‖T⁻¹(p)‖²) | S1 | – | – | p. 3, 7-8 |
| Optimiser, batch size | not stated | S19 | – | – | – |
| Seeds / repeats | Figure 2: 13 plain + 13 residual networks with random (equivalent) initialisations and randomised sample order; Tables 1-3: not stated (apparently single runs) | S15-like averaging for Figure 2 (variance estimation, not ensembling) | – | – | p. 4 |
| Numerical precision | double precision on one CPU for equivalence experiments | S4 | – | – | p. 6 (App. B) |

## A.10 Books in the folder

### Graziani–Xibilia (eds.) 2021
**Document.** Salvatore Graziani and Maria Gabriella Xibilia (Editors), 2021, *Innovative Topologies and Algorithms for Neural Networks*, MDPI (Basel), "Printed Edition of the Special Issue Published in Future Internet", ISBN 978-3-0365-0284-7 (Hbk), 978-3-0365-0285-4 (PDF). BOOK — an edited volume that reprints 13 open-access journal articles (1 editorial + 12 research articles) from *Future Internet* 2018-2020. Each chapter is a separate peer-reviewed journal article; MDPI asks that each be cited independently. The text file has 200 PDF pages; book page b = PDF page b + 11.

**Network(s).** CNN, GCN, GRU/LSTM, ConvLSTM, 3D-CNN, R-CNN-type architectures across 11 application chapters (computer vision, NLP, medical imaging). No actuarial content.

*the chapter is given in the first column; Ch. 2 and the editorial train no network*

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (PDF p.) |
|---|---|---|---|---|---|
| Ch1 CNN backbone | ResNet-101, 2048x14x14 conv5_x maps | S2: chosen because "ResNet-101 is a common paradigm in image classiﬁcation" (pre-training not stated) | not stated | VX | 20-21 (G10, G105) |
| Ch1 label embedding dim | 300 | S1 | not stated | VX | 23 (G12) |
| Ch1 GCN depth (number of graph conv layers) | best at 3; layers used in the final "Ours-improved" model not stated | S6/S18: 1-D sweep reported as ablation | plotted points at 2, 3, 4, 5, 6, 7 GCN layers (from figure image, PDF p. 25; axis runs 0-9) | V5 (inferred): mA; the official validation split was merged into training, so the comparison can only be on the test data | 24 (G11, G15, G16) |
| Ch1 graph threshold t (adjacency binarisation; structural) | "top results when the threshold is about 0.9"; final t not stated | S6/S18: 1-D sweep | plotted points 0.1, 0.2, ..., 0.8, 0.85, 0.9, 0.95 (from figure image, PDF p. 25) | V5 (inferred): mA, test data | 24 (G13) |
| Ch1 re-weighting proportion p | about 0.5 best; "does not work for improving overall performance" | S6/S18 | plotted points 0.1 to 0.9 by 0.1 (from figure image, PDF p. 25) | V5 (inferred): mA | 24 (G14) |
| Ch1 optimiser, learning rate, batch, epochs, dropout | not stated | S19 | - | VX | - |
| Ch3 word embedding dim | 200 (GloVe, not fine-tuned) | S2: pre-trained GloVe | - | VX | 68 (G20) |
| Ch3 GRU hidden size | 200 per layer | S1 | not stated | VX | 68 (G21) |
| Ch3 CNN filter windows and maps | windows 3, 4, 5 with 100 maps each; pooling 4 | S1 | not stated | VX | 68 (G21) |
| Ch3 layer ordering (Bi-GRU then CNN) | Bi-GRU+CNN | S18, used as justification: 3 orderings compared | Bi-GRU+CNN, CNN+Bi-GRU, CNN-Bi-GRU (parallel) | V5: "Test accuracies" on MR and SST | 70-71 (G24-G26) |
| Ch3 optimiser, learning rate | AdaDelta, 10^-2 | S1 | not stated | VX | 68 (G17, G22) |
| Ch3 mini-batch | 32 | S1 | not stated | VX | 68 (G22) |
| Ch3 dropout | 0.5 (Bi-GRU), 0.2 (penultimate) | S1 | not stated | VX (a 10% development set is created for MR but never said to be used) | 68 (G18, G23) |
| Ch3 L2 coefficient lambda_r | 10^-5 | S1 | not stated | VX | 68 (G23) |
| Ch4 3D-conv kernel, filters | kernel 2x2x2, filters 8/32/64; ConvLSTM kernel 2x2, 64 filters | S1 | not stated | VX | 79-80 (G28, G29) |
| Ch4 activation | ReLU | S4: justified by vanishing-gradient argument | - | - | 78 (G27) |
| Ch4 dropout | a dropout layer after each pooling; rate not stated | S19 (rate) | - | VX | 79 (G30) |
| Ch4 optimiser, learning rate, betas | Adam, 0.001, 0.9/0.999 (the usual Adam defaults, but not called defaults) | S1 | - | VX | 80-81 (G31, G33) |
| Ch4 batch size | 64 ("64 batches") | S1 | - | VX | 81 (G32) |
| Ch4 epochs | 100 | S1; curves show stabilisation at about 40 epochs, but that is not used to change the count | - | V9: training and "verification" curves viewed after the fact | 81-82 (G32, G35, G36) |
| Ch5 DNet/CNet depth, input size | DNet: 5 feature layers + 2 prediction layers, 192x192 input; CNet: 2 extra conv + 2 FC + softmax | S4: small targets and parameter budget | not stated | VX | 91-92 (G37, G38) |
| Ch5 grid cells (output-layer structure) | 6x6 | S6: 1-D sweep with an accuracy-speed trade-off | 4x4, 5x5, 6x6, 7x7, 8x8, 9x9 | V5 (inferred) + V9: detection accuracy and FPS; only a 4700/1300 train/test split exists, and the 6x6 accuracy (0.9233) equals the reported DNet test accuracy | 94-95 (G41-G43) |
| Ch5 learning rate and schedule (DNet) | 0.01, /10 every 10,000 iterations, 50,000 iterations | S1 (schedule) + S4 (stop when "losses tend to stabilize") | - | V6: training loss | 92 (G39) |
| Ch5 learning rate and schedule (CNet) | 0.1, /10 every 5000 iterations, 40,000 iterations | S1 + S4 | - | V6: training loss | 93 (G40) |
| Ch5 (out of scope) loss weight lambda; voting weights | lambda = 0.7; lambda_b, lambda_c, lambda_s = 0.3, 0.5, 0.2 | S6: 1-D sweep "experimentally" | lambda 0.1 to 0.9 by 0.1; 7 weight triples | V5 (inferred): detection or recognition accuracy (lambda = 0.7 gives 0.9233, again the test figure) | 95 (G44-G46) |
| Ch6 depth | 5 conv + 2 FC | S9/S6: depth swept with kernel 3x3 fixed | 3, 4, 5, 6 conv layers | V3 + V5: 5-fold CV accuracy, the same folds that give the reported 78.6% (no inner validation) | 103, 105, 107 (G47, G53, G55, G60, G62) |
| Ch6 kernel size | 3x3 | S9/S6: swept with 5 conv layers fixed | 3x3, 5x5, 7x7 | V3 + V5 as above | 107 (G60, G61) |
| Ch6 conv channels | 128 (64 in the first layer) | S9/S6 | 64, 128, 256 kernels per layer | V3 + V5: per-fold accuracy (Fig. 6) | 103, 107 (G48, G56, G57) |
| Ch6 activation | ReLU | S2/S4: "[20]"; faster convergence | - | - | 103 (G49) |
| Ch6 dropout | 0.7 after the 5th pooling layer | S1 | not stated | VX | 103 (G50) |
| Ch6 optimiser | Adam, beta 0.9/0.999 ("standard parameters") | S3: standard (default) parameters | - | - | 104 (G51) |
| Ch6 batch size | 16 | S1 | - | VX | 104 (G51) |
| Ch6 learning rate and schedule | 0.001, x0.8 every 2000 epochs | S1 | - | VX | 104 (G52) |
| Ch6 epochs | 12,000 | S4: stopped when "accuracy was basically stable" (curve inspection; which data not stated) | - | VX (accuracy, data not stated) | 104 (G52) |
| Ch7 C3D backbone | 5 conv (64-128-256-512-512), 3x3x3 kernels, 2 FC of 2048 | S2: C3D [13] | - | - | 113, 117 (G65, G66) |
| Ch7 fusion method (architecture) | linear weighted fusion | S18 used as selection: "Therefore, we choose" | element-wise max, element-wise sum, concatenation, linear weighted | V5: accuracy on UCF Sports and UCF101 splits, which have only train and test parts | 121-122 (G67, G69-G71) |
| Ch7 fusion weights w_s, w_t; LSTM size | not stated | S19 | - | VX | 119 |
| Ch7 learning rate, schedule, iterations | 0.003, /2 every 150K iterations, stop at 1.9M | S1 | - | VX | 122 (G68) |
| Ch8 embedding | 100-d CBOW (Sogou news) | S2: pre-trained | - | - | 139 (G72) |
| Ch8 dropout | 0.5 "fixed ... in all experiments" | S1 | - | VX | 139 (G73) |
| Ch8 epochs, batch, optimiser, learning rate | 20 epochs, batch 50, SGD, 0.05 | S1 | - | VX | 139 (G74) |
| Ch8 Bi-LSTM hidden size | not stated | S19 | - | VX | - |
| Ch8 evaluation protocol | 5-fold CV (4 folds train, 1 test), averages reported | (evaluation, not selection) | - | - | 139 (G75) |
| Ch9 backbone | VGG-16 pre-trained | S2 | - | - | 154 (G77) |
| Ch9 optimiser, learning rate | SGD, 0.001 | S1 | - | VX | 154 (G78) |
| Ch9 feature-fusion and attention modules | both kept | S18: component ablation | with or without attention; with or without fusion | V5: mAP on PASCAL VOC 2007 test | 154-155 (G76, G79) |
| Ch10 embedding dim | 100 | S1 ("fixed to") | - | VX | 167 (G81) |
| Ch10 LSTM hidden size | 200 per direction (400 bi) | S1 | - | VX | 167 (G81, G82) |
| Ch10 activation | tanh | S1 | - | VX | 167 (G82) |
| Ch10 cell type, directionality | BLSTM + char embedding (best) | S18: 6 architectures compared | LSTM, GRU, BLSTM, BGRU, BLSTM+char, BGRU+char | V5: P/R/F1 on the ANERCorp test corpus (only training and testing corpora) | 167-168 (G80, G86) |
| Ch10 L2 weight | not stated (L2 used) | S19 | - | VX | 167 (G83) |
| Ch10 dropout | 0.5 | S1 | - | VX | 167 (G84) |
| Ch10 optimiser, batch, epochs | AdaGrad (learning rate not stated), 128, 30 | S1 | - | VX | 167 (G84) |
| Ch11 architecture | Inception-v3 + DeepID parts, concat, softmax; ImageNet pre-training | S2: transfer learning, "optimal choice" | - | - | 177-178 (G91-G93) |
| Ch11 learning rate, schedule, optimiser | 0.001, decay factor 16 every 30 epochs; RMSProp decay 0.9, momentum 0.9, eps 0.1 | S1 as printed (no source given; see referee flag: probably S2 from Esteva et al. [15]) | - | VX | 179 (G94) |
| Ch11 batch size | 60 (training), 100 ("cross-validated") | S1 | - | VX | 177 (G90) |
| Ch11 epochs | not stated | S19 | - | VX | - |
| Ch12 word-vector dim | 300 (English, Google word2vec); 250 (Chinese, own word2vec) | S2 (English); S4 (Chinese: "better representation on this configuration is obtained") | not stated | VX | 192 (G97) |
| Ch12 maxlen (input length) | 18 (SST), 100 (THUCNews) | S5: average article length | sensitivity 20, 40, 60, 80, 100, 120 (Fig. 4, from figure image) | VX (the sensitivity is best at 80, not the 100 used) | 192, 195 (G98, G101, G102) |
| Ch12 number of layers | 1 BLSTM + 1 conv | S4: "After lots of experiments" | not stated | VX (a 10% validation split exists, but its use is not stated) | 192 (G96, G99) |
| Ch12 BLSTM units | 50 | S1 | - | VX | 192 (G100) |
| Ch12 dropout | 0.5 ("the dropout rate obtained is 0.5") | S4 implied by "obtained"; no procedure given | not stated | VX | 192 (G100) |
| Ch12 conv filters, window, pooling | 64 filters, window 5, pooling 4 | S1; after-the-fact S6/S18 grid finds window 7 best | kernel 2 to 8 x output dim 32/48/64/96/128 (Fig. 5, from figure image) | VX (the figure says "question classification"; data not stated) | 192, 195-196 (G100, G103) |
| Ch12 activation | ReLU | S1 | - | - | 190 (G95) |
| Ch12 optimiser, learning rate, batch, epochs | not stated | S19 | - | VX | - |

### Gridin 2021
**Document.** Ivan Gridin, *Time Series Forecasting using Deep Learning: Combining PyTorch, RNN, TCN, and Deep Neural Network Models to Provide Production-Ready Prediction Solutions*, BPB Publications (India). The copyright page says "FIRST EDITION 2022" (the file stem says 2021), ISBN 978-93-91392-574. BOOK (single-author practitioner text), read from an EPUB. The code bundle is on GitHub (bpbpublications/Time-Series-Forecasting-using-Deep-Learning).

**Network(s).** worked PyTorch examples on synthetic and real series: - FCNN (Ch. 2), and a CNN + FC regressor for UK temperature (Ch. 3). - RNN, GRU and LSTM for hourly energy (Ch. 4). - LSTM encoder-decoder and TCN (Ch. 5). - NNI-tuned GRU, a TCN "NAS" and a hybrid filter + causal-conv + RNN model (Ch. 6). - TCN classifier for rain, encoder-decoder for COVID-19 cases, and a GRU/RNN + indicator trading model (Ch. 7). - DeepAR and the Ch. 3 custom CNN wrapped in PyTorch Forecasting (Ch. 8).

*the example is given in the first column; "code" = shipped GitHub code, not the book text*

| Hyperparameter | Final value(s) | How determined (S-code: words) | Candidates / search space | Selection signal (V-code: metric, data) | Evidence (chapter > section; idx p.) |
|---|---|---|---|---|---|
| Ch2 FCNN widths / depth | 2 hidden layers, 64 and 32, ReLU | S1 (ReLU per the S5 rule) | - | - | Ch2 > Training > Train, validation and test datasets; idx p. 61 (R73) |
| Ch2 optimiser, learning rate | Adam, PyTorch default learning rate | S3 | - | - | same (R64) |
| Ch2 epochs | 10,000 full-batch; weights from the best validation epoch | S1 (count) + S12 (checkpoint) | - | V2: validation MSE on a chronological 70/15/15 split (`shuffle = False`) | same (R50, R51, R74) |
| Ch3 CNN+FC (UK min. temperature) | l_1 = 400, l_2 = 48, conv1_out = 6, kernels 36 and 12, dropout 0.1 | S1: no justification given | - | - | Ch3 > Example > Testing > Initializing models (R75) |
| Ch3 input window | 120 months | S4: "10-year observation history" | - | - | Ch3 > Example > Testing > Number of features (R76) |
| Ch3 optimiser, learning rate, epochs | Adam default; 150 epochs; best validation epoch kept | S3 + S1 + S12 | - | V2: validation L1, chronological split | Ch3 > Example > Testing > Training process (R52, R64, R77) |
| Ch4 RNN/GRU/LSTM hidden size | 24 | S1 | - | - | Ch4 > Recurrent neural network > Parameters (R78) |
| Ch4 learning rate | 0.02 (Adam) | S1 | - | - | same (R78) |
| Ch4 epochs | 500 (RNN, GRU), 100 (LSTM); best validation epoch kept | S1 + S12; afterwards judged "too early" for the LSTM (S4) but not rerun | - | V2: validation MSE | Ch4 (R53, R78) |
| Ch5 encoder-decoder | LSTM hidden 64, learning rate 0.005, teacher-forcing ratio 0.05, 500 epochs | S1 | - | none: train/test split only, no validation set | Ch5 > Encoder-decoder model > Global parameters / Training (R79) |
| Ch5 TCN | channels [10]*4, kernel 5, dropout 0, learning rate 0.005, 1000 epochs, window 20 | S1 + S12 | - | V2: validation MSE | Ch5 > Temporal convolutional network > TCN prediction model (R80) |
| Ch6 GRU optimiser | adam | S11: NNI Evolution, population 8, 30 trials, concurrency 2 | {adam, sgd, adamax} | **V5: TEST MSE** reported to NNI | Ch6 > Hyper-parameter tuning > NNI search; idx p. 181-184 (R8, R9, R81-R84) |
| Ch6 GRU hidden size | 16 | S11 (as above) | {8, 12, 16, 24, 32} | V5 | same (R82, R84) |
| Ch6 GRU learning rate | 0.01 | S11; confirmed as "critical" by top-20% analysis (S18/S27) | {0.001, 0.005, 0.01} | V5 | same (R82, R84, R85) |
| Ch6 GRU epochs | 50, best validation epoch kept within each trial | S1 + S12 | - | V2 inside the trial | Ch6 > Deep Learning model trial (R86) |
| Ch6 TCN "NAS": number of temporal causal layers, channels, kernel, dropout, slices, activation, bias | 2, 6, 5, 0, 1, relu, True | S16 via S11 (tuner not shown in book text; code: Evolution, population 32, 300 trials); then S18/S27 "compression" | layers {1-4}, channels {4, 6, 10}, kernel {3, 5, 7}, dropout {0, .1, .2}, slices {1, 2}, act {relu, tanh}, bias {T, F} | not stated in text; code: **V5 test MSE** | Ch6 > Neural Architecture Search; idx p. 186-192 (R15, R18, R87-R89) |
| Ch6 hybrid model: trend/cycle filter, causal conv (+kernel), RNN hidden, FCNN layers and size | HP trend + CF cycle filters; no causal conv; FCNN optional; exact best config not printed | S16 via S11 (code: Evolution, population 32, 300 trials, learning rate 0.02 fixed, 100 epochs) + S27 top-5% analysis | filters {None, hp, cf}; causal conv {False, True with kernel {3, 5, 7, 9}}; RNN hidden {8, 16, 24}; FCNN layers {0, 1, 2}; size {4, 8, 12} | not stated in text; code: **V5 test MSE** | Ch6 > Hybrid models; idx p. 196-202 (R19, R90-R92) |
| Ch7 rain TCN classifier: layers, channels, kernel, dropout, slices, bias, learning rate | 2, 32, 7, 0.1, 1, True, 0.005 (activation fixed relu) | S11: NNI (code: Evolution, population 32, 300 trials); S27 top-5% analysis | layers {1, 2, 3}, channels {8, 16, 24, 32}, kernel {3, 5, 7}, dropout {0, .1, .2, .4}, slices {1, 2}, bias {T, F}, learning rate {.01, .005, .0001} | **V1**: minimum validation cross-entropy over epochs on a RANDOM 20% of overlapping sliding windows (5 cities, 2008-2015); then tested on 2016 Sydney (balanced accuracy 0.7644) | Ch7 > Rain prediction; idx p. 216-219 (R93-R100) |
| Ch7 rain epochs, window | 500; 14 days | S1 / S4 | - | - | Ch7 > Rain prediction > Global parameters (R101) |
| Ch7 COVID encoder-decoder: hidden, decision-layer size, learning rate, teacher-forcing ratio | 32, 12, 0.01, 0.1 | S11 (code: Evolution, population 32, 300 trials); S27 top-10 analysis | hidden {8, 12, 16, 24, 32, 64}, decision {4, 6, 8, 12}, learning rate {.001, .005, .01}, teacher-forcing ratio {.1, .2, .3, .4, .5} | V1: validation loss on a random 20% of windows from 6 countries | Ch7 > COVID-19 confirmed cases forecast; idx p. 223-236 (R68, R102-R104) |
| Ch7 COVID epochs, window, horizon | 200; 120; 60 | S1 | - | - | same (R105) |
| Ch7 trading: learning rate, cell type, RNN hidden, indicator layer, decision layer, 2 indicators and lengths | 0.01, rnn, 24, 1, 2, RSI(20), CMO(20) | S11 (code: Evolution, population 32, 1000 trials) | learning rate {.01, .005, .001, .0005}; {rnn, gru}; {8, 16, 24}; {1, 2, 4}; {2, 4, 8, 16}; 7 indicators with nested lengths | **V2 + V9**: minimum validation negative mean trading return on the last 20% (chronological) of 2010-2019; tested on 2020 | Ch7 > Algorithmic trading; idx p. 249-254 (R106-R110) |
| Ch7 trading output activation | tanh | S4/S5: forced by the [-1, 1] position constraint | - | - | Ch7 > Algorithmic trading (R111) |
| Ch8 custom model | the Ch3 values (400, 48, 6, 36, 12, 0.1) | S2 (reused from Ch3 within the book) | - | - | Ch8 > A complete example (R75 values repeated) |
| Ch8 DeepAR | library defaults (hidden 10, 2 LSTM layers, dropout 0.1, learning rate 0.001, ranger) | S3 | - | - | Ch8 > Initializing Deep Autoregressive model (R63, R65) |
| Ch8 learning rate | `lr_find` suggestion printed; never assigned in the listing | S13 (LR range test, max_lr 0.3) | range test up to 0.3 | V6: `lr_find` scans training loss against learning rate (library behaviour, not stated in the text) | Ch8 > A complete example; idx p. 271-276 (R57-R59) |
| Ch8 epochs | early stopping: patience 1, min_delta 1e-5, max_epochs 1000; limit_train_batches 30; gradient clip 0.1; batch 240 | S12 (true early stopping) + S1 | - | V2: `val_loss` on a validation set built from the pre-2015 training data | same (R54-R56, R112, R113) |

## A.11 Shipped code

### Manai (2026), claims-reserving benchmark

*FeedForwardNN (PyTorch)*

| Hyperparameter | Value in code | Where (file:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| Depth | 2 hidden layers (Linear-ReLU-Dropout-Linear-ReLU-Linear) | models/neural.py:102-109 | hard-coded (the layer structure is fixed in code) | not searched | none |
| Width | (32, 16) | neural.py:50 (default); config/models.yaml:43; defaults/models.yaml:18; passed at benchmark.py:171 | config file, fixed a priori | not searched | none |
| Activation | ReLU (hidden); identity output | neural.py:104, 107, 108 | hard-coded | not searched | none |
| Embeddings | none; origin/dev/calendar enter as scaled numerics, squares, log cumulative, etc. (8 features) | models/machine_learning.py:17-26, 37-59 | hard-coded feature engineering | n/a | n/a |
| Skip/residual connections | none | neural.py:102-109 | n/a | n/a | n/a |
| Optimiser | AdamW (betas, eps = PyTorch defaults) | neural.py:110-112 | hard-coded (+ library default betas/eps) | not searched | none |
| Learning rate | 0.003, constant | neural.py:53 | **hard-coded dataclass default. It is not in any YAML and `model_registry` does not pass it** (benchmark.py:170-187) | not searched | none |
| LR schedule | none | not in code | n/a | n/a | n/a |
| Batch size | full batch (the whole training split every step) | neural.py:123-128 (one `optimizer.step()` per epoch on `train_x`) | hard-coded | not searched | none |
| Max epochs | 350 (full run); 120 in `--quick` mode | models.yaml:44; evaluation.yaml:13 (`neural_epochs: 120`); benchmark.py:168 | config file | not searched | none |
| Early stopping | patience 35, min_delta 1e-5, monitor = validation Huber loss, restore best weights | neural.py:119-142; models.yaml:45, 48 | config file (patience, min_delta); logic hand-written | not searched | validation Huber loss on a random 20% of observed cells |
| Validation split | random 20% of observed triangle cells (`train_test_split`, not temporal). If &lt;12 cells, validation set = training set | neural.py:91-100; models.yaml:47 | config file (fraction); hard-coded fallback | n/a | n/a |
| Epochs actually run (from shipped results) | company panel: median 82, range 36-350 (n=288); scenarios: median 95, range 36-350 (n=630) | results/research_company_detailed.csv, research_scenario_detailed.csv, column `diagnostic_epochs_run` | outcome of early stopping | n/a | n/a |
| Dropout | 0.05, after first hidden layer only | neural.py:105; models.yaml:46 | config file | not searched | none |
| Weight decay (L2) | 1e-3 (decoupled, AdamW) | neural.py:111; models.yaml:49 | config file | not searched | none |
| Normalisation | input `StandardScaler` and target `StandardScaler`; no BatchNorm/LayerNorm | neural.py:87-90 | hard-coded | n/a | n/a |
| Initialisation | PyTorch `nn.Linear` default (Kaiming-uniform, a=sqrt(5)) | not set in neural.py | library default | not searched | none |
| Loss (context) | `nn.HuberLoss()` (delta = 1.0 default) on the standardised signed-log1p target | neural.py:113 | hard-coded | n/a | n/a |
| Seeds | `np.random.seed`, `torch.manual_seed`, `torch.cuda.manual_seed_all`; cudnn deterministic; `torch.use_deterministic_algorithms(True, warn_only=True)` | neural.py:74-81 | seed value passed in: 42 (default, public benchmark); 20260807 (research company panel, research.yaml:24 -> research.py:267); scenario seed 1000-1029 (research.yaml:30-31 -> research.py:323, 366), i.e. **the NN seed is the same as the data-simulation seed** | not searched | none |
| Ensemble / repeats | none. One network per triangle x valuation diagonal | benchmark.py:166-188 | n/a | n/a | n/a |
| Output guardrails (context) | predictions clipped to [min-0.1*range, max+0.1*range]; projection cap 3 x 95th pct | neural.py:144-148; models.yaml:26, 50 | config file | n/a | n/a |

*ChainLadderResNet (sklearn MLPRegressor)*

| Hyperparameter | Value in code | Where (file:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| Depth / width | 2 hidden layers (24, 12) | hybrid.py:30, 59; models.yaml:56 | config file | not searched | none |
| Activation | ReLU | hybrid.py:60 | hard-coded | not searched | none |
| Skip/residual | none inside the MLP. The "residual" is the CL backbone plus shrunk correction | hybrid.py:104-108 | hard-coded | n/a | n/a |
| Optimiser | Adam (`solver='adam'`) | not passed (hybrid.py:58-66) | library default | not searched | none |
| Learning rate / schedule | 0.001, constant (`learning_rate_init`, `learning_rate='constant'`) | not passed | library default | not searched | none |
| Batch size | `'auto'` = min(200, n). With 15-105 training cells this means full batch | not passed | library default | not searched | none |
| Max iterations (epochs) | 600 | hybrid.py:34, 64; models.yaml:60 | config file | not searched | none |
| Early stopping | on only if >=25 training cells (hybrid.py:62; models.yaml:58). Then: random 20% validation (models.yaml:59), monitor validation **R^2**, `n_iter_no_change=10`, `tol=1e-4`, best weights restored (sklearn). If off: stops when training loss fails to improve by tol for 10 epochs, with no restore | hybrid.py:62-63 | config file (threshold, fraction) + library defaults (patience 10, tol) | not searched | validation R^2 on a random 20% of cells |
| Iterations actually run (shipped results) | company: median 54, max 600, 1/288 hit 600; scenarios: median 70.5, 23/630 hit 600; ablation: 4/1152 hit 600 | results/*_detailed.csv, `diagnostic_iterations` | outcome | n/a | n/a |
| L2 penalty | `alpha=0.01` (sklearn adds 0.5*alpha*sum(W^2)/n_samples) | hybrid.py:31, 61; models.yaml:57 | config file | not searched | none |
| Dropout | none | not in code | n/a | n/a | n/a |
| Normalisation | `StandardScaler` on inputs (pipeline). Target is residual / max(abs(CL fit), 1) | hybrid.py:53-57 | hard-coded | n/a | n/a |
| Initialisation | Glorot-uniform, bound sqrt(6/(fan_in+fan_out)) | not passed | library default | not searched | none |
| Seed | `random_state` (same values as FFNN above). Shuffle=True (default) | hybrid.py:65 | passed from caller | not searched | none |
| Shrinkage lambda (structural, borderline scope) | 0.45 in the main runs. **Ablation** over {0.0, 0.15, 0.45, 0.90} | models.yaml:55; research.yaml:28; research.py:274-307 | config file, fixed a priori | prespecified grid, **reported as an ablation and not used to pick lambda** | reserve_symmetric_error on rolling valuations (reported only) |

### Utulu (2026), reserving workflow (no network)

*not applicable. There is no NN, so no architecture, optimiser, regularisation or ensemble settings. The only "tuning-like" choices are actuarial judgement*

| Hyperparameter | Value in code | Where (file:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| (not an NN hyperparameter) LDF floor from lag 5 | selected factors for lag >= 5 clipped at 1.0 | notebook cell 26, L3-8 | hard-coded judgement (explained in cell 28) | none | none |
| (not an NN hyperparameter) tail factor | none (assumed fully developed at lag 10) | notebook cell 31 (markdown) | stated assumption | none | none |

### Zelený (2026), masters-thesis code

*(1) claim-level two-part NN (sklearn)*

| Hyperparameter | Value in code | Where (file:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| Depth / width | 3 hidden layers (192, 96, 48); both heads, pooled and Type models | notebook cell 54 L45 (dead-code call); cell 65 L95 (`_DL_KW`); passed to dl_pipeline.py:406, 456. Module defaults differ: (128, 64, 32) at dl_pipeline.py:358 and :643 | hard-coded in notebook call | **not in code** (no search) | none in code |
| Activation | ReLU | dl_pipeline.py:407, 457 | hard-coded | n/a | n/a |
| Embeddings | none. Type/AQ/cc/inj_part enter as raw numeric codes, then `StandardScaler` (ml_pipeline.py:22-43, 294-296) | as cited | hard-coded | n/a | n/a |
| Input features (context) | 20 base features + trajectory lags (`trajectory_n_lags=6`) + 5 dev-age features (`add_age_features=True`) + `log1p(prior)` for severity | cell 54 L53, L55; dl_pipeline.py:39-68, 121-165, 445-446 | hard-coded | n/a | n/a |
| Optimiser | Adam (`solver="adam"`) | dl_pipeline.py:408, 458 | hard-coded | n/a | n/a |
| Learning rate / schedule | 7e-4, constant (sklearn `learning_rate='constant'` default) | cell 54 L47; cell 65 L95; dl_pipeline.py:410, 460 | hard-coded in notebook (+ library default schedule) | not in code | none |
| Batch size | `'auto'` = min(200, n) = 200 (training rows 189,675 in cell 65 output) | not passed | library default | not in code | none |
| Max epochs | 280 | cell 54 L48; cell 65 L96; dl_pipeline.py:411, 461 | hard-coded in notebook | not in code | none |
| Early stopping | `validation_fraction=0.1`, `n_iter_no_change=20`, tol=1e-4 (default). Restores best weights (sklearn). Active only if n>=50 and minority class >=5 (classifier, dl_pipeline.py:401-402) / >=50 positive rows (severity, :452). Monitor: validation **accuracy** (classifier, stratified random split) / validation **R^2** (regressor, random split) | dl_pipeline.py:412-414, 462-464 | hard-coded (patience, fraction) + library defaults (tol, metric) | n/a | random 10% of stacked claim-snapshot rows |
| L2 (sklearn `alpha`) | 2e-4 | cell 54 L46; cell 65 L95; dl_pipeline.py:409, 459 | hard-coded in notebook | not in code | none |
| Dropout | none | not in code | n/a | n/a | n/a |
| Normalisation | `StandardScaler` per head | dl_pipeline.py:403-404, 453-454 | hard-coded | n/a | n/a |
| Initialisation | Glorot-uniform (sklearn default) | not passed | library default | n/a | n/a |
| Seed (point forecast) | `random_state=42` for every head and sub-model | cell 54 L49; dl_pipeline.py:415, 465 | hard-coded | n/a | n/a |
| Pooled/Type blend (ensemble-like) | Type model fitted if Type rows >= 1,500. Weight alpha_t = 0.20 + 0.40 * clip((n-1500)/1500, 0, 1) | cell 54 L43; cell 65 L22; dl_pipeline.py:604-619 | hard-coded | n/a | n/a |
| Seed ensemble (uncertainty only) | K = 20, seeds 100 + 7k | cell 65 L19, L210-212 | hard-coded | n/a | not used for selection or the point forecast |
| Bootstrap (uncertainty only) | B = 100 resamples of `d_fit`, seed fixed at 42, `np.random.RandomState(42)` | cell 65 L18, L147, L193-195 | hard-coded | n/a | n/a |
| Residual clip / prediction cap (context) | 1.8; cap at 2 x q0.99 | cell 54 L50-51; dl_pipeline.py:449-450, 473 | hard-coded | n/a | n/a |

*(2) triangle-based NN (Keras)*

| Hyperparameter | Value in code | Where (file:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| Depth / width | 1 hidden layer, 24 units | notebook cell 61 L23 (dead-code call); cell 69 L29; cell 78 L27. Module default (64, 32) at dl_triangle.py:446. Fallback `[20]` if empty (:240-242) | hard-coded in notebook | **not in code.** The code comment claims a sweep ("Tuned default from Section 17.2 anti-overfit sweep.", cell 61 L15), but no §17.2 and no sweep code exist in the notebook (headings jump from §17 to §18) or the package | not in code |
| Number of networks | one per development transition j (J = 11 transitions for 12 dev columns, cell 69 output "dev steps: 12"); fresh `clear_session()` each | dl_triangle.py:247, 268 | hard-coded | n/a | n/a |
| Activation | tanh (hidden); **exponential** (output) | dl_triangle.py:276, 280 | hard-coded | n/a | n/a |
| Offset / skip | non-trainable `Dense(1, use_bias=False, kernel=Ones)` on the sqrt(C_j) volume, multiplied into the output | dl_triangle.py:282-291 | hard-coded | n/a | n/a |
| Embeddings | none. Age min-max to [-1, 1] + one-hot of Type, AQ, cc, inj_part (106 columns, cell 69 output) | dl_triangle.py:143-165 | hard-coded | n/a | n/a |
| Optimiser | RMSprop (rho, eps = Keras defaults) | dl_triangle.py:295 | hard-coded | n/a | n/a |
| Learning rate / schedule | 1e-3, constant (floored at 1e-6) | cell 61 L25; cell 69 L31; dl_triangle.py:244, 295 | hard-coded in notebook | not in code | none |
| Batch size | `min(10000, max(32, n_train))`: full batch up to 10,000 claims, then 10,000 | dl_triangle.py:302 | hard-coded | n/a | n/a |
| Max epochs | 280 | cell 61 L26; cell 69 L32; dl_triangle.py:301 | hard-coded in notebook | not in code | none |
| Early stopping | `EarlyStopping(monitor="val_loss", patience=12, restore_best_weights=True)`, only if n_train >= 20 | dl_triangle.py:305-313 | hard-coded | n/a | val MSE on `validation_split=0.1` |
| Validation split | Keras `validation_split=0.1`, i.e. the **last 10% of rows** in array order, taken before shuffling (Keras semantics). Row order follows `output_df`, which the loader does not re-sort (synthetic_loader.py:171-280 returns `"output": data` unchanged). I read `simulated_data.RData` with the `rdata` package: its 499,566 rows are **sorted by AY (non-decreasing, 2014 -> 2025)**. So for each transition the validation set is, in effect, the claims from the **most recent eligible accident years**. This is a quasi-temporal hold-out, arising as a side effect of row order rather than by design | dl_triangle.py:306 | hard-coded | n/a | n/a |
| Dropout | 0.30 after every hidden layer | dl_triangle.py:279 | hard-coded (not exposed as an argument) | not in code | none |
| L2 | `keras.regularizers.l2(2e-3)` on hidden kernels (adds 2e-3 * sum(w^2) to loss; output layer unregularised) | cell 61 L24; cell 69 L30; dl_triangle.py:243, 277 | hard-coded in notebook | not in code | none |
| Normalisation | none (beyond the min-max age scaling) | not in code | n/a | n/a | n/a |
| Initialisation | Keras `Dense` default (Glorot-uniform, zero bias). Offset kernel = Ones | dl_triangle.py:274-289 | library default | n/a | n/a |
| Loss (context) | MSE on z = C_{j+1}/sqrt(C_j) | dl_triangle.py:263, 294 | hard-coded | n/a | n/a |
| Seeds | `tf.keras.utils.set_random_seed(random_state + j)` (Python, NumPy, TF) per transition. `random_state=42` | dl_triangle.py:269; cell 61 L27 | hard-coded | n/a | n/a |
| Min rows for NN / fallback | NN only if >= max(min_train_rows, 10) = 20 training claims, else an empirical CL ratio | dl_triangle.py:245, 260, 321-326; cell 61 L22 | hard-coded in notebook | n/a | n/a |
| Seed ensemble (uncertainty only) | K = 20, seeds 300 + 11k | cell 69 L13, L109-122 | hard-coded | n/a | n/a |
| Bootstrap (uncertainty only) | B = 100 resamples of `claims_cum`, seed 42 | cell 69 L12, L74-88 | hard-coded | n/a | n/a |
| Unused arguments | `lookback_valuations, factor_floor, factor_cap, credibility_k, fallback_safeguard_ratio, include_current_valuation_in_training, use_chain_ladder_guardrail, cl_guardrail_*` appear only in the signature (grep count = 1 each). Docstring: "kept for notebook-call compatibility" | dl_triangle.py:444-465 | dead parameters | n/a | n/a |

### Richman, Scognamiglio & Wüthrich (2025), PIN example

| Hyperparameter | Value in code | Where (file:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| Continuous-feature embedding | each of the 7 continuous inputs goes through `Dense(20)` (linear, no activation) then `Dense(10, tanh)`. d2 = 20, d1 = 10 | 01_a L212-217, L249-250 (`d1 &lt;- c(10)`, `d2 &lt;- c(20)`) | hard-coded ("Select the PIN hyper-parameters" block, L245-257) | not searched | none |
| Categorical embeddings | `layer_embedding(output_dim = 10)` for VehBrand (11 levels) and Region (22 levels). The h5 files confirm (11, 10) and (22, 10) | 01_a L204-210, L249, L257 | hard-coded | not searched | none |
| Interaction token dim | d0 = 10, one token per pair (45 pairs for 9 features). Initializer `'uniform'` | 01_a L152-158, L252 | hard-coded | not searched | none |
| Shared interaction network (depth/width) | input 2*10 + 10 = 30 -> Dense 30 ReLU -> Dense 20 ReLU -> Dense 1 linear -> centred hard sigmoid max(min((1+x)/2, 1), 0). q1 = (30, 20). The h5 files confirm (30, 30), (30, 20), (20, 1) | 01_a L103-116, L140-150, L251 | hard-coded | not searched | none |
| Output layer | Dense(1, **exponential**) on the 45 interaction outputs, multiplied by Exposure | 01_a L221-222 | hard-coded | n/a | n/a |
| Skip/residual | none | not in code | n/a | n/a | n/a |
| Initialisation | Keras defaults, except the output layer, which is initialised to the **null (homogeneous) model**: weights 0, bias log(mu.hom) | 01_a L272-276 | hard-coded (+ library default elsewhere) | n/a | n/a |
| Optimiser / LR | Adam, lr = 0.001 | 01_a L277 | hard-coded | not searched | none |
| LR schedule | `callback_reduce_lr_on_plateau(factor = 0.9, patience = 5, cooldown = 0)`. Monitor = Keras default `val_loss` | 01_a L283 | hard-coded (+ default monitor) | n/a | val Poisson loss |
| Batch size | 128. The stored optimizer counters divide exactly by ceil(549,185/128) = 4,291 steps/epoch, which confirms 128 on 90% of the learning set | 01_a L285 (commented) | hard-coded | not searched | none |
| Epochs | 100, with **no EarlyStopping callback** (the comment at L279 says "define callback for early stopping", but the code defines a checkpoint) | 01_a L279-286 | hard-coded | not searched | none |
| Early stopping (checkpoint selection) | `callback_model_checkpoint(save_best_only = T, save_weights_only = T)` (monitor default `val_loss`). The best-epoch weights are re-loaded (L290). **Best epochs recovered from the shipped checkpoints** (optimizer iterations / 4,291): seed 100: 22, 101: 41, 102: 40, 103: 68, 104: 31, 105: 57, 106: 35, 107: 94, 108: 67, 109: 25 | 01_a L281-282, L290; `Networks/*.h5` `optimizer/vars/0` | hard-coded | n/a | validation Poisson loss |
| Validation split | `validation_split = 0.1` = last 10% of `learn` rows in data order (Keras semantics). The checkpoints' metric state holds count 61,021 = 610,206 - int(0.9 * 610,206). `shuffle = TRUE` for training batches | 01_a L287 (commented) | hard-coded | n/a | n/a |
| Loss (context) | Keras `"poisson"` | 01_a L278 | hard-coded | n/a | n/a |
| Dropout / L1 / L2 / weight decay / normalisation layers | **none**. Inputs standardised (mean/sd) in pre-processing, VehBrand/Region integer-coded | 01_a L49-73 | n/a | n/a | n/a |
| Seeds | `set.seed(seed)` (R) + `set_random_seed(seed)` (keras-R: R, Python, NumPy, TF). Seeds 100-109. GPU disabled (`CUDA_VISIBLE_DEVICES = -1`) | 01_a L16, L196-198, L269 | hard-coded | n/a | n/a |
| Ensemble (nagging) | **T0 = 10** PINs with different seeds, averaged (`learn.PIN += learn\$PIN/T0`). Individual and ensemble in-/out-of-sample Poisson deviances reported | 01_a L262-303, L306-317 | hard-coded | not searched | none (all 10 kept) |

### Van Oirbeek (2026), hgr (no network)

*Not applicable (no NN). For completeness, the only grids and seeds in the package concern **statistical** parameters, not NN hyperparameters*

| Item (not an NN hyperparameter) | Value in code | Where (file:line) | Set how | Search method & space | Selection signal |
|---|---|---|---|---|---|
| NB dispersion kappa profile | 50-point grid over `kappa_range` | R/nbcl.R:525, 541-556 | function default | profile-likelihood grid | NB log-likelihood (CI from profile) |
| UCR simulation tau^2 | `c(0, 1e-4, 5e-4, 1e-3, 2e-3, 5e-3, 1e-2, 2e-2)` | R/ucr.R:916 | function default | simulation-design grid (not tuning) | n/a |
| CNBG posterior grid | `n_grid = 600` log-spaced kappa points | R/cnbg.R:262, 287 | function default | quadrature grid | posterior |
| Seeds | `set.seed(seed)` if supplied (nbcl.R:363; ucr.R:845); Stan `seed = 2026L` (cnbg.R:864) | as cited | argument / default | n/a | n/a |

### Gabrielli (2019) NNDODP notebook (third-party re-run)

| Hyperparameter | Value in code | Where (cell:line) | Set how | Search method & space if searched | Selection signal |
|---|---|---|---|---|---|
| Depth | K = 2 hidden layers in each of the two FNNs (counts FNN and payout-attention FNN) | cell 16 L36-40, L101-105 | hard-coded | paper: K = 2 fixed by argument ("an additional hidden layer may facilitate learning of interactions", p.9). Not searched | none |
| Width (q1, q2) | (40, 30) in both FNNs | cell 16 L38, L40, L103, L105 (cell 24 same) | hard-coded | **paper, not in code:** grid q1, q2 in {20, 25, ..., 80} with q1 > q2, i.e. **78 models**, each trained 1,000 epochs (p.25) | **paper:** smallest *average* validation claim-amounts Poisson loss (21-epoch moving average) on a 50/50 claim-level train/validation split per LoB x AY (pp.17, 25). Top-3: (40, 30) 1193.6; (80, 50) 1193.7; (25, 20) 1194.4 (Table 10, p.25) |
| Activation | tanh (hidden); linear (claim-count layer, attention layer); exponential (outputs, frozen) | cell 16 L38-45, L77, L103-108, L137 | hard-coded | paper p.9 gives reasons for tanh | none |
| Embeddings | **frozen** (trainable = FALSE) ccODP parameters: AY/DY embeddings of dim 6 (one column per LoB) for N and Y, LoB one-hot of dim 6. Input to FNNs = 30 | cell 16 L11-34 | hard-coded (from ccODP GLM fits, cell 11) | n/a | n/a |
| Skip connections | ccODP predictor added to the NN output via frozen dense layers (`add_N1`, `response_Y` layer_add) | cell 16 L55-78, L119-138 | hard-coded | n/a | n/a |
| Initialisation | trainable output layers initialised to **zero** weights/bias, so the NN starts **exactly at ccODP**. Attention layer bias = 1 (weights 0). Other layers use Keras defaults | cell 16 L44-45, L107-108, L116-117 | hard-coded | n/a | n/a |
| Batch normalisation | `layer_batch_normalization()` on the ordered claim-counts layer before the attention product (Keras defaults) | cell 16 L98-99 | hard-coded | n/a | n/a |
| Dropout | 0.2 (after dense 40 and before each linear output layer) | cell 16 L39, L43, L104, L106, L115 | hard-coded | not searched (paper p.9: "constant dropout rate of 20%") | none |
| L2 | `regularizer_l2(l = 0.001)` on all trainable dense kernels | cell 16 L38, L40, L45, L103, L105, L107, L117 | hard-coded | not searched (paper p.9: "regularization parameter given by 0.001") | none |
| Optimiser / LR | `optimizer_rmsprop()`, Keras-R default lr = 0.001 | cell 16 L141 | hard-coded + library default LR | not searched | none |
| Batch size | full batch: `batch_size = length(x.upper[[1]])` = 6 LoBs x 78 upper-triangle cells = 468 | cell 18 L6; cell 19 L15; cell 26 L13, L25 | hard-coded | not searched | none |
| Epochs | 390 + 20 = 410. Predictions are **averaged over the 21 weight snapshots at epochs 390, 391, ..., 410** ("epochs &lt;- 390 # number of epochs - epochs.cont/2"; `epochs.cont &lt;- 20 # for averaging`) | cell 18 L1-3; cell 25 L1-2; cell 19 L5-15; cell 26 L39-61 | hard-coded (cell 18 comment: "values derived in [4] using train-validation-split") | **paper, not in code:** "ideal number of epochs" per LoB read from validation curves over 1,000 epochs (Table 11, p.25: LoB 1-6 = 500, 500, 0, 300, 1,000, 100). Average = **400** used for all LoBs | paper: validation claim-amounts loss per LoB (Figure 7) |
| Early stopping | none as a callback. "Early stopping" = a fixed epoch count (paper p.16: "we apply early stopping to prevent from over-fitting ... The number of gradient descent steps ... has to be chosen very carefully") | cell 18, 25 | hard-coded | see epochs | see epochs |
| Epoch-snapshot averaging (ensemble-like) | 21 snapshots, each checkpointed by `callback_model_checkpoint(save_weights_only = TRUE)` every epoch | cell 19 L4-15; cell 26 L16-25, L39-57 | hard-coded | n/a | n/a |
| Seeds | **none.** No `set.seed`, `use_session_with_seed`, `set_random_seed` or `tensorflow::set_random_seed` anywhere (regex over all 39 cells) | not in code | n/a | n/a | n/a |
| Repeated runs / ensemble | `nnn &lt;- 100` independent re-fits of `build_model()` (unseeded), each with 21-epoch averaging. Mean/sd of reserves by LoB reported, plus the cumulative mean bias vs number of nets (cells 28-36). Notebook conclusion (cell 37): "It does not seem necessary to calculate and average 100 models to obtain stable results." | cell 23 L1; cell 26 L8-66; cell 36 | hard-coded | n/a | n/a |
| Validation data | **none in the notebook.** It trains on the full upper triangle (`x.upper`, cell 14 L6-12) | not in code | n/a | n/a | n/a |

# Appendix B – Verification log

**Quotations inserted by the build script** (every quotation in Sections 1–10 that carries a page reference):

| Source | Quotations | Check | Result |
|---|---|---|---|
| Papers, theses and books in the folder | 371 from 54 documents | whitespace-normalised exact substring of the PDF text layer; page containing the match compared with the PDF page cited | all found; 363 on the cited PDF page, 8 cited by EPUB section (Gridin) or by code location, which have no PDF page |
| [WM] | 81 | exact substring of the book text; printed page taken from the page-marker lines of the text | all found on the cited printed page |
| [AIT] | 86 | as above | all found on the cited printed page |
| [GBC] | 109 | as above (one pair of pages, 426–427, has no detectable page foot; quotes there are accepted if the cited page is in that pair) | all found on the cited printed page |
| [H] | 35 | as above | all found on the cited printed page |
| **Total** | **682** (565 distinct) | | **0 failures** |

Two textbook symbols are lost in the text layer of [GBC] (the learning-rate symbol $\epsilon$ and $m'$); where a quotation contains them, the text on either side of the symbol was checked and the symbol is printed as in the book.

**Other quoted strings.** The document contains 264 further strings in quotation marks that were not inserted by the script, most of them inside the Appendix A extraction tables. Each was searched in all paper texts, the four textbooks and the shipped code: 228 were found verbatim. The remaining 36 were inspected one by one. They are the document's own title, subtitle and author line (3); stretches of text *between* two genuine quotations that the scanner paired by mistake (6); quotations that the extraction pass shortened with an ellipsis ("…" or "..."), or that run across a page break (15); paper titles and one PDF metadata title (10); and short phrase-level labels written by the extraction pass rather than quoted from a source (2). None of them is presented in Sections 1–10 as a verbatim quotation with a page reference.

**What was not checked automatically.** Values that the extraction read from table or figure images (marked in Appendix A), the page offsets in the table of Section 1 (carried over from the 17 September explainers), and the R/keras3 skeletons of Section 9, which were not executed.
