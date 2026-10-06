#!/bin/bash
# usage: build.sh in.md out.pdf   (run from the directory of in.md so images resolve)
set -e
TOOLS="$(cd "$(dirname "$0")" && pwd)"
IN="$1"; OUT="$2"
HTML="${OUT%.pdf}.html"
pandoc "$IN" -s --from markdown+tex_math_dollars+tex_math_single_backslash+raw_tex+pipe_tables+implicit_figures+fenced_divs+bracketed_spans \
  --katex="file://$TOOLS/node_modules/katex/dist/" \
  --toc --toc-depth=2 --number-sections \
  -c "file://$TOOLS/style.css" \
  --metadata lang=en \
  -o "$HTML"
node "$TOOLS/render.js" "$HTML" "$OUT"
