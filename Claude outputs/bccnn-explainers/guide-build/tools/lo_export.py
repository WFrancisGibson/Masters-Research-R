"""Open each .docx in LibreOffice (headless, via UNO), update all fields and
indexes (table of contents, lists of tables and figures, captions), export a
PDF, and dump the generated index texts to <name>.indexes.json.

  python3 lo_export.py out/d1.docx [out/d2.docx ...]
"""
import json, os, socket, subprocess, sys, tempfile, time

import uno
from com.sun.star.beans import PropertyValue


def pv(name, value):
    p = PropertyValue(); p.Name = name; p.Value = value
    return p


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    return port


def main(paths):
    port = free_port()
    profile = tempfile.mkdtemp(prefix="lo_profile_")
    env = dict(os.environ, SAL_USE_VCLPLUGIN="svp")
    proc = subprocess.Popen(["soffice", f"-env:UserInstallation=file://{profile}", "--headless", "--invisible",
                             "--norestore", "--nologo", f"--accept=socket,host=127.0.0.1,port={port};urp;"],
                            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext("com.sun.star.bridge.UnoUrlResolver", local)
    ctx = None
    for _ in range(120):
        try:
            ctx = resolver.resolve(f"uno:socket,host=127.0.0.1,port={port};urp;StarOffice.ComponentContext")
            break
        except Exception:
            time.sleep(0.5)
    if ctx is None:
        proc.kill(); raise SystemExit("could not connect to LibreOffice")
    desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
    try:
        for path in paths:
            url = uno.systemPathToFileUrl(os.path.abspath(path))
            doc = desktop.loadComponentFromURL(url, "_blank", 0, (pv("Hidden", True),))
            # the caption counters are hidden in Word (SEQ \\h); LibreOffice shows them, so blank them here
            fe = doc.getTextFields().createEnumeration()
            while fe.hasMoreElements():
                f = fe.nextElement()
                if f.supportsService("com.sun.star.text.TextField.SetExpression"):
                    try:
                        if f.getPropertyValue("VariableName") in ("Table", "Figure"):
                            f.setPropertyValue("NumberingType", 5)      # NumberingType.NUMBER_NONE
                    except Exception:
                        pass
            for _ in range(2):                       # fields first, then indexes, twice for page numbers
                doc.getTextFields().refresh()
                idx = doc.getDocumentIndexes()
                for i in range(idx.getCount()):
                    idx.getByIndex(i).update()
                doc.refresh()
            texts = []
            idx = doc.getDocumentIndexes()
            for i in range(idx.getCount()):
                ix = idx.getByIndex(i)
                texts.append({"service": ix.getImplementationName(), "text": ix.getAnchor().getString()})
            pdf = os.path.splitext(os.path.abspath(path))[0] + ".pdf"
            doc.storeToURL(uno.systemPathToFileUrl(pdf), (pv("FilterName", "writer_pdf_Export"),))
            doc.close(True)
            json.dump(texts, open(os.path.splitext(path)[0] + ".indexes.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            print("exported", pdf, "| indexes:", [len(t["text"].splitlines()) for t in texts])
    finally:
        try:
            desktop.terminate()
        except Exception:
            pass
        time.sleep(1)
        proc.kill()


if __name__ == "__main__":
    main(sys.argv[1:])
