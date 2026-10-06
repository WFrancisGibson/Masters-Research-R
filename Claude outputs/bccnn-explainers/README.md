# bCCNN explainers: numerical checks and build tooling

Four explainers in `thesis/`:

| file | covers |
|:--|:--|
| `claude_explainer-bccnn-mathematics-model-and-ccodp-start.{md,pdf}` | the ccODP model and its chain-ladder equivalence (with proof), the network of `bccnn_model()`, the Keras loss, the gradients, the three properties of the ccODP start |
| `claude_explainer-bccnn-fitting-procedure-and-training.{md,pdf}` | the data parts, Paper C's 50/50 claims split, RMSprop, early stopping, the refit, the outputs, the procedure in Paper C / Härkönen / Al-Mudafer et al. vs the code |
| `claude_explainer-bccnn-time-aware-rolling-origin-split.{md,pdf}` | `rolling_origin_sets()` cell by cell, its guarantees, the out-of-time scoring and the test error (4.4) |
| `claude_explainer-bccnn-as-a-whole-interpretation-evaluation-uncertainty.{md,pdf}` | what the bCCNN estimates, early stopping as shrinkage, how the reserve is judged, MSEP / bootstrap / nagging for the bCCNN |

Figures used by the four documents are in `thesis/figures/bccnn-explainers/`.

## Numerical checks (Python, no Keras, no R)

* `bccnn_check.py` re-implements `fit_odp_glm()` (IWLS), `bccnn_model()` / `fit_bccnn()` (forward pass, back-propagation, Keras RMSprop, inverted dropout) in numpy on a synthetic 20 x 20 triangle, and checks: chain-ladder equivalence, marginal totals, the unit of the payments, parameter counts, the start property, analytic gradients vs finite differences, the Keras loss / deviance identity, the first RMSprop step, a toy early-stopping run on two claims halves, the refit, and (optionally) a parametric bootstrap and a seed study.
  Environment variables: `GAMMA`, `JCUT` (interaction the ccODP cannot represent), `PHI`, `MU11`, `MAXEP`, `BOOT` (bootstrap replicates), `SEEDS` (seed study), `OUTDIR`.
  The run used in the documents: `GAMMA=0.004 JCUT=12 PHI=0.3 MAXEP=3000 MU11=100 BOOT=20 SEEDS=10 python3 bccnn_check.py` (the formula checks of document 1 use the defaults). Writes `results.json` and `figures/*.png`. The JSON files kept here are: `results_formula-checks_default.json` (defaults; the numbers of document 1, Section 11), `results_toy-run_bootstrap-seeds.json` (the run above with `BOOT=20 SEEDS=10`; documents 2 and 3), `results_toy-run_figures.json` (the same run without bootstrap, used for the heat map), `rolling_origin_counts.json` (document 4, Table 1).
* `rolling_origin_check.py` replicates `rolling_origin_sets()` for the `config.yml` values (n = 20, test_periods c(5, 2), vali_periods 2, exclude 2), prints the cell counts and guarantees (`rolling_origin.json`), and draws the partition tiles, the calendar-diagonal figure, the claims-split schematic and the network diagram.

Requirements: `python3 -m pip install numpy matplotlib`.

## Building the PDFs

`build.sh in.md out.pdf` runs pandoc (Markdown + LaTeX math -> HTML with KaTeX) and prints the HTML to PDF with headless Chromium through Playwright (`render.js`); `style.css` is the page style. It needs `pandoc`, `node` with the `playwright` package and a Chromium it can launch, and a local copy of KaTeX (`npm install katex@0.16.11` next to `build.sh`, so that `node_modules/katex/dist/` exists). Run it from the directory of the `.md` file so that `figures/...` resolves (in `thesis/` the images are under `figures/bccnn-explainers/`). The renderer lays the page out at the printable width and prints a list of any element wider than the page: Chromium would otherwise shrink the whole document to fit the widest element, so a long display equation must be broken into an `aligned` block until the report says `no overflow`.

## Editable Word diagram of the network

`thesis/figures/bccnn-explainers/bccnn_network_diagram.docx` holds the network figure as native Word shapes in one group (11 boxes, 12 arrows, a legend), with the maths typed as text (italics, sub- and superscripts), so every label, colour and position can be edited in Word. It is not a SmartArt object: SmartArt layouts are fixed lists, processes, hierarchies and cycles, none of which can hold two merging branches plus a skip connection.

Rebuild: `node word-diagram/base.js` (landscape page, title, caption, placeholder), unzip `base.docx`, `python3 word-diagram/make_diagram.py unpacked/word/document.xml` (box positions, texts and arrow routes are the lists at the top of the script), zip again.
