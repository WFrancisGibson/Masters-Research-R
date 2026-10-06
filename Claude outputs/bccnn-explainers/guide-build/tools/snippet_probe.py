"""Run LaTeX snippets through pandoc + build.transform and LibreOffice; print which fail."""
import os, subprocess, sys, zipfile, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build
snips = [l.rstrip("\n") for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
md = "\n\n".join(f"S{k:03d}: ${s}$" for k, s in enumerate(snips))
work = os.path.join(build.ROOT, "build", "snip"); os.makedirs(work, exist_ok=True)
open(f"{work}/s.md", "w", encoding="utf-8").write(md)
subprocess.run(["pandoc", f"{work}/s.md", "-o", f"{work}/s.docx", "--reference-doc", build.TEMPLATE], check=True)
z = zipfile.ZipFile(f"{work}/s.docx")
d, n = build.transform(z.read("word/document.xml"), z.read("word/numbering.xml"), {}, "")
with zipfile.ZipFile(f"{work}/t.docx", "w") as o:
    for it in z.infolist():
        o.writestr(it, d if it.filename == "word/document.xml" else (n if it.filename == "word/numbering.xml" else z.read(it.filename)))
prof = "file:///tmp/claude-0/-home-user-Masters-Research-R/1cd9441d-4075-5511-a8f5-fb2214f015b5/scratchpad/lo_prof"
subprocess.run(["soffice", f"-env:UserInstallation={prof}", "--headless", "--convert-to", "pdf", "--outdir", work, f"{work}/t.docx"],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
txt = subprocess.run(["pdftotext", f"{work}/t.pdf", "-"], capture_output=True, text=True).stdout
for b in re.split(r"(?=S\d{3}: )", txt):
    if b.startswith("S"):
        k = int(b[1:4]); flag = "FAIL" if "¿" in b else "ok  "
        print(flag, snips[k], "=>", " ".join(b[6:].split())[:80])
