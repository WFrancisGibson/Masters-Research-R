"""Build a Word document on the Department template from build/dX.md
(written by resolve.py), following the Research Assignment Guide.

  python3 build.py d1 [d2 ...]

Steps: pandoc (reference document = the Department template) -> raw docx;
rewrite word/document.xml (markers, styles, equations, captions, tables,
lists, figures, sections, title page); zip -> out/dX.docx.
"""
import copy, json, os, re, shutil, subprocess, sys, zipfile
from lxml import etree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD, OUT = os.path.join(ROOT, "build"), os.path.join(ROOT, "out")
TEMPLATE = os.path.join(ROOT, "template", "template.docx")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import drawings  # editable figures (Word shapes, Word tables)

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
M = "http://schemas.openxmlformats.org/officeDocument/2006/math"
R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS = {"w": W, "m": M, "r": R}
q = lambda tag: "{%s}%s" % (W, tag.split(":")[1]) if tag.startswith("w:") else "{%s}%s" % (M, tag.split(":")[1])
TEXT_W = 9356                        # 16.5 cm text width in twips (A4, 25 mm left, 20 mm right)
NSDECL = f'xmlns:w="{W}" xmlns:m="{M}" xmlns:r="{R}"'


def X(xml):
    """parse an XML fragment with the w/m/r namespaces"""
    return etree.fromstring(f"<root {NSDECL} {drawings.EXTRA_NS}>{xml}</root>")[0]


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def ptext(p):
    return "".join(t.text or "" for t in p.iter(q("w:t")))


def style_of(p):
    s = p.find("w:pPr/w:pStyle", NS)
    return s.get(q("w:val")) if s is not None else None


def set_style(p, sid):
    ppr = p.find("w:pPr", NS)
    if ppr is None:
        ppr = etree.SubElement(p, q("w:pPr")); p.remove(ppr); p.insert(0, ppr)
    s = ppr.find("w:pStyle", NS)
    if sid is None:
        if s is not None:
            ppr.remove(s)
        return
    if s is None:
        s = etree.Element(q("w:pStyle")); ppr.insert(0, s)
    s.set(q("w:val"), sid)


def ppr_child(p, tag):
    ppr = p.find("w:pPr", NS)
    if ppr is None:
        set_style(p, style_of(p)); ppr = p.find("w:pPr", NS)
    return ppr


def strip_prefix(p, n):
    """remove the first n characters of the paragraph's text, run by run"""
    for t in list(p.iter(q("w:t"))):
        if n <= 0:
            break
        s = t.text or ""
        if len(s) <= n:
            n -= len(s); t.text = ""
        else:
            t.text = s[n:]; n = 0
            t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")


def run(text, rpr=""):
    return f'<w:r>{"<w:rPr>" + rpr + "</w:rPr>" if rpr else ""}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'


def field(instr, result):
    return ('<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
            f'<w:r><w:instrText xml:space="preserve"> {esc(instr)} </w:instrText></w:r>'
            '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
            f'<w:r><w:rPr><w:noProof/></w:rPr><w:t xml:space="preserve">{esc(result)}</w:t></w:r>'
            '<w:r><w:fldChar w:fldCharType="end"/></w:r>')


def para(style, inner="", ppr_extra=""):
    st = f'<w:pStyle w:val="{style}"/>' if style else ""
    return f"<w:p><w:pPr>{st}{ppr_extra}</w:pPr>{inner}</w:p>"


# ---------------------------------------------------------------- front matter
def title_page(title, subtitle):
    blank = para("USBtitlepage")
    sz = lambda n: f'<w:sz w:val="{n}"/><w:szCs w:val="{n}"/>'
    xs = [para("Title", run(title, sz(28)), f'<w:spacing w:before="1800" w:after="120"/><w:rPr>{sz(28)}</w:rPr>'),
          para("USBtitlepage", run(subtitle, sz(24))), blank, blank, blank, blank,
          para("USBStudentnameontitlepage", run("Study notes on the bCCNN strand of the research assignment")),
          blank, blank,
          para("USBtitlepage",
               run("Prepared with the generative artificial intelligence tool Claude (Anthropic)", sz(22))
               + f'<w:r><w:rPr>{sz(22)}</w:rPr><w:br/></w:r>' + run("as study material for the BComHons research assignment", sz(22))
               + f'<w:r><w:rPr>{sz(22)}</w:rPr><w:br/></w:r>' + run("Department of Statistics and Actuarial Science", sz(22))
               + f'<w:r><w:rPr>{sz(22)}</w:rPr><w:br/></w:r>' + run("Stellenbosch University", sz(22))),
          blank, blank, blank,
          para("USBSupervisor", run("Not for submission for assessment")),
          blank, blank, blank, blank,
          para("USBtitlepage", run("October 2026"))]
    return [X(x) for x in xs]


def toc_para(instr, style, placeholder):
    return X(para(style, field(instr, placeholder),
                  '<w:tabs><w:tab w:val="left" w:pos="1200"/><w:tab w:val="right" w:leader="dot" w:pos="9346"/></w:tabs>'))


def heading_like(text):
    # 'Table of contents' must look like a Section heading but stay out of the table of contents
    return X(para(None, run(text, '<w:b/><w:bCs/><w:sz w:val="28"/><w:szCs w:val="32"/>'),
                  '<w:keepNext/><w:pageBreakBefore/><w:spacing w:before="120"/><w:jc w:val="center"/>'))


# ---------------------------------------------------------------- captions, equations
def caption(kind, num, p):
    """turn marker paragraph 'QQTABCAP|n|text' into a captioned paragraph keeping the text's formatting"""
    marker = ptext(p)
    pref = marker[: marker.index("|", marker.index("|") + 1) + 1]
    strip_prefix(p, len(pref))
    style = "USBTableheading" if kind == "Table" else "USBFigureheading"
    chap, n = num.split(".")
    # fixed number text (correct in Word and LibreOffice) plus a hidden SEQ field so that
    # Word's and LibreOffice's lists of tables and figures pick the caption up
    lead = run(f"{kind} {chap}.{n}") + field(f"SEQ {kind} \\* ARABIC \\h", "")
    lead += "<w:r><w:tab/></w:r>"
    ppr = p.find("w:pPr", NS)
    if ppr is not None:
        p.remove(ppr)
    for i, el in enumerate(X(f"<w:p>{lead}</w:p>")):
        p.insert(i, el)
    p.insert(0, X(f'<w:pPr><w:pStyle w:val="{style}"/>{"<w:keepNext/>" if kind == "Table" else ""}'
                  f'<w:tabs><w:tab w:val="left" w:pos="1134"/></w:tabs><w:ind w:left="1134" w:hanging="1134"/></w:pPr>'))
    return p


def equation_table(mpara, num):
    set_style(mpara, "USBformula")
    ppr = mpara.find("w:pPr", NS)
    for tag in ("w:spacing", "w:jc"):
        e = ppr.find(tag, NS)
        if e is not None:
            ppr.remove(e)
    ppr.append(X('<w:spacing w:before="60" w:after="60"/>'))
    for jc in mpara.iter("{%s}jc" % M):
        jc.set("{%s}val" % M, "center")
    tbl = X(f'''<w:tbl><w:tblPr><w:tblW w:w="{TEXT_W}" w:type="dxa"/><w:jc w:val="center"/>
      <w:tblBorders><w:top w:val="none" w:sz="0" w:space="0" w:color="auto"/><w:left w:val="none" w:sz="0" w:space="0" w:color="auto"/>
      <w:bottom w:val="none" w:sz="0" w:space="0" w:color="auto"/><w:right w:val="none" w:sz="0" w:space="0" w:color="auto"/>
      <w:insideH w:val="none" w:sz="0" w:space="0" w:color="auto"/><w:insideV w:val="none" w:sz="0" w:space="0" w:color="auto"/></w:tblBorders>
      <w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar>
      <w:tblLook w:val="0000" w:firstRow="0" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="1" w:noVBand="1"/></w:tblPr>
      <w:tblGrid><w:gridCol w:w="8505"/><w:gridCol w:w="851"/></w:tblGrid>
      <w:tr><w:trPr><w:cantSplit/></w:trPr>
        <w:tc><w:tcPr><w:tcW w:w="8505" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr></w:tc>
        <w:tc><w:tcPr><w:tcW w:w="851" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:pStyle w:val="USBformula"/><w:spacing w:before="60" w:after="60"/><w:jc w:val="right"/></w:pPr>{run("(" + num + ")")}</w:p></w:tc></w:tr></w:tbl>''')
    tc = tbl.findall(".//w:tc", NS)[0]
    tc.append(mpara)
    return tbl


# ---------------------------------------------------------------- tables
def style_table(tbl):
    tblPr = tbl.find("w:tblPr", NS)
    for e in list(tblPr):
        tblPr.remove(e)
    for x in [f'<w:tblW w:w="{TEXT_W}" w:type="dxa"/>', '<w:jc w:val="center"/>',
              '<w:tblBorders>' + "".join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
                                         for s in ("top", "left", "bottom", "right", "insideH", "insideV")) + '</w:tblBorders>',
              '<w:tblLayout w:type="fixed"/>',
              '<w:tblCellMar><w:left w:w="85" w:type="dxa"/><w:right w:w="85" w:type="dxa"/></w:tblCellMar>',
              '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>']:
        tblPr.append(X(x))
    grid = tbl.find("w:tblGrid", NS)
    cols = grid.findall("w:gridCol", NS)
    widths = [int(c.get(q("w:w")) or 1) for c in cols]
    tot = sum(widths) or 1
    new = [max(400, round(w * TEXT_W / tot)) for w in widths]
    new[-1] += TEXT_W - sum(new)
    for c, w in zip(cols, new):
        c.set(q("w:w"), str(w))
    rows = tbl.findall("w:tr", NS)
    # alignment of each column from the body rows
    col_jc = {}
    for tr in rows[1:]:
        for k, tc in enumerate(tr.findall("w:tc", NS)):
            jc = tc.find(".//w:pPr/w:jc", NS)
            if jc is not None:
                col_jc[k] = jc.get(q("w:val"))
    for r_i, tr in enumerate(rows):
        header = r_i == 0
        trPr = tr.find("w:trPr", NS)
        if trPr is None:
            trPr = etree.Element(q("w:trPr")); tr.insert(0, trPr)
        if header and trPr.find("w:tblHeader", NS) is None:
            trPr.append(X("<w:tblHeader/>"))
        if trPr.find("w:cantSplit", NS) is None:
            trPr.insert(0, X("<w:cantSplit/>"))
        for k, tc in enumerate(tr.findall("w:tc", NS)):
            tcPr = tc.find("w:tcPr", NS)
            if tcPr is None:
                tcPr = etree.Element(q("w:tcPr")); tc.insert(0, tcPr)
            tcW = tcPr.find("w:tcW", NS)
            if tcW is None:
                tcW = etree.SubElement(tcPr, q("w:tcW"))
            tcW.set(q("w:w"), str(new[k] if k < len(new) else 1000)); tcW.set(q("w:type"), "dxa")
            for p in tc.findall("w:p", NS):
                set_style(p, "USBTabletextcolumnheading" if header else "USBTabletext")
                ppr = p.find("w:pPr", NS)
                jc = ppr.find("w:jc", NS)
                want = col_jc.get(k)
                if header:
                    want = "center" if want in ("right", "end") else (want if want == "center" else "left")
                if want:
                    if jc is None:
                        jc = etree.SubElement(ppr, q("w:jc"))
                    jc.set(q("w:val"), "right" if want == "end" else want)
                kn = ppr.find("w:keepNext", NS)
                if kn is not None:
                    ppr.remove(kn)
                # short tables stay on one page; long ones keep only the header and the first rows together
                # (the header row repeats on each page) - the style itself keeps every row with the next
                keep = (len(rows) <= 14 and r_i < len(rows) - 1) or r_i < 2
                ppr.insert(1, X("<w:keepNext/>" if keep else '<w:keepNext w:val="0"/>'))
                for mr in p.iter("{%s}r" % M):
                    wrpr = mr.find("w:rPr", NS)
                    if wrpr is None:
                        wrpr = etree.Element(q("w:rPr"))
                        mpr = mr.find("{%s}rPr" % M)
                        mr.insert(1 if mpr is not None else 0, wrpr)
                    for e in wrpr.findall("w:sz", NS) + wrpr.findall("w:szCs", NS):
                        wrpr.remove(e)
                    wrpr.append(X('<w:sz w:val="20"/>')); wrpr.append(X('<w:szCs w:val="20"/>'))
                for r_ in p.iter(q("w:r")):
                    rpr = r_.find("w:rPr", NS)
                    if rpr is None:
                        rpr = etree.Element(q("w:rPr")); r_.insert(0, rpr)
                    for b in rpr.findall("w:b", NS):
                        rpr.remove(b)
                    rpr.insert(0, X("<w:b/>" if header else '<w:b w:val="0"/>'))
                    if r_.tag == "{%s}r" % M:
                        continue


# ---------------------------------------------------------------- lists
def list_kinds(numbering_xml):
    n = etree.fromstring(numbering_xml)
    absfmt = {}
    for a in n.findall("w:abstractNum", NS):
        lvl = a.find("w:lvl[@w:ilvl='0']", NS)
        f = lvl.find("w:numFmt", NS) if lvl is not None else None
        absfmt[a.get(q("w:abstractNumId"))] = f.get(q("w:val")) if f is not None else None
    kinds = {}
    for num in n.findall("w:num", NS):
        a = num.find("w:abstractNumId", NS).get(q("w:val"))
        kinds[num.get(q("w:numId"))] = absfmt.get(a)
    return n, kinds


def restart_num(numbering, abstract_id, new_id):
    numbering.append(X(f'<w:num w:numId="{new_id}"><w:abstractNumId w:val="{abstract_id}"/>'
                       f'<w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride></w:num>'))


# ---------------------------------------------------------------- main transform
def transform(doc_xml, numbering_xml, meta, figdir):
    root = etree.fromstring(doc_xml)
    body = root.find("w:body", NS)
    numbering, kinds = list_kinds(numbering_xml)
    next_num = 5000
    children = list(body)
    final_sect = body.find("w:sectPr", NS)
    refs_mode = False
    prev = None
    for el in children:
        if el.tag != q("w:p"):
            if el.tag == q("w:tbl") and refs_mode is False:
                style_table(el)
            prev = el
            continue
        t = ptext(el).strip()
        if t.startswith("QQ"):
            key = t.split("|")[0]
            parts = t.split("|")
            idx = body.index(el)
            if key == "QQTITLEPAGE":
                for k, x in enumerate(title_page(parts[1], parts[2])):
                    body.insert(idx + k, x)
                body.remove(el)
            elif key == "QQSECTIONHEADING":
                refs_mode = parts[1] == "References" and False
                body.replace(el, X(para("Sectionheading", run(parts[1]))))
                refs_mode = parts[1] == "References"
            elif key == "QQTOCHEADING":
                body.replace(el, heading_like(parts[1])); refs_mode = False
            elif key == "QQTOC":
                body.replace(el, toc_para('TOC \\h \\z \\t "Heading 1,1,Heading 2,2,Heading 3,3,Section heading,1"', "TOC1",
                                          "Right-click and choose Update Field to show the table of contents."))
            elif key == "QQLOT":
                body.replace(el, toc_para('TOC \\h \\z \\c "Table"', "TableofFigures",
                                          "Right-click and choose Update Field to show the list of tables."))
            elif key == "QQLOF":
                body.replace(el, toc_para('TOC \\h \\z \\c "Figure"', "TableofFigures",
                                          "Right-click and choose Update Field to show the list of figures."))
            elif key == "QQABBR":
                body.replace(el, X(para("USBlistoftables", run(parts[1]) + "<w:r><w:tab/></w:r>" + run("|".join(parts[2:])),
                                        '<w:tabs><w:tab w:val="clear" w:pos="1418"/><w:tab w:val="left" w:pos="1701"/></w:tabs>'
                                        '<w:spacing w:after="80"/>')))
            elif key == "QQENDFRONT":
                sect = copy.deepcopy(final_sect)
                body.replace(el, X(f"<w:p><w:pPr></w:pPr></w:p>"))
                body[idx].find("w:pPr", NS).append(sect)
                refs_mode = False
            elif key == "QQEQ":
                mp = body[idx - 1]
                if mp.tag != q("w:p") or mp.find(".//m:oMathPara", NS) is None:
                    raise SystemExit(f"QQEQ|{parts[1]} does not follow a display equation")
                body.remove(mp)
                body.replace(el, equation_table(mp, parts[1]))
            elif key in ("QQTABCAP", "QQFIGCAP"):
                caption("Table" if key == "QQTABCAP" else "Figure", parts[1], el)
            elif key == "QQTABSOURCE":
                body.replace(el, X(para("USBtablesource", run("|".join(parts[1:])))))
            elif key == "QQAPPENDIX":
                body.replace(el, X(para("Sectionheading", run(f"APPENDIX {parts[1]}") + "<w:r><w:br/></w:r>" + run(parts[2]))))
                refs_mode = False
            elif key == "QQREFSTART":
                body.remove(el)
            elif key == "QQDRAWING":
                new = drawings.build(parts[1])
                for k, x in enumerate(new):
                    body.insert(idx + k, x)
                body.remove(el)
            else:
                raise SystemExit("unknown marker " + key)
            continue
        st = style_of(el)
        if refs_mode and st in ("FirstParagraph", "BodyText", None):
            set_style(el, "USBReferences")
            ppr = el.find("w:pPr", NS)
            ppr.append(X('<w:jc w:val="left"/>'))
            continue
        if st == "Heading1":
            ppr = el.find("w:pPr", NS)
            el.insert(list(el).index(ppr) + 1, X("<w:r><w:br/></w:r>"))
        numPr = el.find("w:pPr/w:numPr", NS)
        if numPr is not None and st not in ("Heading1", "Heading2", "Heading3", "Heading4"):
            nid = numPr.find("w:numId", NS).get(q("w:val"))
            el.set("_list", nid)
        elif st in ("FirstParagraph", "BodyText", "Compact"):
            set_style(el, None)
        elif st == "BlockText":
            set_style(el, None)
            el.find("w:pPr", NS).append(X('<w:ind w:left="567" w:right="567"/>'))
        if el.find(".//w:drawing", NS) is not None and el.find(".//m:oMath", NS) is None:
            set_style(el, None)
            ppr = el.find("w:pPr", NS)
            ppr.append(X('<w:keepNext/>')); ppr.append(X('<w:spacing w:before="120" w:after="0" w:line="240" w:lineRule="auto"/>'))
            ppr.append(X('<w:jc w:val="center"/>'))
        if el.find("m:oMathPara", NS) is not None or el.find(".//m:oMathPara", NS) is not None:
            if style_of(el) is None:
                el.find("w:pPr", NS).append(X('<w:keepLines/>'))
        prev = el
    # lists: group consecutive paragraphs with the same pandoc list id
    paras = list(body)
    i = 0
    while i < len(paras):
        el = paras[i]
        nid = el.get("_list") if el.tag == q("w:p") else None
        if not nid:
            i += 1; continue
        j = i
        while j + 1 < len(paras) and paras[j + 1].tag == q("w:p") and paras[j + 1].get("_list") == nid:
            j += 1
        bullet = kinds.get(nid) == "bullet"
        if not bullet:
            restart_num(numbering, "7", next_num); my = next_num; next_num += 1
        for k in range(i, j + 1):
            p = paras[k]
            del p.attrib["_list"]
            last = k == j
            ppr = p.find("w:pPr", NS)
            ppr.remove(ppr.find("w:numPr", NS))
            if bullet:
                set_style(p, "USBBulletlast" if last else "USBBullets")
            else:
                set_style(p, "USBiiiiiilast" if last else "USBiiiiii")
                ppr.insert(1, X(f'<w:numPr><w:ilvl w:val="0"/><w:numId w:val="{my}"/></w:numPr>'))
        i = j + 1
    for el in body.iter():
        if "_list" in el.attrib:
            del el.attrib["_list"]
    # LibreOffice's equation import has three faults that Word does not share; the
    # rewrites below leave Word's rendering unchanged:
    #  - a formula starting with a relation ("> n"): put a word joiner (U+2060) in front;
    #  - pandoc's empty separator character on single-item delimiters (m:d): drop it;
    #  - a lone "|" run: mark it as normal text (m:nor), as Word draws it the same.
    MR, MT, MRPR = "{%s}r" % M, "{%s}t" % M, "{%s}rPr" % M
    RELS = "<>=:\u2264\u2265\u2260\u2248\u223c\u226a\u226b\u2208\u2282\u2286\u2192\u2190\u21a6\u2261\u2254\u221d"
    containers = {"{%s}%s" % (M, k) for k in ("oMath", "e", "num", "den", "sub", "sup", "fName", "lim", "deg")}
    for box in [el for el in root.iter() if el.tag in containers]:
        first = next((c for c in box if not c.tag.endswith("Pr")), None)
        if first is None:                            # empty cell, e.g. an aligned row starting with &
            zr = etree.SubElement(box, MR); etree.SubElement(zr, MT).text = "\u2060"
            continue
        if first.tag != MR:
            continue
        t = first.find(MT)
        if t is not None and (t.text or "")[:1] in RELS:
            zr = etree.Element(MR); zt = etree.SubElement(zr, MT); zt.text = "\u2060"
            box.insert(list(box).index(first), zr)
    for t in root.iter(MT):
        if t.text == "\\":
            t.text = "\u2216"                       # \setminus: pandoc writes a backslash
        elif t.text == "*":
            t.text = "\u2217"                       # t^*: asterisk operator (LibreOffice cannot import a bare *)
    # \underbrace / \overbrace: pandoc stacks a small brace glyph (limLow/limUpp with lim = U+23DF/U+23DE);
    # Word's own form is a stretched group character (m:groupChr). Convert, keeping the label.
    for tag, ch, pos, vj in (("limLow", "\u23df", "bot", "top"), ("limUpp", "\u23de", "top", "bot")):
        for outer in list(root.iter("{%s}%s" % (M, tag))):
            lim = outer.find("{%s}lim" % M)
            texts = "".join(t.text or "" for t in lim.iter(MT)) if lim is not None else ""
            if texts.strip() != ch:
                continue
            e = outer.find("{%s}e" % M)
            g = etree.Element("{%s}groupChr" % M)
            gpr = etree.SubElement(g, "{%s}groupChrPr" % M)
            etree.SubElement(gpr, "{%s}chr" % M).set("{%s}val" % M, ch)
            etree.SubElement(gpr, "{%s}pos" % M).set("{%s}val" % M, pos)
            etree.SubElement(gpr, "{%s}vertJc" % M).set("{%s}val" % M, vj)
            g.append(e)
            outer.getparent().replace(outer, g)
    for d in root.iter("{%s}d" % M):
        dpr = d.find("{%s}dPr" % M)
        es = d.findall("{%s}e" % M)
        if dpr is None:
            continue
        sep = dpr.find("{%s}sepChr" % M)
        if len(es) > 1:                              # \big[ a \big| b \big]: one part with an explicit separator
            ch = sep.get("{%s}val" % M) if sep is not None else "|"
            for e in es[1:]:
                sr = etree.SubElement(es[0], MR)
                etree.SubElement(etree.SubElement(sr, MRPR), "{%s}nor" % M)
                etree.SubElement(sr, MT).text = ch or "|"
                for c in list(e):
                    es[0].append(c)
                d.remove(e)
        if sep is not None:
            dpr.remove(sep)
    for mr in root.iter(MR):
        t = mr.find(MT)
        if t is not None and (t.text or "").strip() in ("|", "\u2016", "\u2225"):
            rpr = mr.find(MRPR)
            if rpr is None:
                rpr = etree.Element(MRPR); mr.insert(0, rpr)
            if rpr.find("{%s}nor" % M) is None:
                rpr.append(etree.Element("{%s}nor" % M))
    # identifiers such as AY_embed: LibreOffice reads "_" as a subscript; as normal text both agree
    for mr in list(root.iter(MR)):
        t = mr.find(MT)
        if t is not None and "_" in (t.text or ""):
            rpr = mr.find(MRPR)
            if rpr is None:
                rpr = etree.Element(MRPR); mr.insert(0, rpr)
            if rpr.find("{%s}nor" % M) is None:
                etree.SubElement(rpr, "{%s}nor" % M)
    # \text{(...)}: LibreOffice escapes brackets inside text runs; make the brackets maths symbols
    for mr in list(root.iter(MR)):
        rpr = mr.find(MRPR); t = mr.find(MT)
        if rpr is None or t is None or rpr.find("{%s}nor" % M) is None:
            continue
        txt = t.text or ""
        if "(" not in txt and ")" not in txt:
            continue
        parts = [p for p in re.split(r"([()])", txt) if p != ""]
        parent = mr.getparent(); pos = list(parent).index(mr)
        for k, p in enumerate(parts):
            nr = copy.deepcopy(mr) if p not in "()" else etree.Element(MR)
            if p in "()":
                etree.SubElement(nr, MT).text = p
            else:
                nr.find(MT).text = p
                nr.find(MT).set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
            parent.insert(pos + k, nr)
        parent.remove(mr)
    # schema: m:nor and m:scr/m:sty are alternatives; m:count comes before m:mcJc
    for rpr in root.iter(MRPR):
        if rpr.find("{%s}nor" % M) is not None:
            for k in ("sty", "scr"):
                for e in rpr.findall("{%s}%s" % (M, k)):
                    rpr.remove(e)
    for rpr in root.iter(MRPR):                     # m:rPr order: lit, (nor | scr, sty), brk, aln
        order = {"lit": 0, "nor": 1, "scr": 2, "sty": 3, "brk": 4, "aln": 5}
        kids = list(rpr)
        if [etree.QName(k).localname for k in kids] != sorted([etree.QName(k).localname for k in kids], key=lambda n: order.get(n, 9)):
            for k in kids:
                rpr.remove(k)
            for k in sorted(kids, key=lambda e: order.get(etree.QName(e).localname, 9)):
                rpr.append(k)
    for mcpr in root.iter("{%s}mcPr" % M):
        cnt = mcpr.find("{%s}count" % M)
        if cnt is not None:
            mcpr.remove(cnt); mcpr.insert(0, cnt)
    # body section: Arabic numbers from 1, no separate first page
    pg = final_sect.find("w:pgNumType", NS)
    pg.attrib.pop(q("w:fmt"), None); pg.set(q("w:start"), "1")
    tp = final_sect.find("w:titlePg", NS)
    if tp is not None:
        final_sect.remove(tp)
    return etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True), \
        etree.tostring(numbering, xml_declaration=True, encoding="UTF-8", standalone=True)


SETTINGS_ORDER = ["writeProtection", "view", "zoom", "removePersonalInformation", "removeDateAndTime", "doNotDisplayPageBoundaries",
    "displayBackgroundShape", "printPostScriptOverText", "printFractionalCharacterWidth", "printFormsData", "embedTrueTypeFonts",
    "embedSystemFonts", "saveSubsetFonts", "saveFormsData", "mirrorMargins", "alignBordersAndEdges", "bordersDoNotSurroundHeader",
    "bordersDoNotSurroundFooter", "gutterAtTop", "hideSpellingErrors", "hideGrammaticalErrors", "activeWritingStyle", "proofState",
    "formsDesign", "attachedTemplate", "linkStyles", "stylePaneFormatFilter", "stylePaneSortMethod", "documentType", "mailMerge",
    "revisionView", "trackRevisions", "doNotTrackMoves", "doNotTrackFormatting", "documentProtection", "autoFormatOverride",
    "styleLockTheme", "styleLockQFSet", "defaultTabStop", "autoHyphenation", "consecutiveHyphenLimit", "hyphenationZone",
    "doNotHyphenateCaps", "showEnvelope", "summaryLength", "clickAndTypeStyle", "defaultTableStyle", "evenAndOddHeaders",
    "bookFoldRevPrinting", "bookFoldPrinting", "bookFoldPrintingSheets", "drawingGridHorizontalSpacing", "drawingGridVerticalSpacing",
    "displayHorizontalDrawingGridEvery", "displayVerticalDrawingGridEvery", "doNotUseMarginsForDrawingGridOrigin",
    "drawingGridHorizontalOrigin", "drawingGridVerticalOrigin", "doNotShadeFormData", "noPunctuationKerning",
    "characterSpacingControl", "printTwoOnOne", "strictFirstAndLastChars", "noLineBreaksAfter", "noLineBreaksBefore",
    "savePreviewPicture", "doNotValidateAgainstSchema", "saveInvalidXml", "ignoreMixedContent", "alwaysShowPlaceholderText",
    "doNotDemarcateInvalidXml", "saveXmlDataOnly", "useXSLTWhenSaving", "saveThroughXslt", "showXMLTags",
    "alwaysMergeEmptyNamespace", "updateFields", "hdrShapeDefaults", "footnotePr", "endnotePr", "compat", "docVars", "rsids",
    "mathPr", "attachedSchema", "themeFontLang", "clrSchemeMapping", "doNotIncludeSubdocsInStats", "doNotAutoCompressPictures",
    "forceUpgrade", "captions", "readModeInkLockDown", "smartTagType", "schemaLibrary", "shapeDefaults",
    "doNotEmbedSmartTags", "decimalSymbol", "listSeparator"]


def package_fixes(work):
    w = os.path.join(work, "word")
    # settings: schema order (pandoc writes its own order), update fields on opening
    sx = os.path.join(w, "settings.xml")
    st = etree.parse(sx); r = st.getroot()
    if r.find("w:updateFields", NS) is None:
        u = etree.SubElement(r, q("w:updateFields")); u.set(q("w:val"), "true")
    rank = {n: i for i, n in enumerate(SETTINGS_ORDER)}
    kids = list(r)
    for k in kids:
        r.remove(k)
    for k in sorted(kids, key=lambda e: rank.get(etree.QName(e).localname, len(rank))):
        r.append(k)
    st.write(sx, xml_declaration=True, encoding="UTF-8", standalone=True)
    # numbering: pandoc writes 4-digit nsid values; the schema wants 8 hex digits
    nx = os.path.join(w, "numbering.xml")
    n = open(nx, encoding="utf-8").read()
    n = re.sub(r'(<w:nsid w:val=")([0-9A-Fa-f]{1,7})(")', lambda m: m.group(1) + m.group(2).upper().rjust(8, "0") + m.group(3), n)
    open(nx, "w", encoding="utf-8").write(n)
    # media copied from the template but not used: remove
    rels = "".join(open(os.path.join(base, f), encoding="utf-8").read()
                   for base, _, fs in os.walk(work) for f in fs if f.endswith(".rels"))
    mdir = os.path.join(w, "media")
    if os.path.isdir(mdir):
        for f in os.listdir(mdir):
            if "media/" + f not in rels:
                os.remove(os.path.join(mdir, f))
    # content types for images
    ct = os.path.join(work, "[Content_Types].xml")
    c = open(ct, encoding="utf-8").read()
    for ext, typ in (("png", "image/png"), ("jpeg", "image/jpeg"), ("jpg", "image/jpeg")):
        if f'Extension="{ext}"' not in c:
            c = c.replace("<Default ", f'<Default Extension="{ext}" ContentType="{typ}"/><Default ', 1)
    open(ct, "w", encoding="utf-8").write(c)


def build(doc):
    os.makedirs(OUT, exist_ok=True)
    md = os.path.join(BUILD, doc + ".md")
    meta = json.load(open(os.path.join(BUILD, doc + ".json"), encoding="utf-8"))
    raw = os.path.join(BUILD, doc + ".raw.docx")
    subprocess.run(["pandoc", md, "-f", "markdown+tex_math_dollars+pipe_tables+implicit_figures-smart",
                    "-o", raw, "--reference-doc", TEMPLATE, "--resource-path", BUILD], check=True)
    work = os.path.join(BUILD, doc + "_unz")
    shutil.rmtree(work, ignore_errors=True)
    with zipfile.ZipFile(raw) as z:
        z.extractall(work)
    dx = os.path.join(work, "word", "document.xml"); nx = os.path.join(work, "word", "numbering.xml")
    d, n = transform(open(dx, "rb").read(), open(nx, "rb").read(), meta, os.path.join(BUILD, "figures"))
    open(dx, "wb").write(d); open(nx, "wb").write(n)
    # Word refreshes the table of contents and the lists on opening
    sx = os.path.join(work, "word", "settings.xml")
    s = open(sx, encoding="utf-8").read()
    s = re.sub(r'<w:lang w:val="[^"]*"', '<w:lang w:val="en-ZA"', s)
    open(sx, "w", encoding="utf-8").write(s)
    # South African English for the spelling checker
    stx = os.path.join(work, "word", "styles.xml")
    st = open(stx, encoding="utf-8").read()
    st = re.sub(r'(<w:docDefaults>.*?<w:lang )w:val="[^"]*"', r'\1w:val="en-ZA"', st, count=1, flags=re.S)
    open(stx, "w", encoding="utf-8").write(st)
    package_fixes(work)
    out = os.path.join(OUT, doc + ".docx")
    if os.path.exists(out):
        os.remove(out)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(work):
            for f in files:
                full = os.path.join(base, f)
                z.write(full, os.path.relpath(full, work))
    print("wrote", out)


if __name__ == "__main__":
    for d in sys.argv[1:]:
        build(d)
