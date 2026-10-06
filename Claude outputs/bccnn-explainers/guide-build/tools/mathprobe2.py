"""Exact per-formula probe: every formula of a built .docx on its own page; failures are
mapped back to the LaTeX source (build/<doc>.md) by document order."""
import re, subprocess, sys, zipfile, os
from lxml import etree
M = "http://schemas.openxmlformats.org/officeDocument/2006/math"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
doc = sys.argv[1]
src = f"out/{doc}.docx"; out = f"build/probe2_{doc}.docx"
md = open(f"build/{doc}.md", encoding="utf-8").read()
md = re.sub(r"`[^`\n]*`", "", md)
latex = []
for m in re.finditer(r"\$\$(.*?)\$\$|\$([^$\n]+?)\$", md, re.S):
    latex.append(("D " if m.group(1) is not None else "I ") + " ".join((m.group(1) or m.group(2)).split()))
z = zipfile.ZipFile(src); root = etree.fromstring(z.read("word/document.xml")); body = root.find("{%s}body" % W)
maths = [el for el in root.iter() if el.tag == "{%s}oMathPara" % M or (el.tag == "{%s}oMath" % M and el.getparent().tag != "{%s}oMathPara" % M)]
sect = body.find("{%s}sectPr" % W)
for c in list(body):
    body.remove(c)
for k, m in enumerate(maths):
    p = etree.SubElement(body, "{%s}p" % W)
    ppr = etree.SubElement(p, "{%s}pPr" % W); etree.SubElement(ppr, "{%s}pageBreakBefore" % W)
    r = etree.SubElement(p, "{%s}r" % W); t = etree.SubElement(r, "{%s}t" % W); t.text = f"Q{k:04d} "
    p.append(m)
body.append(sect)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
    for it in z.infolist():
        o.writestr(it, etree.tostring(root) if it.filename == "word/document.xml" else z.read(it.filename))
prof = "file:///tmp/claude-0/-home-user-Masters-Research-R/1cd9441d-4075-5511-a8f5-fb2214f015b5/scratchpad/lo_prof"
subprocess.run(["soffice", f"-env:UserInstallation={prof}", "--headless", "--convert-to", "pdf", "--outdir", "build", out],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)
pages = subprocess.run(["pdftotext", out.replace(".docx", ".pdf"), "-"], capture_output=True, text=True).stdout.split("\f")
bad = []
for pg in pages:
    m = re.search(r"Q(\d{4})", pg)
    if m and "¿" in pg:
        bad.append(int(m.group(1)))
print(f"{doc}: {len(maths)} formulas in docx, {len(latex)} in source, {len(bad)} failing")
for k in bad:
    print("   ", k, latex[k] if k < len(latex) and len(maths) == len(latex) else "(order mismatch)", )
