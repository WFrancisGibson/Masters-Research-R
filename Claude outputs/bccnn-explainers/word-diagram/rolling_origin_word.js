// Editable Word version of the rolling-origin partition figure: one 20 x 20
// Word table per partition (a cell = an accident/development period cell,
// its shading = its role), side by side in a borderless outer table.
// Roles follow rolling_origin_sets() in R/triangles.R for config.yml:
// n = 20, test_periods = c(5, 2), vali_periods = 2, exclude = 2.
const fs = require('fs');
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType, ShadingType,
        BorderStyle, HeightRule, TableLayoutType, VerticalAlign, AlignmentType, PageOrientation,
        HeadingLevel } = require('docx');

const n = 20, TEST = [5, 2], V = 2, E = 2;
const rround = x => { const f = Math.floor(x), d = x - f;            // R round(): half to even
  if (Math.abs(d - 0.5) < 1e-12) return (f % 2 === 0) ? f : f + 1; return Math.round(x); };

function partition(tau) {
  // role[i][j] for 1-based i, j in 1..n
  const role = Array.from({ length: n + 1 }, () => Array(n + 1).fill(null));
  for (let i = 1; i <= n; i++) for (let j = 1; j <= n; j++) {
    const k = i + j - 1;
    if (k > n) role[i][j] = 'future';
    else if (i > tau || j > tau) role[i][j] = 'outside';
    else if (k > tau) role[i][j] = 'test';
    else role[i][j] = (k > tau - V && i > E && j > E) ? 'validation' : 'train';
  }
  const K = V * (E - 1), lo = E + 1, hi = tau - V - E + 1;
  for (let m = 1; m <= K; m++) {
    const r = rround(lo + (hi - lo) * (m - 0.5) / K);
    const devs = []; for (let d = E; d >= 2; d--) devs.push(d);
    role[r][devs[(m - 1) % devs.length]] = 'validation';
  }
  return role;
}

const STYLE = {
  train:      { fill: '4DAF4A', type: ShadingType.CLEAR },
  validation: { fill: '1B5E20', type: ShadingType.CLEAR },
  test:       { fill: 'E41A1C', type: ShadingType.CLEAR },
  outside:    { fill: 'DDE7F0', type: ShadingType.THIN_DIAGONAL_STRIPE, color: '9FB0C2' },
  future:     { fill: 'F0F0F0', type: ShadingType.CLEAR },
};
const CELL = 215, LAB = 300;                  // DXA: grid cell, axis-label column
const thin = (c) => ({ style: BorderStyle.SINGLE, size: 2, color: c });
const thick = { style: BorderStyle.SINGLE, size: 12, color: '000000' };
const none = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
const small = (t, sz = 11, opts = {}) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 0, after: 0, line: 160, lineRule: 'exact' },
  children: [new TextRun({ text: t, size: sz, font: 'Calibri', ...opts })] });
const ticks = new Set([1, 5, 10, 15, 20]);

function grid(tau) {
  const role = partition(tau);
  const counts = { train: 0, validation: 0, test: 0 };
  const rows = [];
  // header row: development periods
  rows.push(new TableRow({ height: { value: CELL, rule: HeightRule.EXACT }, children:
    [new TableCell({ width: { size: LAB, type: WidthType.DXA }, borders: { top: none, bottom: none, left: none, right: none }, children: [small('')] })]
    .concat(Array.from({ length: n }, (_, c) => new TableCell({ width: { size: CELL, type: WidthType.DXA },
      borders: { top: none, bottom: none, left: none, right: none }, verticalAlign: VerticalAlign.BOTTOM,
      margins: { top: 0, bottom: 0, left: 0, right: 0 }, children: [small(ticks.has(c + 1) ? String(c + 1) : '')] }))) }));
  for (let i = 1; i <= n; i++) {
    const cells = [new TableCell({ width: { size: LAB, type: WidthType.DXA }, borders: { top: none, bottom: none, left: none, right: none },
      verticalAlign: VerticalAlign.CENTER, margins: { top: 0, bottom: 0, left: 0, right: 40 },
      children: [new Paragraph({ alignment: AlignmentType.RIGHT, spacing: { before: 0, after: 0, line: 160, lineRule: 'exact' },
        children: [new TextRun({ text: ticks.has(i) ? String(i) : '', size: 11, font: 'Calibri' })] })] })];
    for (let j = 1; j <= n; j++) {
      const r = role[i][j]; if (counts[r] !== undefined) counts[r]++;
      const st = STYLE[r];
      const line = r === 'future' || r === 'outside' ? 'D9D9D9' : 'FFFFFF';
      const b = { top: thin(line), bottom: thin(line), left: thin(line), right: thin(line) };
      // black outline of the partition's tau x tau square
      if (i <= tau && j <= tau) {
        if (i === 1) b.top = thick; if (i === tau) b.bottom = thick;
        if (j === 1) b.left = thick; if (j === tau) b.right = thick;
      }
      cells.push(new TableCell({ width: { size: CELL, type: WidthType.DXA }, borders: b,
        shading: { fill: st.fill, type: st.type, color: st.color || 'auto' },
        margins: { top: 0, bottom: 0, left: 0, right: 0 }, children: [small('', 2)] }));
    }
    rows.push(new TableRow({ height: { value: CELL, rule: HeightRule.EXACT }, children: cells }));
  }
  const table = new Table({ layout: TableLayoutType.FIXED, width: { size: LAB + n * CELL, type: WidthType.DXA },
    columnWidths: [LAB].concat(Array(n).fill(CELL)), rows, alignment: AlignmentType.CENTER });
  return { table, counts };
}

const parts = [[n - TEST[0], 'Test partition 1: valuation year 15'],
               [n - TEST[1], 'Test partition 2: valuation year 18'],
               [n, 'Final partition: valuation year 20 (no test set)']];
const built = parts.map(([tau]) => grid(tau));
built.forEach((b, k) => console.log(parts[k][1], JSON.stringify(b.counts)));

const OUT = 5040, nob = { top: none, bottom: none, left: none, right: none };
const p = (runs, o = {}) => new Paragraph({ spacing: { before: 0, after: 60 }, ...o,
  children: runs.map(r => typeof r === 'string' ? new TextRun({ text: r, font: 'Calibri', size: 18 }) : new TextRun({ font: 'Calibri', size: 18, ...r })) });
const outer = new Table({ layout: TableLayoutType.FIXED, width: { size: 3 * OUT, type: WidthType.DXA }, columnWidths: [OUT, OUT, OUT],
  borders: { top: none, bottom: none, left: none, right: none, insideHorizontal: none, insideVertical: none },
  rows: [new TableRow({ children: built.map((b, k) => new TableCell({ width: { size: OUT, type: WidthType.DXA }, borders: nob,
    children: [p([{ text: parts[k][1], bold: true, size: 18 }], { alignment: AlignmentType.CENTER, spacing: { after: 40 } }),
               p(['development period ', { text: 'j', italics: true }, ' →'], { alignment: AlignmentType.CENTER, spacing: { after: 20 } }),
               b.table,
               p(['rows: accident period ', { text: 'i', italics: true }, ', 1 at the top'], { alignment: AlignmentType.CENTER, spacing: { before: 40, after: 0 } })] })) })] });

// legend: swatch cells and labels
const LEG = [['train', 'training cells'], ['validation', 'validation cells'], ['test', 'test cells (held-out calendar years)'],
             ['outside', 'observed at year 20, outside the partition’s square (unused)'], ['future', 'future cells (never used)']];
const sw = 260, lab = [1500, 1500, 2700, 4300, 1900];
const legend = new Table({ layout: TableLayoutType.FIXED, alignment: AlignmentType.CENTER,
  width: { size: LEG.length * sw + lab.reduce((a, b) => a + b, 0), type: WidthType.DXA },
  columnWidths: LEG.flatMap((_, k) => [sw, lab[k]]),
  borders: { top: none, bottom: none, left: none, right: none, insideHorizontal: none, insideVertical: none },
  rows: [new TableRow({ height: { value: 260, rule: HeightRule.EXACT }, children: LEG.flatMap(([r, t], k) => [
    new TableCell({ width: { size: sw, type: WidthType.DXA }, shading: { fill: STYLE[r].fill, type: STYLE[r].type, color: STYLE[r].color || 'auto' },
      borders: { top: thin('999999'), bottom: thin('999999'), left: thin('999999'), right: thin('999999') }, children: [small('', 2)] }),
    new TableCell({ width: { size: lab[k], type: WidthType.DXA }, borders: nob, verticalAlign: VerticalAlign.CENTER,
      margins: { left: 80, right: 40, top: 0, bottom: 0 }, children: [new Paragraph({ spacing: { before: 0, after: 0 }, children: [new TextRun({ text: t, size: 16, font: 'Calibri' })] })] })]) })] });

const c = built.map(b => b.counts);
const doc = new Document({ styles: { default: { document: { run: { font: 'Calibri', size: 18 } } } },
  sections: [{ properties: { page: { size: { width: 11906, height: 16838, orientation: PageOrientation.LANDSCAPE },
                                      margin: { top: 794, bottom: 794, left: 794, right: 794 } } },
    children: [
      new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { after: 120 }, children: [new TextRun({ text: 'Rolling-origin partitions of the 20 × 20 triangle (rolling_origin_sets(), R/triangles.R)', font: 'Calibri' })] }),
      outer,
      new Paragraph({ spacing: { before: 120, after: 60 }, children: [] }),
      legend,
      p(['Figure. The three partitions for ', { text: 'test_periods = c(5, 2), vali_periods = 2, exclude = 2', font: 'Consolas', size: 17 },
         ` (Al-Mudafer et al. 2021, scaled from their 40 × 40 quarters). The black outline is each partition’s τ × τ square, τ = 15, 18, 20. Validation: the last two diagonals of the partition, without the first two accident and development periods, plus two cells at development period 2. Test: the calendar years after τ, up to 20. Cells (training / validation / test): ${c[0].train} / ${c[0].validation} / ${c[0].test}, ${c[1].train} / ${c[1].validation} / ${c[1].test}, ${c[2].train} / ${c[2].validation} / none.`],
        { spacing: { before: 160, after: 60 } }),
      p([{ text: 'Editing: every cell is a table cell. Select one or more cells and use Table Design, Shading to change a role; the outline of a partition’s square is the cell borders (Table Design, Borders). Titles, axis labels and the legend are ordinary text.', color: '555555', size: 16 }]),
    ] }] });
Packer.toBuffer(doc).then(b => { fs.writeFileSync('rolling_origin_partitions.docx', b); console.log('written'); });
