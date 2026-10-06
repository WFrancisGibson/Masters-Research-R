"""Resolve the tokenised thesis-format Markdown sources (src/d1..d4.md) into
pandoc-ready Markdown (build/dX.md) plus metadata (build/dX.json).

Numbering follows the Research Assignment Guide: chapters 1, 2, ...; headings
X.Y, X.Y.Z, X.Y.Z.W; equations, tables and figures X.n within chapter X
(A.n in Appendix A). References between documents are resolved with one
global label table.

Tokens (see SPEC.md):
  headings  "# TITLE {#id}", "# REFERENCES {.references}", "# TITLE {.appendix #id}"
  ⟦eq:id⟧ line after a display, ⟦tabcap:id|text⟧, ⟦figcap:id|text⟧,
  ⟦tabsource|text⟧, ⟦ref:id⟧
Markers written for build.py: QQTITLEPAGE, QQSECTIONHEADING|t, QQTOCHEADING|t,
  QQTOC, QQLOT, QQLOF, QQABBR|a|m, QQENDFRONT, QQEQ|n, QQTABCAP|n|t,
  QQFIGCAP|n|t, QQTABSOURCE|t, QQAPPENDIX|L|t, QQREFSTART
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC, OUT = os.path.join(ROOT, "src"), os.path.join(ROOT, "build")
DOCS = [d for d in ["d1", "d2", "d3", "d4", "d5"] if os.path.exists(os.path.join(SRC, d + ".md"))]

HEAD = re.compile(r"^(#{1,4})\s+(.*?)\s*(?:\{([^}]*)\})?\s*$")
EQ = re.compile(r"^⟦eq:([^⟧|]+)⟧\s*$")
TABCAP = re.compile(r"^⟦tabcap:([^|⟧]+)\|(.*)⟧\s*$")
FIGCAP = re.compile(r"^⟦figcap:([^|⟧]+)\|(.*)⟧\s*$")
TABSRC = re.compile(r"^⟦tabsource\|(.*)⟧\s*$")
REF = re.compile(r"⟦ref:([^⟧]+)⟧")

GUIDE_REF = ("Department of Statistics and Actuarial Science. 2026. *Research assignment guide*. "
             "Last updated 28 January 2026. Stellenbosch: Stellenbosch University.")
NOTE = [
    "These notes were prepared with the generative artificial intelligence (AI) tool Claude (Anthropic) "
    "at the request of the student, as study material on the blended cross-classified neural network "
    "(bCCNN) strand of the research assignment. They explain the mathematics of the model, the code in "
    "the student’s repository (Masters-Research-R) and the literature that the code follows.",
    "The notes are not the student’s original work and are not intended for submission for "
    "assessment. Section 2.6.3 of the Research Assignment Guide (Department of Statistics and Actuarial "
    "Science, 2026: 7-8) prohibits the use of AI tools to generate content that is submitted for "
    "assessment and requires a declaration of any use of such tools. For this reason the plagiarism "
    "declaration and the declaration on the use of artificial intelligence tools of the Department "
    "template are not included. The layout follows the technical requirements in Chapter 5 of the Guide "
    "and the Department template.",
]


def attrs(a):
    return re.findall(r"#([\w.\-]+)", a or ""), re.findall(r"\.([\w\-]+)", a or "")


def split_front(text):
    meta, body = {}, text
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if m:
        for line in m.group(1).splitlines():
            k = re.match(r'^(\w+):\s*"?(.*?)"?\s*(#.*)?$', line)
            if k:
                meta[k.group(1)] = k.group(2)
        body = text[m.end():]
    blocks = {}
    def grab(mm):
        blocks[mm.group(1)] = mm.group(2).strip()
        return ""
    body = re.sub(r"(?ms)^:::\s*\{?\.?(abstract|keywords|abbreviations)\}?\s*\n(.*?)\n:::\s*$", grab, body)
    return meta, blocks, body


def number(doc, body, labels, info):
    ch = 0; h = [0, 0, 0]; eqn = tabn = fign = 0; scope = None; app = 0
    in_math = in_code = False
    for line in body.splitlines():
        s = line.strip()
        if s.startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        if s == "$$" or (s.startswith("$$") and not s.endswith("$$")) or (s.endswith("$$") and not s.startswith("$$") and in_math):
            in_math = not in_math
            continue
        if in_math:
            continue
        m = HEAD.match(line)
        if m:
            lvl, title, a = len(m.group(1)), m.group(2), m.group(3)
            ids, cls = attrs(a)
            if lvl == 1:
                if "references" in cls:
                    scope = "refs"; num = None
                elif "appendix" in cls:
                    app += 1; scope = chr(64 + app); num = scope; eqn = tabn = fign = 0
                else:
                    ch += 1; scope = str(ch); num = scope; h = [0, 0, 0]; eqn = tabn = fign = 0
                    info["chapters"].append((num, title))
            else:
                k = lvl - 2
                h[k] += 1
                for j in range(k + 1, 3):
                    h[j] = 0
                num = ".".join([scope] + [str(x) for x in h[:k + 1]])
            info["headings"].append((lvl, num, title))
            for i in ids:
                if i in labels:
                    info["errors"].append(f"duplicate id {i}")
                labels[i] = ("sec", num, doc)
            continue
        for rx, kind in ((EQ, "eq"), (TABCAP, "tab"), (FIGCAP, "fig")):
            mm = rx.match(s)
            if mm:
                if kind == "eq":
                    eqn += 1; n = eqn
                elif kind == "tab":
                    tabn += 1; n = tabn
                else:
                    fign += 1; n = fign
                num = f"{scope}.{n}"
                lid = mm.group(1)
                if lid in labels:
                    info["errors"].append(f"duplicate id {lid}")
                labels[lid] = (kind, num, doc)
                if kind in ("tab", "fig"):
                    info[kind + "s"].append((num, mm.group(2)))
                break


def emit(doc, meta, blocks, body, labels, info):
    out = []
    # ---- front matter
    out += ["QQTITLEPAGE|" + meta.get("title", "") + "|" + meta.get("subtitle", ""), ""]
    out += ["QQSECTIONHEADING|Note on the preparation of these notes", ""]
    for p in NOTE:
        out += [p, ""]
    out += ["QQSECTIONHEADING|Abstract", "", blocks.get("abstract", ""), ""]
    out += ["*Key words:* " + blocks.get("keywords", ""), ""]
    out += ["QQTOCHEADING|Table of contents", "", "QQTOC", ""]
    out += ["QQSECTIONHEADING|List of tables", "", "QQLOT", ""]
    if info["figs"]:
        out += ["QQSECTIONHEADING|List of figures", "", "QQLOF", ""]
    out += ["QQSECTIONHEADING|List of abbreviations and/or acronyms", ""]
    for row in blocks.get("abbreviations", "").splitlines():
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        if len(cells) >= 2 and not re.match(r"^:?-+:?$", cells[0]) and cells[0].lower() != "abbreviation":
            out += [f"QQABBR|{cells[0]}|{cells[1]}", ""]
    out += ["QQENDFRONT", ""]
    # ---- body
    in_math = in_code = False
    refs_mode = False
    for line in body.splitlines():
        s = line.strip()
        if s.startswith("```"):
            in_code = not in_code
        if in_code:
            out.append(line); continue
        if s == "$$" or (s.startswith("$$") and not s.endswith("$$")) or (s.endswith("$$") and not s.startswith("$$") and in_math):
            in_math = not in_math
            out.append(line); continue
        if in_math:
            out.append(line); continue
        m = HEAD.match(line)
        if m:
            lvl, title, a = len(m.group(1)), m.group(2), m.group(3)
            ids, cls = attrs(a)
            if lvl == 1 and "references" in cls:
                out += ["", "QQSECTIONHEADING|References", "", "QQREFSTART", ""]
                refs_mode = True
                continue
            if lvl == 1 and "appendix" in cls:
                L = labels[ids[0]][1] if ids and ids[0] in labels else "A"
                out += ["", f"QQAPPENDIX|{L}|{title.upper()}", ""]
                refs_mode = False
                continue
            refs_mode = False
            out += ["", "#" * lvl + " " + title, ""]
            continue
        mm = EQ.match(s)
        if mm:
            out += ["", "QQEQ|" + labels[mm.group(1)][1], ""]; continue
        mm = TABCAP.match(s)
        if mm:
            out += ["", f"QQTABCAP|{labels[mm.group(1)][1]}|{mm.group(2)}", ""]; continue
        mm = FIGCAP.match(s)
        if mm:
            out += ["", f"QQFIGCAP|{labels[mm.group(1)][1]}|{mm.group(2)}", ""]; continue
        mm = re.match(r"^!\[[^\]]*\]\(figures/(bccnn_architecture|rolling_origin_partitions)\.png\)(\{[^}]*\})?\s*$", s)
        if mm:
            out += ["", "QQDRAWING|" + ("architecture" if mm.group(1).startswith("bccnn") else "partitions"), ""]; continue
        mm = TABSRC.match(s)
        if mm:
            out += ["", "QQTABSOURCE|" + mm.group(1), ""]; continue
        out.append(line)
    text = "\n".join(out)
    # the Guide is cited in the note: make sure it is in the reference list
    if "Department of Statistics and Actuarial Science. 2026" not in text and "QQREFSTART" in text:
        start = text.index("QQREFSTART") + len("QQREFSTART")
        end = text.find("QQAPPENDIX|", start)
        end = len(text) if end < 0 else end
        refs = [p.strip() for p in re.split(r"\n\s*\n", text[start:end]) if p.strip()]
        refs.append(GUIDE_REF)
        key = lambda r: re.sub(r"[^a-z]", "", r.lower().replace("ä", "a").replace("ö", "o").replace("ü", "u"))
        refs.sort(key=key)
        text = text[:start] + "\n\n" + "\n\n".join(refs) + "\n\n" + text[end:]
    # cross-references
    def rep(mm):
        lid = mm.group(1)
        if lid not in labels:
            info["errors"].append(f"unresolved ref {lid}")
            return "??"
        kind, num, _ = labels[lid]
        info["used"].add(lid)
        return f"({num})" if kind == "eq" else num
    text = REF.sub(rep, text)
    return re.sub(r"\n{3,}", "\n\n", text)


def lint(doc, text, info):
    plain = re.sub(r"(?s)\$\$.*?\$\$", " ", text)
    plain = re.sub(r"\$[^$\n]*\$", " ", plain)
    plain = re.sub(r"`[^`]*`", " ", plain)
    plain = re.sub(r"(?m)^QQ.*$", " ", plain)
    quotes = re.sub(r"“[^”]*”|\"[^\"]*\"", " ", plain)       # leave quotations alone
    checks = {
        "second person": r"\b[Yy]ou(r|rs)?\b",
        "first person": r"(?<!companion )(?<!Appendix )\b(I|[Ww]e|[Oo]ur|[Uu]s)\b(?!\.)",
        "eq. prefix": r"\b[Ee]qs?\.\s*\(",
        "bold": r"\*\*",
        "etc": r"\betc\b",
        "contraction": r"\b\w+n't\b|\b(it's|that's|there's)\b",
        "comma thousands": r"\b\d{1,3},\d{3}\b",
        "American -ize": r"\b\w+(iz(e|es|ed|ing|ation|ations))\b",
        "American words": r"\b(color|behavior|favor|labeled|modeling|center|centered|analyze)\b",
        "tag": r"\\tag",
        "bare number refs": r"\b(Table|Figure|Section|Chapter)\s+\d",
    }
    for name, rx in checks.items():
        src = quotes if name in ("first person", "second person", "American -ize", "American words") else plain
        hits = sorted(set(m.group(0) for m in re.finditer(rx, src)))
        allowed = {"American -ize": {"size", "sizes", "seize", "prize"}}.get(name, set())
        hits = [h for h in hits if h.lower() not in allowed]
        if hits:
            info["lint"].append(f"{name}: {hits[:12]}")


def main():
    labels, raw, infos = {}, {}, {}
    for d in DOCS:
        text = open(os.path.join(SRC, d + ".md"), encoding="utf-8").read()
        meta, blocks, body = split_front(text)
        info = {"chapters": [], "headings": [], "tabs": [], "figs": [], "errors": [], "lint": [], "used": set()}
        number(d, body, labels, info)
        raw[d] = (meta, blocks, body); infos[d] = info
    os.makedirs(OUT, exist_ok=True)
    ok = True
    for d in DOCS:
        meta, blocks, body = raw[d]; info = infos[d]
        lint(d, body, info)
        text = emit(d, meta, blocks, body, labels, info)
        open(os.path.join(OUT, d + ".md"), "w", encoding="utf-8").write(text)
        own = [k for k, v in labels.items() if v[2] == d and v[0] in ("eq", "tab", "fig")]
        json.dump({"meta": meta, "chapters": info["chapters"], "headings": info["headings"],
                   "tables": info["tabs"], "figures": info["figs"]},
                  open(os.path.join(OUT, d + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print(f"{d}: {len(info['chapters'])} chapters, {sum(1 for h in info['headings'] if h[0] > 1)} sub-headings, "
              f"{sum(1 for k in own if labels[k][0] == 'eq')} equations, {len(info['tabs'])} tables, {len(info['figs'])} figures, "
              f"abstract {len(blocks.get('abstract', '').split())} words, {len([k for k in blocks.get('keywords', '').split(';') if k.strip()])} key words")
        for e in sorted(set(info["errors"])):
            print("   ERROR", e); ok = False
        for l in info["lint"]:
            print("   lint", l)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
