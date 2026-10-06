// Base document: landscape A4, title, a placeholder paragraph for the diagram, notes.
const fs = require('fs');
const { Document, Packer, Paragraph, TextRun, AlignmentType, PageOrientation, HeadingLevel } = require('docx');
const p = (text, opts = {}) => new Paragraph({ spacing: { after: 80 }, ...opts, children: [new TextRun({ text, font: 'Calibri', size: 20, ...(opts.run || {}) })] });
const doc = new Document({
  styles: { default: { document: { run: { font: 'Calibri', size: 20 } } } },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838, orientation: PageOrientation.LANDSCAPE },
                          margin: { top: 851, bottom: 851, left: 851, right: 851 } } },
    children: [
      new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { after: 120 },
        children: [new TextRun({ text: 'The bCCNN network of bccnn_model() (R/nn_models.R)', font: 'Calibri' })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun('@@DIAGRAM@@')] }),
      new Paragraph({ spacing: { before: 120, after: 80 }, children: [
        ['Figure. The network of bccnn_model() with Keras\u2019s layer names. Green: skip connection (the ccODP part), which carries the linear predictor '],
        ['\u03B1', 'i'], ['i', 'sub'], [' + '], ['\u03B2', 'i'], ['j', 'sub'],
        [' unchanged to the output. Orange: feed-forward part. Red: output neuron, which adds the two on the log scale and exponentiates. Started at '],
        ['w', 'i'], [' = 1, '], ['c', 'i'], [' = '], ['\u0109', 'i'], [', '], ['B', 'i'],
        [' = 0, the network is exactly the ccODP (chain-ladder) model.'],
      ].map(([text, st]) => new TextRun({ text, font: 'Calibri', size: 20, italics: st === 'i' || st === 'sub', subScript: st === 'sub' })) }),
      p('Editing: every box, arrow and the legend line are separate Word shapes in one group. Click once to select the group, click again to select a single shape; type to change its text; use Shape Format for colour, outline and size. To move a box, select it inside the group and drag it, then drag the end points of its arrows (elbow arrows: right-click, Edit Points). Right-click, Group, Ungroup releases all shapes.', { run: { color: '555555', size: 18 } }),
    ],
  }],
});
Packer.toBuffer(doc).then(b => { fs.writeFileSync('base.docx', b); console.log('base.docx written'); });
