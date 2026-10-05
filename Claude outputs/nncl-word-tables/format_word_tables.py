"""Formats the tables of a pandoc-made .docx: grid borders, Arial, bold
centred header row, fixed column widths, A4 page with 2 cm margins.
usage: python format_word_tables.py <file.docx> [widths] [font size]
widths: column widths in twips, comma separated (default: the eight columns
of the optimiser tables); font size in half-points (default 20 = 10 pt)"""
import os
import re
import sys
import zipfile

path = sys.argv[1]
widths = [1250, 1200, 1200, 1200, 1200, 1500, 1200, 888]   # twips, sum 9638
if len(sys.argv) > 2:
    widths = [int(w) for w in sys.argv[2].split(",")]
half_points = sys.argv[3] if len(sys.argv) > 3 else "20"
border = ' w:val="single" w:sz="4" w:space="0" w:color="000000" />'
borders = ("<w:tblBorders>"
           + "".join("<w:" + side + border for side in
                     ("top", "left", "bottom", "right", "insideH", "insideV"))
           + "</w:tblBorders>")
margins = ('<w:tblCellMar><w:left w:w="80" w:type="dxa" />'
           '<w:right w:w="80" w:type="dxa" /></w:tblCellMar>')
font = '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial" />'
size = '<w:sz w:val="%s" /><w:szCs w:val="%s" />' % (half_points, half_points)


def format_row(row, header):
    cells = re.findall(r"<w:tc>.*?</w:tc>", row, flags=re.S)
    assert len(cells) == len(widths)
    for k, cell in enumerate(cells):
        tc_pr = ('<w:tcPr><w:tcW w:w="%d" w:type="dxa" />'
                 '<w:vAlign w:val="center" /></w:tcPr>' % widths[k])
        new = re.sub(r"<w:tcPr ?/>|<w:tcPr>.*?</w:tcPr>", tc_pr, cell,
                     count=1, flags=re.S)
        r_pr = "<w:rPr>" + font + ("<w:b /><w:bCs />" if header else "") \
            + size + "</w:rPr>"
        new = new.replace("<w:r><w:t", "<w:r>" + r_pr + "<w:t")
        if header:
            new = re.sub(r'<w:jc w:val="\w+" />', '<w:jc w:val="center" />',
                         new)
        row = row.replace(cell, new, 1)
    return row


def format_table(match):
    tbl = match.group(0)
    grid = ("<w:tblGrid>"
            + "".join('<w:gridCol w:w="%d" />' % w for w in widths)
            + "</w:tblGrid>")
    tbl = re.sub(r"<w:tblGrid>.*?</w:tblGrid>", grid, tbl, flags=re.S)
    tbl = re.sub(r"<w:tblW [^>]*/>",
                 '<w:tblW w:type="dxa" w:w="%d" />' % sum(widths)
                 + borders, tbl, count=1)
    tbl = re.sub(r"(<w:tblLayout [^>]*/>)", r"\1" + margins, tbl, count=1)
    rows = re.findall(r"<w:tr>.*?</w:tr>", tbl, flags=re.S)
    for k, row in enumerate(rows):
        tbl = tbl.replace(row, format_row(row, header=(k == 0)), 1)
    return tbl


section = ('<w:sectPr><w:footnotePr><w:numRestart w:val="eachSect" />'
           '</w:footnotePr><w:pgSz w:w="11906" w:h="16838" />'
           '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" '
           'w:left="1134" w:header="708" w:footer="708" w:gutter="0" />'
           '</w:sectPr>')
tmp = path + ".tmp"
with zipfile.ZipFile(path) as zin, \
        zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        data = zin.read(item.filename)
        if item.filename == "word/document.xml":
            doc = data.decode("utf-8")
            doc, n = re.subn(r"<w:tbl>.*?</w:tbl>", format_table, doc,
                             flags=re.S)
            doc = re.sub(r"<w:sectPr>.*?</w:sectPr>", section, doc,
                         flags=re.S)
            print("tables formatted:", n)
            data = doc.encode("utf-8")
        zout.writestr(item, data)
os.replace(tmp, path)
