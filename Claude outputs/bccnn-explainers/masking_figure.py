"""Masking of periods without payments in the rolling-origin early stopping.

Draws thesis/figures/bccnn-explainers/rolling_origin_masking.png:
  (a) final partition (tau = 20), late development periods: a development
      period whose training cells hold no payments, and its validation cell;
  (b) schematic validation deviance with and without that cell;
  (c) test partition (tau = 15): which test cells are dropped and which kept.
Roles follow rolling_origin() (test_periods 5, 2; vali_periods 2; exclude 2).
The payments in (a) and (c) and the curves in (b) are illustrative.

Run from this folder: python3 masking_figure.py
"""
import os

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch, Rectangle

N, VP, EX = 20, 2, 2
OUT = os.path.join("..", "..", "thesis", "figures", "bccnn-explainers", "rolling_origin_masking.png")

# validated categorical slots 1-3 (dataviz reference palette, light mode);
# masked cells: neutral grey with hatch and a cross (not colour alone)
COL = {"train": "#2a78d6", "validation": "#eb6834", "test": "#1baf7a",
       "masked": "#d9d9d6", "unused": "#f3f3f1"}
INK, MUTED = "#0b0b0b", "#52514e"

plt.rcParams.update({"font.size": 8.5, "font.family": "Caladea", "mathtext.fontset": "custom",
                     "mathtext.rm": "Caladea", "mathtext.it": "Caladea:italic", "mathtext.bf": "Caladea:bold",
                     "axes.titlesize": 9, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "savefig.dpi": 300})


def role(tau, i, j):
    """Role of cell (i, j) in the partition at tau, as rolling_origin()."""
    k = i + j - 1
    if i > tau or j > tau or k > N:
        return "unused"
    if k > tau:
        return "test"
    m = VP * (EX - 1)
    lo, hi = EX + 1, tau - VP - EX + 1
    devs = list(range(EX, 1, -1))
    repl = {(int(np.round(lo + (hi - lo) * (q - 0.5) / m)), devs[(q - 1) % len(devs)]) for q in range(1, m + 1)}
    if (k > tau - VP and i > EX and j > EX) or (i, j) in repl:
        return "validation"
    return "train"


def grid(ax, tau, rows, cols, pay, masked, title, note_col=None, note_rows=None):
    for i in rows:
        for j in cols:
            r = role(tau, i, j)
            k = i + j - 1
            if k > N:
                continue
            face = COL["masked"] if (i, j) in masked else COL[r]
            ax.add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=face, edgecolor="white", lw=1.5,
                                   hatch="////" if (i, j) in masked else None))
            if (i, j) in masked:
                ax.plot(j, i, marker="x", ms=9, mew=1.6, color=INK)
            elif (i, j) in pay:
                ax.text(j, i, pay[(i, j)], ha="center", va="center", fontsize=8,
                        color="white" if r in ("train",) else INK)
    if note_col is not None:
        ax.add_patch(Rectangle((note_col - .5, note_rows[0] - .5), 1, len(note_rows), fill=False, edgecolor=INK,
                               lw=1.6, ls="--", zorder=6))
    ax.set_xlim(cols[0] - .5, cols[-1] + .5); ax.set_ylim(rows[-1] + .5, rows[0] - .5)
    ax.set_xticks(cols); ax.set_yticks(rows); ax.set_aspect("equal")
    ax.set_xlabel("development period $j$"); ax.set_ylabel("accident period $i$")
    ax.tick_params(length=0)
    for s in ax.spines.values():
        s.set_visible(False)
    ax.set_title(title, loc="left", color=INK)


fig = plt.figure(figsize=(6.6, 8.2))
gs = fig.add_gridspec(3, 2, height_ratios=[1.05, 0.28, 1], hspace=0.3, wspace=0.3)

# (a) final partition: development period 18 has payments only in its validation cell (3, 18)
ax = fig.add_subplot(gs[0, 0])
rows, cols = list(range(1, 7)), list(range(15, 21))
pay = {(1, 18): "0", (2, 18): "0", (1, 17): "4", (2, 17): "3", (1, 15): "6", (2, 15): "5", (1, 16): "5",
       (2, 16): "4", (3, 15): "5", (3, 16): "3", (4, 15): "4", (1, 19): "2", (2, 19): "1", (1, 20): "1"}
grid(ax, 20, rows, cols, pay, masked={(3, 18)},
     title="(a) Final partition, $\\tau$ = 20", note_col=18, note_rows=[1, 2, 3])
note = fig.add_subplot(gs[1, 0]); note.axis("off")
note.text(0, 1, "$j$ = 18: its training cells (1, 18) and (2, 18) pay 0,\nso the ccODP start has "
          "$\\hat\\beta_{18}\\approx-30$ and $\\hat\\mu\\approx e^{-30}$.\n"
          "Its validation cell (3, 18) pays 0.5: masked.", fontsize=7.5, color=INK, va="top", linespacing=1.35)

# (c) test partition: column 13 pays only in a validation cell (kept), column 14 pays nothing by year 15 (dropped)
ax = fig.add_subplot(gs[0, 1])
rows, cols = list(range(1, 9)), list(range(11, 16))
dropped = {(i, 14) for i in range(3, 8)} | {(i, 15) for i in range(2, 7)} | {(3, 13)}
pay = {(1, 13): "0", (2, 13): "0", (3, 13): "50", (1, 14): "0", (2, 14): "0", (1, 15): "0"}
grid(ax, 15, rows, cols, pay, masked=dropped, title="(b) Test partition, $\\tau$ = 15")
note = fig.add_subplot(gs[1, 1]); note.axis("off")
note.text(0, 1, "$j$ = 13: by year 15 it pays only in validation cell\n(3, 13), masked as in (a); the chain ladder at 15\n"
          "knows the column, so its test cells are kept.\n"
          "$j$ = 14, 15: nothing paid by year 15: test cells dropped.", fontsize=7.5, color=INK,
          va="top", linespacing=1.35)

# (b) schematic validation deviance with and without the cell (3, 18)
ax = fig.add_subplot(gs[2, :])
t = np.arange(0, 1001)
base = 40 - 10 * (1 - np.exp(-t / 120)) + 1e-5 * t ** 2           # the other 32 validation cells
y, log_mu = 0.5, -30 + 0.012 * t                                  # the network slowly lifts the cell
cell = 2 * (y * (np.log(y) - log_mu) - y + np.exp(log_mu))
both = base + cell
t_m, t_u = t[np.argmin(base)], t[np.argmin(both)]
d_m, d_u = base - base[0], both - both[0]
ax.plot(t, d_u, color=MUTED, lw=2, ls=(0, (5, 2)), label="not masked: all 33 validation cells")
ax.plot(t, d_m, color=INK, lw=2, label="masked: 32 cells, (3, 18) left out")
for tt, curve, c in [(t_m, d_m, INK), (t_u, d_u, MUTED)]:
    ax.plot(tt, curve[tt], "o", ms=8, color=c, mec="white", mew=2, zorder=5)
ax.annotate(f"$t^*$ = {t_m}: chosen by the fit\nof the latest diagonals", xy=(t_m, d_m[t_m]),
            xytext=(t_m + 120, d_m[t_m] + 4.0), fontsize=7.5, color=INK, ha="left",
            arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
ax.annotate(f"$t^*$ = {t_u}: chosen by how fast the\nnetwork lifts one cell from $e^{{-30}}$", xy=(t_u, d_u[t_u]),
            xytext=(t_u + 60, d_u[t_u] - 4.2), fontsize=7.5, color=INK, ha="left",
            arrowprops=dict(arrowstyle="-", color=MUTED, lw=0.8))
ax.text(1000, 3.2, f"the one cell adds about {cell[0]:.0f} to $D_{{V,20}}$ at the start\n"
        "and keeps falling as the network lifts it", ha="right", va="top", fontsize=7.5, color=MUTED)
ax.axhline(0, color="#e6e6e3", lw=0.8)
ax.set_xlim(0, 1000); ax.set_ylim(min(d_m.min(), d_u.min()) - 7, 3.5)
ax.set_xlabel("gradient-descent step $t$"); ax.set_ylabel("change in validation deviance\nfrom the start, $D_{V,20}(t) - D_{V,20}(0)$")
ax.set_yticks([])
ax.grid(axis="x", color="#e6e6e3", lw=0.6)
for s in ("top", "right", "left"):
    ax.spines[s].set_visible(False)
ax.legend(loc="lower left", frameon=False, fontsize=8)
ax.set_title("(c) Schematic: early stopping at $\\tau$ = 20 with and without the cell (3, 18)", loc="left", color=INK)

handles = [Patch(facecolor=COL["train"], label="training"), Patch(facecolor=COL["validation"], label="validation"),
           Patch(facecolor=COL["test"], label="test"),
           Patch(facecolor=COL["masked"], hatch="////", edgecolor="white", label="masked (×): not scored")]
fig.legend(handles=handles, loc="upper center", ncol=4, frameon=False, bbox_to_anchor=(0.5, 0.995), fontsize=8)
fig.savefig(OUT, bbox_inches="tight", facecolor="white")
print("wrote", os.path.abspath(OUT), "t* masked", t_m, "unmasked", t_u, "cell at start", round(cell[0], 1))
