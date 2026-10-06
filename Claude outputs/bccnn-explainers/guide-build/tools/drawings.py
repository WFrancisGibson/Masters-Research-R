"""Editable figures for the Word versions of the explainers, laid out for the
16.5 cm text width of the Research Assignment Guide and set in Cambria:

  architecture  the bCCNN network of bccnn_model() as a group of Word shapes
  partitions    the rolling-origin partitions as three 20 x 20 Word tables

build(name) returns a list of lxml elements (paragraphs / tables)."""
from xml.sax.saxutils import escape
from lxml import etree

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
M = "http://schemas.openxmlformats.org/officeDocument/2006/math"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
EXTRA_NS = ('xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
            'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
            'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
            'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
            'xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"')
FONT = "Cambria"


def X(xml):
    return etree.fromstring(f'<root xmlns:w="{W}" xmlns:m="{M}" xmlns:r="{R}" {EXTRA_NS}>{xml}</root>')[0]


# ======================================================================= network
EMU = 360000
cm = lambda v: int(round(v * EMU))
GW, GH = 16.5, 8.5


def _run(text, st=(), size=14, color="111111"):
    rpr = [f'<w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:cs="{FONT}"/>']
    if "b" in st: rpr.append("<w:b/>")
    if "i" in st: rpr.append("<w:i/>")
    rpr.append(f'<w:color w:val="{color}"/><w:sz w:val="{size}"/><w:szCs w:val="{size}"/>')
    if "sub" in st: rpr.append('<w:vertAlign w:val="subscript"/>')
    if "sup" in st: rpr.append('<w:vertAlign w:val="superscript"/>')
    return f'<w:r><w:rPr>{"".join(rpr)}</w:rPr><w:t xml:space="preserve">{escape(text)}</w:t></w:r>'


def _para(runs, size=14, color="111111"):
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="228" w:lineRule="auto"/>'
            f'<w:jc w:val="center"/></w:pPr>{"".join(_run(t, st, size, color) for t, st in runs)}</w:p>')


I, SUB, SUP = ("i",), ("i", "sub"), ("sup",)
a_i = [("α", I), ("i", SUB)]
b_j = [("β", I), ("j", SUB)]
z3 = [("z", I), ("(3)", SUP)]

BOXES = [  # name, x, y, w, h, fill, line, lines (cm)
    ("AccYear", 0.0, 1.1, 2.45, 0.95, "E8F0FE", "1F1F1F", [[("AccYear", ())], [("i", I), (" − 1 ∈ {0, …, 19}", ())]]),
    ("AY_embed", 2.75, 1.1, 2.35, 0.95, "DBE9FF", "1F1F1F", [[("AY_embed", ())], a_i + [(" fixed, 20 × 1", ())]]),
    ("DevYear", 0.0, 5.7, 2.45, 0.95, "E8F0FE", "1F1F1F", [[("DevYear", ())], [("j", I), (" − 1 ∈ {0, …, 19}", ())]]),
    ("DY_embed", 2.75, 5.7, 2.35, 0.95, "DBE9FF", "1F1F1F", [[("DY_embed", ())], b_j + [(" fixed, 20 × 1", ())]]),
    ("cc0", 5.75, 0.2, 2.1, 0.9, "E0F3E0", "2E7D32", [[("cc0 = add", ())], a_i + [(" + ", ())] + b_j]),
    ("concate0", 5.75, 3.4, 2.55, 1.0, "FFF3E0", "1F1F1F",
     [[("concate0", ())], [("z", I), ("(0)", SUP), (" = (", ())] + a_i + [(", ", ())] + b_j + [(") ∈ ℝ", ()), ("2", SUP)]]),
    ("hidden1", 8.75, 3.25, 2.05, 1.3, "FFF3E0", "1F1F1F",
     [[("hidden1", ())], [("tanh, ", ()), ("q", I), ("1", ("sub",)), (" = 20", ())], [("dropout 10%", ())]]),
    ("hidden2", 11.2, 3.25, 2.05, 1.3, "FFF3E0", "1F1F1F",
     [[("hidden2", ())], [("tanh, ", ()), ("q", I), ("2", ("sub",)), (" = 15", ())], [("dropout 10%", ())]]),
    ("hidden3", 13.65, 3.25, 2.05, 1.3, "FFF3E0", "1F1F1F",
     [[("hidden3", ())], [("tanh, ", ()), ("q", I), ("3", ("sub",)), (" = 10", ())], [("dropout 10%", ())]]),
    ("concate1", 10.8, 0.2, 4.9, 0.9, "F3E5F5", "1F1F1F",
     [[("concate1 = (", ())] + a_i + [(" + ", ())] + b_j + [(", ", ())] + z3 + [(") ∈ ℝ", ()), ("11", SUP)]]),
    ("Response", 9.6, 5.9, 6.1, 1.9, "FFE0E0", "B71C1C",
     [[("Response: dense(1), exponential", ())],
      [("μ", I), ("i,j", SUB), (" = exp{", ()), ("w", I), ("(", ())] + a_i + [(" + ", ())] + b_j
      + [(") + ", ()), ("c", I), (" + ⟨", ()), ("B", I), (", ", ())] + z3 + [("⟩}", ())],
      [("start: ", ()), ("w", I), (" = 1, ", ()), ("c", I), (" = ", ()), ("ĉ", I), (", ", ()), ("B", I), (" = 0", ())]]),
]
BLACK, GREEN = "1F1F1F", "2E7D32"
ARROWS = [
    ("AccYear to AY_embed", BLACK, [(2.45, 1.575), (2.75, 1.575)], True),
    ("DevYear to DY_embed", BLACK, [(2.45, 6.175), (2.75, 6.175)], True),
    ("AY_embed to concate0", BLACK, [(3.925, 2.05), (3.925, 3.9), (5.75, 3.9)], True),
    ("DY_embed joins AY_embed into concate0", BLACK, [(3.925, 5.7), (3.925, 3.9)], False),
    ("AY_embed to cc0 (skip connection)", GREEN, [(5.1, 1.575), (6.4, 1.575), (6.4, 1.1)], True),
    ("DY_embed to cc0 (skip connection)", GREEN, [(5.1, 6.175), (5.4, 6.175), (5.4, 2.6), (7.3, 2.6), (7.3, 1.1)], True),
    ("cc0 to concate1 (skip connection)", GREEN, [(7.85, 0.65), (10.8, 0.65)], True),
    ("concate0 to hidden1", BLACK, [(8.3, 3.9), (8.75, 3.9)], True),
    ("hidden1 to hidden2", BLACK, [(10.8, 3.9), (11.2, 3.9)], True),
    ("hidden2 to hidden3", BLACK, [(13.25, 3.9), (13.65, 3.9)], True),
    ("hidden3 to concate1", BLACK, [(14.675, 3.25), (14.675, 1.1)], True),
    ("concate1 to Response", BLACK, [(15.7, 0.65), (16.3, 0.65), (16.3, 6.85), (15.7, 6.85)], True),
]


def _architecture_xml():
    sid = [10]

    def nid():
        sid[0] += 1
        return sid[0]

    def box(name, x, y, w, h, fill, line, lines):
        return (f'<wps:wsp><wps:cNvPr id="{nid()}" name="{escape(name)}"/><wps:cNvSpPr/>'
                f'<wps:spPr><a:xfrm><a:off x="{cm(x)}" y="{cm(y)}"/><a:ext cx="{cm(w)}" cy="{cm(h)}"/></a:xfrm>'
                '<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 12000"/></a:avLst></a:prstGeom>'
                f'<a:solidFill><a:srgbClr val="{fill}"/></a:solidFill>'
                f'<a:ln w="9525"><a:solidFill><a:srgbClr val="{line}"/></a:solidFill></a:ln></wps:spPr>'
                f'<wps:txbx><w:txbxContent>{"".join(_para(l) for l in lines)}</w:txbxContent></wps:txbx>'
                '<wps:bodyPr rot="0" vert="horz" wrap="square" lIns="18000" tIns="0" rIns="18000" bIns="0" anchor="ctr" anchorCtr="0">'
                '<a:noAutofit/></wps:bodyPr></wps:wsp>')

    def arrow(name, color, pts, head):
        xs = [cm(p[0]) for p in pts]; ys = [cm(p[1]) for p in pts]
        x0, y0 = min(xs), min(ys)
        w, h = max(max(xs) - x0, 1), max(max(ys) - y0, 1)
        path = f'<a:moveTo><a:pt x="{xs[0]-x0}" y="{ys[0]-y0}"/></a:moveTo>' + "".join(
            f'<a:lnTo><a:pt x="{x-x0}" y="{y-y0}"/></a:lnTo>' for x, y in zip(xs[1:], ys[1:]))
        tail = '<a:tailEnd type="triangle" w="sm" len="sm"/>' if head else ""
        return (f'<wps:wsp><wps:cNvPr id="{nid()}" name="{escape(name)}"/><wps:cNvSpPr/>'
                f'<wps:spPr><a:xfrm><a:off x="{x0}" y="{y0}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm>'
                '<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l="0" t="0" r="r" b="b"/>'
                f'<a:pathLst><a:path w="{w}" h="{h}" fill="none">{path}</a:path></a:pathLst></a:custGeom>'
                f'<a:noFill/><a:ln w="12700"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill>'
                f'<a:miter lim="800000"/>{tail}</a:ln></wps:spPr><wps:bodyPr/></wps:wsp>')

    legend = (f'<wps:wsp><wps:cNvPr id="{nid()}" name="Legend"/><wps:cNvSpPr txBox="1"/>'
              f'<wps:spPr><a:xfrm><a:off x="0" y="{cm(8.0)}"/><a:ext cx="{cm(GW)}" cy="{cm(0.45)}"/></a:xfrm>'
              '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr>'
              '<wps:txbx><w:txbxContent>' + _para([("Green: skip connection (the ccODP part); orange: feed-forward part; red: output neuron", ())], 14, "444444")
              + '</w:txbxContent></wps:txbx><wps:bodyPr rot="0" vert="horz" wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr" anchorCtr="0"><a:noAutofit/></wps:bodyPr></wps:wsp>')
    children = "".join(arrow(*a) for a in ARROWS) + "".join(box(*b) for b in BOXES) + legend
    return ('<w:p><w:pPr><w:keepNext/><w:spacing w:before="120" w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr>'
            '<w:r><mc:AlternateContent><mc:Choice Requires="wpg"><w:drawing>'
            f'<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cm(GW)}" cy="{cm(GH)}"/>'
            '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
            '<wp:docPr id="501" name="bCCNN network diagram" descr="Editable diagram of the bCCNN network: inputs, fixed embeddings, skip connection, three hidden layers and the exponential output neuron."/>'
            '<wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup">'
            f'<wpg:wgp><wpg:cNvGrpSpPr/><wpg:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cm(GW)}" cy="{cm(GH)}"/>'
            f'<a:chOff x="0" y="0"/><a:chExt cx="{cm(GW)}" cy="{cm(GH)}"/></a:xfrm></wpg:grpSpPr>{children}</wpg:wgp>'
            '</a:graphicData></a:graphic></wp:inline></w:drawing></mc:Choice></mc:AlternateContent></w:r></w:p>')


# ======================================================================= partitions
N, TEST, VP, EX = 20, (5, 2), 2, 2


def _rround(x):
    import math
    f = math.floor(x)
    if abs(x - f - 0.5) < 1e-12:
        return f if f % 2 == 0 else f + 1
    return int(round(x))


def partition(tau):
    role = [[None] * (N + 1) for _ in range(N + 1)]
    for i in range(1, N + 1):
        for j in range(1, N + 1):
            k = i + j - 1
            if k > N: role[i][j] = "future"
            elif i > tau or j > tau: role[i][j] = "outside"
            elif k > tau: role[i][j] = "test"
            else: role[i][j] = "validation" if (k > tau - VP and i > EX and j > EX) else "train"
    K, lo, hi = VP * (EX - 1), EX + 1, tau - VP - EX + 1
    devs = list(range(EX, 1, -1))
    for m in range(1, K + 1):
        role[_rround(lo + (hi - lo) * (m - 0.5) / K)][devs[(m - 1) % len(devs)]] = "validation"
    return role


SHADE = {"train": ('4DAF4A', 'clear', 'auto'), "validation": ('1B5E20', 'clear', 'auto'), "test": ('E41A1C', 'clear', 'auto'),
         "outside": ('DDE7F0', 'thinDiagStripe', '9FB0C2'), "future": ('F0F0F0', 'clear', 'auto')}
CELL, LAB, PANEL = 144, 238, 3118      # twips: 20 x 144 + 238 = 3118; 3 x 3118 = 9354


def _small(t, sz=10, jc="center", st=""):
    return (f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="120" w:lineRule="exact"/><w:jc w:val="{jc}"/></w:pPr>'
            f'<w:r><w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}"/>{st}<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/></w:rPr>'
            f'<w:t xml:space="preserve">{escape(t)}</w:t></w:r></w:p>')


def _caption_line(runs, sz=15, after=0):
    body = "".join(f'<w:r><w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}"/>{"<w:i/>" if it else ""}<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/></w:rPr>'
                   f'<w:t xml:space="preserve">{escape(t)}</w:t></w:r>' for t, it in runs)
    return (f'<w:p><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="{after}" w:line="240" w:lineRule="auto"/>'
            f'<w:jc w:val="center"/></w:pPr>{body}</w:p>')


def _bd(c, sz=2):
    return f'w:val="single" w:sz="{sz}" w:space="0" w:color="{c}"'


NOB = '<w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/>'


def _grid(tau):
    role = partition(tau)
    ticks = {1, 5, 10, 15, 20}
    rows = []
    hdr = [f'<w:tc><w:tcPr><w:tcW w:w="{LAB}" w:type="dxa"/><w:tcBorders>{NOB}</w:tcBorders></w:tcPr>{_small("")}</w:tc>']
    for c in range(1, N + 1):
        hdr.append(f'<w:tc><w:tcPr><w:tcW w:w="{CELL}" w:type="dxa"/><w:tcBorders>{NOB}</w:tcBorders><w:vAlign w:val="bottom"/></w:tcPr>'
                   f'{_small(str(c) if c in ticks else "")}</w:tc>')
    rows.append(f'<w:tr><w:trPr><w:cantSplit/><w:trHeight w:val="{CELL}" w:hRule="exact"/></w:trPr>{"".join(hdr)}</w:tr>')
    for i in range(1, N + 1):
        cells = [f'<w:tc><w:tcPr><w:tcW w:w="{LAB}" w:type="dxa"/><w:tcBorders>{NOB}</w:tcBorders><w:vAlign w:val="center"/></w:tcPr>'
                 f'{_small(str(i) if i in ticks else "", jc="right")}</w:tc>']
        for j in range(1, N + 1):
            r = role[i][j]
            fill, val, color = SHADE[r]
            line = "D9D9D9" if r in ("future", "outside") else "FFFFFF"
            b = {"top": _bd(line), "left": _bd(line), "bottom": _bd(line), "right": _bd(line)}
            if i <= tau and j <= tau:
                thick = _bd("000000", 12)
                if i == 1: b["top"] = thick
                if i == tau: b["bottom"] = thick
                if j == 1: b["left"] = thick
                if j == tau: b["right"] = thick
            borders = "".join(f"<w:{k} {v}/>" for k, v in b.items())
            cells.append(f'<w:tc><w:tcPr><w:tcW w:w="{CELL}" w:type="dxa"/><w:tcBorders>{borders}</w:tcBorders>'
                         f'<w:shd w:val="{val}" w:color="{color}" w:fill="{fill}"/></w:tcPr>{_small("", 2)}</w:tc>')
        rows.append(f'<w:tr><w:trPr><w:cantSplit/><w:trHeight w:val="{CELL}" w:hRule="exact"/></w:trPr>{"".join(cells)}</w:tr>')
    grid = "".join(f'<w:gridCol w:w="{w}"/>' for w in [LAB] + [CELL] * N)
    return (f'<w:tbl><w:tblPr><w:tblW w:w="{PANEL}" w:type="dxa"/><w:jc w:val="center"/><w:tblLayout w:type="fixed"/>'
            '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar>'
            f'<w:tblLook w:val="0000"/></w:tblPr><w:tblGrid>{grid}</w:tblGrid>{"".join(rows)}</w:tbl>')


def _partitions_xml():
    titles = [(15, "Test partition 1: valuation year 15"), (18, "Test partition 2: valuation year 18"),
              (20, "Final partition: valuation year 20")]
    cells = []
    for tau, t in titles:
        cells.append(f'<w:tc><w:tcPr><w:tcW w:w="{PANEL}" w:type="dxa"/><w:tcBorders>{NOB}</w:tcBorders></w:tcPr>'
                     + _caption_line([(t, False)], 15, 40)
                     + _caption_line([("development period ", False), ("j", True), (" (columns)", False)], 13, 20)
                     + _grid(tau)
                     + _caption_line([("accident period ", False), ("i", True), (" (rows, 1 at the top)", False)], 13, 0) + '</w:tc>')
    outer = (f'<w:tbl><w:tblPr><w:tblW w:w="{3 * PANEL}" w:type="dxa"/><w:jc w:val="center"/>'
             '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/><w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders><w:tblLayout w:type="fixed"/>'
             '<w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar><w:tblLook w:val="0000"/></w:tblPr>'
             f'<w:tblGrid>{"".join(f"<w:gridCol w:w={chr(34)}{PANEL}{chr(34)}/>" for _ in range(3))}</w:tblGrid>'
             f'<w:tr><w:trPr><w:cantSplit/></w:trPr>{"".join(cells)}</w:tr></w:tbl>')
    items = [("train", "training", 1150), ("validation", "validation", 1150), ("test", "test (later calendar years)", 2200),
             ("outside", "observed, outside the partition’s square", 2550), ("future", "future (never used)", 1306)]
    lc = []
    for r, label, w in items:
        fill, val, color = SHADE[r]
        lc.append(f'<w:tc><w:tcPr><w:tcW w:w="200" w:type="dxa"/><w:tcBorders><w:top {_bd("999999")}/><w:left {_bd("999999")}/>'
                  f'<w:bottom {_bd("999999")}/><w:right {_bd("999999")}/></w:tcBorders><w:shd w:val="{val}" w:color="{color}" w:fill="{fill}"/></w:tcPr>{_small("", 2)}</w:tc>')
        lc.append(f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/><w:tcBorders>{NOB}</w:tcBorders><w:vAlign w:val="center"/></w:tcPr>'
                  f'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:ind w:left="60"/></w:pPr>'
                  f'<w:r><w:rPr><w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}"/><w:sz w:val="14"/><w:szCs w:val="14"/></w:rPr><w:t xml:space="preserve">{escape(label)}</w:t></w:r></w:p></w:tc>')
    lgrid = "".join(f'<w:gridCol w:w="{x}"/>' for _, _, w in items for x in (200, w))
    legend = (f'<w:tbl><w:tblPr><w:tblW w:w="9356" w:type="dxa"/><w:jc w:val="center"/>'
              '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/><w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders><w:tblLayout w:type="fixed"/>'
              '<w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar><w:tblLook w:val="0000"/></w:tblPr>'
              f'<w:tblGrid>{lgrid}</w:tblGrid><w:tr><w:trPr><w:cantSplit/><w:trHeight w:val="200" w:hRule="exact"/></w:trPr>{"".join(lc)}</w:tr></w:tbl>')
    spacer = '<w:p><w:pPr><w:keepNext/><w:spacing w:before="0" w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>'
    return [outer, spacer, legend]


def counts():
    out = {}
    for tau in (15, 18, 20):
        role = partition(tau)
        flat = [role[i][j] for i in range(1, N + 1) for j in range(1, N + 1)]
        out[tau] = {k: flat.count(k) for k in ("train", "validation", "test")}
    return out


def build(name):
    if name == "architecture":
        return [X(_architecture_xml())]
    if name == "partitions":
        return [X(x) for x in _partitions_xml()]
    raise SystemExit("unknown drawing " + name)
