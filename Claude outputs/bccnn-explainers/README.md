# bCCNN explainers: sources, checks and build tooling

The four explainers are in `thesis/`, as Word documents on the Department template with a PDF of each. They follow the Research Assignment Guide (Department of Statistics and Actuarial Science, 2026), Chapter 5 and Appendix D.

| Companion | Files in `thesis/` | Covers |
|:--|:--|:--|
| I | `claude_explainer-bccnn-mathematics-model-and-ccodp-start.{docx,pdf}` | The ccODP model and the proof that it is the chain ladder; the network of `bccnn_model()`; the Keras loss; the gradients; the three properties of the ccODP start. |
| II | `claude_explainer-bccnn-fitting-procedure-and-training.{docx,pdf}` | The data parts; the 50/50 claims split; RMSprop; early stopping; the refit; the outputs; the procedure in Paper C, Härkönen and Al-Mudafer *et al.* against the code. |
| III | `claude_explainer-bccnn-as-a-whole-interpretation-evaluation-uncertainty.{docx,pdf}` | What the bCCNN estimates; early stopping as shrinkage towards the chain ladder; how the reserve is judged; MSEP, bootstrap and nagging. |
| IV | `claude_explainer-bccnn-time-aware-rolling-origin-split.{docx,pdf}` | `rolling_origin_sets()` cell by cell; its guarantees and cell counts; out-of-time scoring and the test error. |

`thesis/figures/bccnn-explainers/` holds two editable figures, both laid out to the Guide:

- `bccnn_network_diagram.docx` is Figure 3.1 of companion I, drawn as Word shapes.
- `rolling_origin_partitions.docx` is Figure 2.2 of companion IV, drawn as Word tables.

The same folder holds the chart images.

The explainers were prepared with the generative AI tool Claude as study material. Each says so on its title page and in its opening note. Section 2.6.3 of the Guide does not allow AI-generated content in work submitted for assessment, so the plagiarism and AI-use declarations of the template are left out.

## What the formatting follows

- **Page, font and spacing.** A4, with margins of 25 mm on the left and 20 mm elsewhere, so the text is 16.5 cm wide. Body text is Cambria 11 pt, justified, with 1.5 line spacing and no indents.
- **Page numbers.** Page numbers are centred at the top. The front pages use Roman numerals, with none shown on the title page; Chapter 1 starts at page 1.
- **Front pages.** Title page, note on preparation, abstract with key words, table of contents, list of tables, list of figures, and list of abbreviations.
- **Chapters.** Chapters are headed "CHAPTER n" and the title, centred, 14 pt and bold. Each chapter opens with an introduction and closes with a summary.
- **Headings and lists.** Headings are numbered 1.1 (upper case), 1.1.1 and 1.1.1.1. Bullets use the template styles; numbered steps run i), ii), iii).
- **Equations.** Equations are numbered (chapter.n) at the right margin, in the template's two-column layout. They are referred to as "(2.7)" without the word "equation".
- **Tables.** Tables are 16.5 cm wide and centred, with the caption above and 10 pt text. Headers are bold, numbers are right-aligned, and thousands are separated by spaces. The header row repeats when a table runs over a page.
- **Figures.** The caption sits below the figure. Charts are redrawn in Caladea, which has the same metrics as Cambria, at text width with labelled axes.
- **Language and citations.** Writing is in the third person with UK spelling. Citations are Harvard, with pages for quotations and *et al.* in italics. The References list is alphabetical, followed by the list of symbols as Appendix A.

## Numerical checks (Python, no Keras or R)

- `bccnn_check.py` re-implements `fit_odp_glm()` and the bCCNN in numpy: the IWLS fit, the forward and backward pass, Keras's RMSprop and dropout. It checks every formula of companion I. It also runs the toy early-stopping example and the refit, and, when asked, a bootstrap and a seed study.
  - Environment variables: `GAMMA`, `JCUT`, `PHI`, `MU11`, `MAXEP`, `BOOT`, `SEEDS`, `OUTDIR`.
  - The run used in companions II and III is `GAMMA=0.004 JCUT=12 PHI=0.3 MAXEP=3000 MU11=100 BOOT=20 SEEDS=10`.
  - `bccnn_check_guide.py` is the same script with the figure style of the Guide.
- `rolling_origin_check.py` replicates `rolling_origin_sets()` for the values in `config.yml` and draws the calendar-diagonal figure and the claims-split schematic. `rolling_origin_check_guide.py` is its Guide-style version.
- The `results_*.json` and `rolling_origin_counts.json` files hold the numbers quoted in the explainers.

## Rebuilding the documents (`guide-build/`)

- **Sources.** `src/d1.md` to `src/d4.md` hold the text, with tokens for cross-references, equation numbers and captions. `SPEC.md` describes them.
- **Template.** `template/template.docx` is the Department template.

```
cd guide-build
python3 tools/resolve.py            # numbers chapters, sections, equations, tables, figures across d1..d4
python3 tools/build.py d1 d2 d3 d4  # pandoc on the template, then the Guide formatting -> out/dX.docx
python3 tools/lo_export.py out/d1.docx out/d2.docx out/d3.docx out/d4.docx   # update fields, export PDF
```

Requirements:

- pandoc 3.1;
- Python 3 with lxml;
- for the PDFs, LibreOffice with its Math component and Python UNO (`libreoffice-math`, `python3-uno`), plus the Caladea and Carlito fonts (`fonts-crosextra-caladea`, `fonts-crosextra-carlito`).

`build/fig_network.md` and `build/fig_partitions.md` hold the two standalone figure files. To build one, write `{"meta": {}}` to `build/<name>.json` and run `python3 tools/build.py <name>`.

`build.py` rewrites a few equation constructs that LibreOffice cannot import. These are a leading relation symbol, empty cells in `aligned` blocks, a bare `*` or `|`, `\underbrace`, and brackets inside `\text{}`. Each rewrite leaves Word's rendering unchanged or improves it.

`tools/mathprobe2.py dX` renders every formula of `out/dX.docx` on its own page in LibreOffice and lists any that fail. The current documents have none.

Word refreshes the table of contents and the lists of tables and figures when a document is opened, and asks before doing so. Answer Yes.
