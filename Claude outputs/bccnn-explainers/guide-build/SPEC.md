# Specification: rewriting a bCCNN explainer to the Stellenbosch Honours Research Assignment Guide

You rewrite ONE existing explainer (Markdown with LaTeX maths) into a new Markdown source that a converter turns into a Word document on the department template. Keep ALL technical content (every formula, derivation, table, figure, number, code reference). Change structure, wording style, numbering mechanics and citations as below. Do not invent results. Do not drop material.

Working directory: /tmp/claude-0/-home-user-Masters-Research-R/1cd9441d-4075-5511-a8f5-fb2214f015b5/scratchpad/hons
Inputs:
- The explainer to convert: ../docs/<name>.md (given in your task).
- The other three explainers (read them only to resolve cross-references to their OLD section/equation/table/figure numbers): ../docs/claude_explainer-bccnn-*.md. Their ids: d1 = mathematics-model-and-ccodp-start, d2 = fitting-procedure-and-training, d3 = as-a-whole-interpretation-evaluation-uncertainty, d4 = time-aware-rolling-origin-split.
- Härkönen thesis text with printed page numbers: harkonen_paged.txt (cite by PRINTED page number).
- Literature notes with Paper C and Al-Mudafer quotations and their PDF page numbers: /home/user/Masters-Research-R/thesis/Hyperparameter search (grep it; e.g. "Gabrielli et al. 2018, PDF p. 11, §3.3.1").
- The guide itself: guide.md (Chapter 5 and Appendix D are the rules).
Output: src/<docid>.md (UTF-8). Nothing else.

## 1. Front matter (YAML + three blocks at the top of the file)

```
---
docid: d1
title: "THE MATHEMATICS BEHIND THE bCCNN"          # short main title, UPPER CASE except the model name bCCNN/ccODP
subtitle: "The ccODP model, the network and its chain-ladder start"   # sentence case
---

::: abstract
One to three paragraphs, at most 300 words, third person, no citations of section numbers, no maths display.
:::

::: keywords
Five to ten key words separated by semicolons, sentence case, e.g.: Claims reserving; Chain ladder; Over-dispersed Poisson model; Neural networks; ...
:::

::: abbreviations
| Abbreviation | Meaning |
|:--|:--|
| bCCNN | Blended cross-classified neural network |
...alphabetical, every abbreviation used in the document (CL, ccODP, MLE, IWLS, LoB, RMSprop, ...)
:::
```

## 2. Chapters and headings

- `# Title {#d1-chN}` = chapter (Heading 1). Write the title in UPPER CASE (e.g. `# THE CROSS-CLASSIFIED OVER-DISPERSED POISSON MODEL {#d1-ch2}`). Do NOT type "CHAPTER 2"; Word numbers it.
- `## Title {#id}` = X.Y heading. Sentence case (Word shows it in capitals by itself). E.g. `## Introduction {#d1-ch2-intro}`.
- `### Title {#id}` = X.Y.Z heading, sentence case, no initial capitals on every word.
- `#### Title {#id}` = X.Y.Z.W heading (bold italic), only if needed.
- Never type numbers in headings. Never skip a level. No text directly under a chapter heading: every chapter starts with `## Introduction` (what the chapter does and how it links to the previous one) and ends with `## Summary` (main messages, link to the next chapter). Exception: the first chapter (INTRODUCTION) needs no summary; the LAST chapter ends with `## Summary and conclusions` instead.
- Give EVERY heading an id. For a heading that corresponds to an OLD section of the source, the id MUST be `{#<docid>-s<oldnumber>}`, e.g. old "3.9 Periods without payments" becomes `### Periods without payments {#d1-s3.9}` (whatever its new level). Old top-level section 7 becomes `{#d1-s7}`. New headings (introductions, summaries, merged parents) get free ids like `{#d1-ch2-intro}`.
- The chapter plan for your document is given in your task. Follow it.
- At most four heading levels; do not use headings for single short paragraphs.

## 3. Equations

- Every display equation that had `\tag{k}` in the source: remove the `\tag{k}` and put on the line DIRECTLY after the closing `$$` a marker line `⟦eq:<docid>-eq<k>⟧` (k = the OLD number), e.g.
  ```
  $$
  D(\boldsymbol y, \boldsymbol\mu; \mathcal S) = 2 \sum ...
  $$
  ⟦eq:d1-eq7⟧
  ```
  The converter numbers it (chapter.n) at the right margin in the template's two-column layout.
- Keep `\begin{aligned} ... \end{aligned}` blocks (one tag per block = one marker). Keep every display within about 14 cm: break long ones with aligned.
- Displays without a tag stay unnumbered (intermediate steps are not numbered in the guide; do not add numbers to intermediate steps).
- No `$$` inside list items or tables. Inline maths `$...$` stays.
- Referring to an equation of THIS or another explainer: write `⟦ref:<docid>-eq<k>⟧` (old number k); it becomes "(2.7)". NEVER write the words "equation", "eq." or "eqs." before your own equations (guide 5.8: "Using (5.3), it can be shown..."). For another explainer: "(3.12) of companion I" is written `⟦ref:d1-eq27⟧ of companion I`. Equations of external papers keep their own wording, e.g. "Paper C's equation (13)" (that is a paper's number, not a token).

## 4. Tables and figures

- Table: the caption line comes immediately BEFORE the pipe table as a marker paragraph, then a blank line, then the table:
  `⟦tabcap:d1-tab3|Results of the numerical check (amounts in millions of the synthetic data)⟧`
  Old "Table k" captions below tables are removed and become these markers; use id `<docid>-tab<k>` with the OLD number k (new tables: `<docid>-tabnew1`, ...). The caption text is sentence case, no full stop, no "Table 3:" prefix.
- Every table needs a header row with a heading for each column. Numbers: consistent decimals per column, right-aligned columns (`--:`). Thousands separated by a no-break space (U+00A0): 3 047, 10 000 (not 3,047 / 3{,}047). No bold in cells (the converter makes the header row bold). Keep tables reasonable in width (they become 16.5 cm wide, 10 pt). If a source table only stated a table "Source", add after the table `⟦tabsource|Source: ...⟧`; tables of your own computations need no source line.
- Figure: an image paragraph WITHOUT caption text, followed by the caption marker:
  ```
  ![](figures/claims_split.png){width=16.5cm}

  ⟦figcap:d2-fig1|The claims split and the early-stopping run built on it⟧
  ```
  Figure ids `<docid>-fig<k>` with the OLD order number k of figures in the source (first image = 1). Put any longer explanation that was in the old caption into the body text just before or after the figure.
- References in the text: "Table ⟦ref:d1-tab3⟧", "Figure ⟦ref:d2-fig1⟧", "Section ⟦ref:d1-s3.9⟧", "Chapter ⟦ref:d1-ch2⟧" (gives just the number). Capital T/F/S/C. Use tokens for EVERY internal or cross-document reference to a section, table, figure, chapter or equation; never type a bare number.
- Other explainers are cited as "companion I" (d1), "companion II" (d2), "companion III" (d3), "companion IV" (d4), defined once in Chapter 1 with their full titles. Example: "(companion I, Section ⟦ref:d1-s3.9⟧)".

## 5. Lists

- Bullet lists: `- ` items, one level only (no nesting), each item starts with a capital letter and ends with a semicolon or full stop; the last ends with a full stop (guide 5.4). Keep lists few; turn long bullet paragraphs into ordinary paragraphs where reasonable.
- Numbered lists (steps): `1. ` items; they become i), ii), iii).
- No bold lead-ins in bullets or paragraphs (the guide asks for very limited bold). If a lead-in label is needed use italics: `*Statement.*`. Prefer turning recurring lead-ins ("Property 1", "Statement/Proof") into `###`/`####` headings or italic lead-ins.

## 6. Language (guide 5.2, 5.3, 5.10)

- Third person throughout. No "you", "your", "I", "we", "our". Replace "your code" with "the code" or "the code in the repository"; "your hyperparameter notes" with "the literature notes in the repository (thesis/Hyperparameter search)"; "your portfolio" with "the simulated portfolio"; "I have not re-read..." with "These notes have not re-checked...". 
- South African/British spelling: -ise (optimise, regularise, minimise, initialise, standardise, normalise), behaviour, colour, favour, modelling, labelled, centre (not center), programme (not program, except computer program). Keep code names and quotations unchanged.
- No contractions; no "etc."; no informal words ("get", "a lot").
- Dashes in sentences: en dash with spaces " – ". No dashes in headings. Page ranges with hyphen, no spaces: (Härkönen, 2021: 27-28).
- Abbreviations: write out in full at first use in the BODY (Chapter 1) with the abbreviation in brackets, then use only the abbreviation; all listed in the abbreviations block.
- Concepts/terms in single quotation marks ('chain-ladder start'); direct quotations in double quotation marks with a page reference.
- Numbers: decimal point; thousands with a no-break space (U+00A0) in text, tables and maths (in maths write `3\ 047` or `10\ 000`); years, seeds (2026), code values in backticks and identifiers are not split. Dates like 6 October 2026 fine.
- Code identifiers stay in backticks.

## 7. Citations (Harvard, Stellenbosch "Make sense of referencing")

- In text: Härkönen (2021), (Härkönen, 2021: 33) with page for quotes/specific claims; Mack (1993); two authors: England and Verrall (2002); three or more: ALL surnames the FIRST time (Gabrielli, Richman and Wüthrich, 2020; Al-Mudafer, Avanzi, Taylor and Wong, 2021), afterwards first author + *et al.* in italics: Gabrielli *et al.* (2020). "et al." is always italic and plural ("Al-Mudafer *et al.* use").
- "Paper C" may be kept as the label used in the code, defined at first use: "Gabrielli, Richman and Wüthrich (2020), referred to as Paper C as in the code". Quotations of Paper C come from the SSRN version (the literature notes cite "Gabrielli et al. 2018, PDF p."): cite them as (Gabrielli *et al.*, 2018: 11) and list BOTH versions in the References. Al-Mudafer quotations: (Al-Mudafer *et al.*, 2021: 10) using the notes' PDF page.
- Härkönen quotations: verify every quote against harkonen_paged.txt and give the printed page.
- The references block at the end: `# REFERENCES {.references}` then one paragraph per source, alphabetical, only sources cited in the text, all sources cited are listed. Format:
  Gabrielli, A., Richman, R. & Wüthrich, M.V. 2020. Neural network embedding of the over-dispersed Poisson reserving model. *Scandinavian Actuarial Journal*, 2020(1):1-29.
  Goodfellow, I., Bengio, Y. & Courville, A. 2016. *Deep learning*. Cambridge, MA: MIT Press.
  Härkönen, V. 2021. On claims reserving with machine learning techniques. Unpublished master's thesis. Stockholm: Stockholm University.
  Al-Mudafer, M.T., Avanzi, B., Taylor, G. & Wong, B. 2021. Stochastic loss reserving with mixture density neural networks. arXiv preprint 2108.07924.
  Gabrielli, A., Richman, R. & Wüthrich, M.V. 2018. Neural network embedding of the over-dispersed Poisson reserving model. SSRN working paper 3288454, version of 21 November 2018.
  (Journal and book titles italic; article titles sentence case, plain.)

## 8. Appendix

After REFERENCES: `# LIST OF SYMBOLS {.appendix #<docid>-appA}` containing the old "Notation used in this document" table as a captioned table `⟦tabcap:<docid>-tabnotation|Symbols used in this report⟧` with a third column giving the new Section via tokens if the old table had a Section column (map old section k to `⟦ref:<docid>-s<k>⟧`). The guide asks for symbols to be summarised in an appendix. Add one short introductory sentence above the table. Remove the old notation section from the front.

## 9. Things to remove or move

- Remove "Prepared for Francis", dates in the subtitle, and the HTML-specific details. Remove the old "Notation used in this document" section (moved to the appendix) and the old "Abbreviations:" paragraph (moved to the abbreviations block). Keep a short paragraph in Chapter 1 saying how the mathematics was checked.
- Chapter 1 must contain the guide's elements where meaningful for an explanatory text: introduction (what is explained and why), the question addressed, scope and limitations (for example: Paper C quoted through the literature notes; synthetic check data; no Keras run), the approach used to verify the mathematics, and the plan of the document (chapter outline using ⟦ref:...-chN⟧ tokens).

## 10. Self-check before finishing

grep your output for: "you", "your", " I ", " we ", "eq.", "Eq.", "\tag", "**", "etc", American -ize words, "\d,\d\d\d", "Table [0-9]", "Figure [0-9]", "Section [0-9]", "(\d+)" bare own-equation references. Every ⟦ref:...⟧ id must exist as a heading id, ⟦eq:...⟧, ⟦tabcap:...⟧ or ⟦figcap:...⟧ in the target document (for cross-document refs, in that document's OLD numbering: the other agents use the same id scheme `<docid>-s<old section>`, `<docid>-eq<old tag>`, `<docid>-tab<old table no.>`, `<docid>-fig<old figure order>`). Report at the end: chapter titles, number of equations, tables, figures, and any content you were unsure about.
