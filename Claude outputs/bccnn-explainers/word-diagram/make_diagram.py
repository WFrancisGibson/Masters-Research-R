"""Inject the bCCNN network diagram as a group of editable Word shapes
(DrawingML wps shapes in a wpg group) into base.docx's placeholder paragraph."""
import re, sys
from xml.sax.saxutils import escape

EMU = 360000                      # EMU per cm
cm = lambda v: int(round(v * EMU))
W, H = 23.6, 11.8                 # group size, cm

# ---- text runs: (text, style) with style a set of 'i', 'b', 'sub', 'sup'
def run(text, st=(), size=18, color="111111", font="Calibri"):
    rpr = [f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:cs="{font}"/>']
    if "b" in st: rpr.append("<w:b/>")
    if "i" in st: rpr.append("<w:i/>")
    rpr.append(f'<w:color w:val="{color}"/><w:sz w:val="{size}"/><w:szCs w:val="{size}"/>')
    if "sub" in st: rpr.append('<w:vertAlign w:val="subscript"/>')
    if "sup" in st: rpr.append('<w:vertAlign w:val="superscript"/>')
    return f'<w:r><w:rPr>{"".join(rpr)}</w:rPr><w:t xml:space="preserve">{escape(text)}</w:t></w:r>'

def para(runs, size=18, color="111111"):
    body = "".join(run(t, st, size, color) for t, st in runs)
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
            f'<w:jc w:val="center"/></w:pPr>{body}</w:p>')

I, SUB, SUP, B = ("i",), ("i", "sub"), ("sup",), ("b",)
a_i = [("α", I), ("i", SUB)]
b_j = [("β", I), ("j", SUB)]
z3 = [("z", I), ("(3)", SUP)]

boxes = [  # name, x, y, w, h, fill, line, lines of runs
 ("AccYear", 0.0, 1.5, 3.1, 1.3, "E8F0FE", "1F1F1F",
  [[("AccYear", ())], [("i", I), (" − 1 ∈ {0, …, 19}", ())]]),
 ("AY_embed", 3.7, 1.5, 3.4, 1.3, "DBE9FF", "1F1F1F",
  [[("AY_embed", ())], a_i + [(" fixed, 20 × 1", ())]]),
 ("DevYear", 0.0, 8.0, 3.1, 1.3, "E8F0FE", "1F1F1F",
  [[("DevYear", ())], [("j", I), (" − 1 ∈ {0, …, 19}", ())]]),
 ("DY_embed", 3.7, 8.0, 3.4, 1.3, "DBE9FF", "1F1F1F",
  [[("DY_embed", ())], b_j + [(" fixed, 20 × 1", ())]]),
 ("cc0", 8.4, 0.3, 3.0, 1.2, "E0F3E0", "2E7D32",
  [[("cc0 = add", ())], a_i + [(" + ", ())] + b_j]),
 ("concate0", 8.4, 4.8, 3.6, 1.5, "FFF3E0", "1F1F1F",
  [[("concate0", ())], [("z", I), ("(0)", SUP), (" = (", ())] + a_i + [(", ", ())] + b_j + [(") ∈ ℝ", ()), ("2", SUP)]]),
 ("hidden1", 12.6, 4.55, 2.9, 2.0, "FFF3E0", "1F1F1F",
  [[("hidden1", ())], [("tanh, ", ()), ("q", I), ("1", ("sub",)), (" = 20", ())], [("dropout 10%", ())]]),
 ("hidden2", 16.0, 4.55, 2.9, 2.0, "FFF3E0", "1F1F1F",
  [[("hidden2", ())], [("tanh, ", ()), ("q", I), ("2", ("sub",)), (" = 15", ())], [("dropout 10%", ())]]),
 ("hidden3", 19.4, 4.55, 2.9, 2.0, "FFF3E0", "1F1F1F",
  [[("hidden3", ())], [("tanh, ", ()), ("q", I), ("3", ("sub",)), (" = 10", ())], [("dropout 10%", ())]]),
 ("concate1", 15.6, 0.3, 6.7, 1.2, "F3E5F5", "1F1F1F",
  [[("concate1 = (", ())] + a_i + [(" + ", ())] + b_j + [(", ", ())] + z3 + [(") ∈ ℝ", ()), ("11", SUP)]]),
 ("Response", 13.6, 8.1, 8.7, 2.6, "FFE0E0", "B71C1C",
  [[("Response: dense(1), exponential", ())],
   [("μ", I), ("i,j", SUB), (" = exp{", ()), ("w", I), ("(", ())] + a_i + [(" + ", ())] + b_j
     + [(") + ", ()), ("c", I), (" + ⟨", ()), ("B", I), (", ", ())] + z3 + [("⟩}", ())],
   [("start: ", ()), ("w", I), (" = 1, ", ()), ("c", I), (" = ", ()), ("ĉ", I), (", ", ()), ("B", I), (" = 0", ())]]),
]

BLACK, GREEN = "1F1F1F", "2E7D32"
arrows = [  # name, colour, points (cm), arrowhead at the end?
 ("AccYear to AY_embed", BLACK, [(3.1, 2.15), (3.7, 2.15)], True),
 ("DevYear to DY_embed", BLACK, [(3.1, 8.65), (3.7, 8.65)], True),
 ("AY_embed to concate0", BLACK, [(5.4, 2.8), (5.4, 5.55), (8.4, 5.55)], True),
 ("DY_embed joins AY_embed into concate0", BLACK, [(5.4, 8.0), (5.4, 5.55)], False),
 ("AY_embed to cc0 (skip)", GREEN, [(7.1, 2.15), (9.3, 2.15), (9.3, 1.5)], True),
 ("DY_embed to cc0 (skip)", GREEN, [(7.1, 8.65), (7.8, 8.65), (7.8, 3.4), (10.5, 3.4), (10.5, 1.5)], True),
 ("cc0 to concate1 (skip)", GREEN, [(11.4, 0.9), (15.6, 0.9)], True),
 ("concate0 to hidden1", BLACK, [(12.0, 5.55), (12.6, 5.55)], True),
 ("hidden1 to hidden2", BLACK, [(15.5, 5.55), (16.0, 5.55)], True),
 ("hidden2 to hidden3", BLACK, [(18.9, 5.55), (19.4, 5.55)], True),
 ("hidden3 to concate1", BLACK, [(20.85, 4.55), (20.85, 1.5)], True),
 ("concate1 to Response", BLACK, [(22.3, 0.9), (23.3, 0.9), (23.3, 9.4), (22.3, 9.4)], True),
]

sid = [10]
def nid():
    sid[0] += 1
    return sid[0]

def box_xml(name, x, y, w, h, fill, line, lines):
    paras = "".join(para(l) for l in lines)
    return (f'<wps:wsp><wps:cNvPr id="{nid()}" name="{escape(name)}"/><wps:cNvSpPr/>'
            f'<wps:spPr><a:xfrm><a:off x="{cm(x)}" y="{cm(y)}"/><a:ext cx="{cm(w)}" cy="{cm(h)}"/></a:xfrm>'
            '<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 12000"/></a:avLst></a:prstGeom>'
            f'<a:solidFill><a:srgbClr val="{fill}"/></a:solidFill>'
            f'<a:ln w="12700"><a:solidFill><a:srgbClr val="{line}"/></a:solidFill></a:ln></wps:spPr>'
            f'<wps:txbx><w:txbxContent>{paras}</w:txbxContent></wps:txbx>'
            '<wps:bodyPr rot="0" vert="horz" wrap="square" lIns="36000" tIns="18000" rIns="36000" bIns="18000" anchor="ctr" anchorCtr="0">'
            '<a:noAutofit/></wps:bodyPr></wps:wsp>')

def arrow_xml(name, color, pts, head):
    xs = [cm(p[0]) for p in pts]; ys = [cm(p[1]) for p in pts]
    x0, y0 = min(xs), min(ys)
    w, h = max(max(xs) - x0, 1), max(max(ys) - y0, 1)
    path = f'<a:moveTo><a:pt x="{xs[0]-x0}" y="{ys[0]-y0}"/></a:moveTo>' + "".join(
        f'<a:lnTo><a:pt x="{x-x0}" y="{y-y0}"/></a:lnTo>' for x, y in zip(xs[1:], ys[1:]))
    tail = '<a:tailEnd type="triangle" w="med" len="med"/>' if head else ""
    return (f'<wps:wsp><wps:cNvPr id="{nid()}" name="{escape(name)}"/><wps:cNvSpPr/>'
            f'<wps:spPr><a:xfrm><a:off x="{x0}" y="{y0}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm>'
            '<a:custGeom><a:avLst/><a:gdLst/><a:ahLst/><a:cxnLst/><a:rect l="0" t="0" r="r" b="b"/>'
            f'<a:pathLst><a:path w="{w}" h="{h}" fill="none">{path}</a:path></a:pathLst></a:custGeom>'
            f'<a:noFill/><a:ln w="15875"><a:solidFill><a:srgbClr val="{color}"/></a:solidFill>'
            f'<a:miter lim="800000"/>{tail}</a:ln></wps:spPr><wps:bodyPr/></wps:wsp>')

legend = ("Legend", 0.0, 11.0, W, 0.7, None, None,
          [[("green: skip connection (the ccODP part)   orange: feed-forward part   red: output neuron", ())]])
def legend_xml():
    _, x, y, w, h, *_r, lines = legend
    paras = "".join(para(l, size=16, color="444444") for l in lines)
    return (f'<wps:wsp><wps:cNvPr id="{nid()}" name="Legend"/><wps:cNvSpPr txBox="1"/>'
            f'<wps:spPr><a:xfrm><a:off x="{cm(x)}" y="{cm(y)}"/><a:ext cx="{cm(w)}" cy="{cm(h)}"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr>'
            f'<wps:txbx><w:txbxContent>{paras}</w:txbxContent></wps:txbx>'
            '<wps:bodyPr rot="0" vert="horz" wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr" anchorCtr="0"><a:noAutofit/></wps:bodyPr></wps:wsp>')

children = "".join(arrow_xml(*a) for a in arrows) + "".join(box_xml(*b) for b in boxes) + legend_xml()
A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
drawing = (
 '<w:r><mc:AlternateContent><mc:Choice Requires="wpg"><w:drawing>'
 f'<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cm(W)}" cy="{cm(H)}"/>'
 '<wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="1" name="bCCNN network diagram" descr="Editable diagram of the bCCNN network: inputs, embeddings, skip connection, three hidden layers and the exponential output neuron."/>'
 '<wp:cNvGraphicFramePr/>'
 f'<a:graphic {A}><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup">'
 '<wpg:wgp><wpg:cNvGrpSpPr/><wpg:grpSpPr>'
 f'<a:xfrm><a:off x="0" y="0"/><a:ext cx="{cm(W)}" cy="{cm(H)}"/><a:chOff x="0" y="0"/><a:chExt cx="{cm(W)}" cy="{cm(H)}"/></a:xfrm>'
 f'</wpg:grpSpPr>{children}</wpg:wgp></a:graphicData></a:graphic></wp:inline></w:drawing>'
 '</mc:Choice></mc:AlternateContent></w:r>')

p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = re.search(r'<w:r>(?:(?!</w:r>).)*@@DIAGRAM@@(?:(?!</w:r>).)*</w:r>', s)
assert m, "placeholder run not found"
s = s[:m.start()] + drawing + s[m.end():]
open(p, "w", encoding="utf-8").write(s)
print("diagram injected:", len(boxes), "boxes,", len(arrows), "arrows, legend")
