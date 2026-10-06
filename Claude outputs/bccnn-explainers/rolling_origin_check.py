"""Replicates rolling_origin_sets() of R/triangles.R for the config of
config.yml (n = 20, test_periods = c(5, 2), vali_periods = 2, exclude = 2),
prints the cell counts, checks the guarantees, and draws the figures used by
the explainers (partition tiles, calendar diagonals, claims split, network).
"""
import json, math
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, FancyBboxPatch, FancyArrowPatch

def r_round(x):            # R's round(): half to even (IEC 60559)
    return int(np.round(x))

def rolling_origin_sets(n, test_periods=(5, 2), vali_periods=2, exclude=2):
    origins = [n - t for t in sorted(test_periods, reverse=True)] + [n]
    parts = []
    for c0 in origins:
        row = np.arange(1, c0 + 1)[:, None] * np.ones((1, c0), int)
        col = np.ones((c0, 1), int) * np.arange(1, c0 + 1)[None, :]
        cal = row + col - 1
        known = cal <= c0
        vali = known & (cal > c0 - vali_periods) & (row > exclude) & (col > exclude)
        extra = []
        if exclude >= 2:
            k = vali_periods * (exclude - 1)
            lo = exclude + 1
            hi = c0 - vali_periods - exclude + 1
            rows = [r_round(lo + (hi - lo) * (kk - 0.5) / k) for kk in range(1, k + 1)]
            devs = [list(range(exclude, 1, -1))[(kk - 1) % (exclude - 1)] for kk in range(1, k + 1)]
            for rr, dd in zip(rows, devs):
                vali[rr - 1, dd - 1] = True
                extra.append((rr, dd, int(cal[rr - 1, dd - 1])))
        train = known & ~vali
        test = ((cal > c0) & (cal <= n)) if c0 < n else None   # observed at n only
        parts.append(dict(origin=c0, known=known, train=train, vali=vali, test=test, cal=cal,
                          extra=extra, final=c0 == n, lo=lo, hi=hi))
    return parts

n = 20
parts = rolling_origin_sets(n)
summary = []
for p in parts:
    c0 = p["origin"]
    diag_counts = {}
    for d in sorted(set(p["cal"][p["vali"]].tolist())):
        diag_counts[int(d)] = int(np.sum(p["vali"] & (p["cal"] == d)))
    summary.append(dict(
        origin=c0, final=p["final"], square=f"{c0} x {c0}", n_known=int(p["known"].sum()),
        n_train=int(p["train"].sum()), n_vali=int(p["vali"].sum()),
        n_test=int(p["test"].sum()) if p["test"] is not None else 0,
        vali_diagonals=[c0 - 1, c0], vali_on_diagonals=int(np.sum(p["vali"] & (p["cal"] > c0 - 2))),
        vali_by_calendar=diag_counts, extra_cells=p["extra"], lo=p["lo"], hi=p["hi"],
        every_row_has_train=bool(np.all(p["train"].sum(1) > 0)), every_col_has_train=bool(np.all(p["train"].sum(0) > 0)),
        test_calendar=sorted(set(p["cal"][p["test"]].tolist())) if p["test"] is not None else [],
        train_rows_last_two=[int(p["train"][c0 - 1].sum()), int(p["train"][c0 - 2].sum())],
        vali_share_of_known=float(p["vali"].sum() / p["known"].sum()),
    ))
    # Upper triangle (full) counts
tot_test = sum(s["n_test"] for s in summary if not s["final"])
print(json.dumps(summary, indent=1))
json.dump(dict(summary=summary, total_test_cells=tot_test), open("rolling_origin.json", "w"), indent=1)

# ---------------------------------------------------------------- figures ---
plt.rcParams.update({"font.size": 9, "font.family": "DejaVu Sans"})
COL = dict(train="#4daf4a", validation="#1b5e20", test="#e41a1c", future="#f0f0f0", outside="#dde7f0")

def draw_partition(ax, p, n, title):
    c0 = p["origin"]
    # full n x n frame: future cells (never used) light grey
    for i in range(1, n + 1):
        for j in range(1, n + 1):
            if i + j > n + 1:
                ax.add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=COL["future"], edgecolor="#dddddd", lw=0.3))
            elif i > c0 or j > c0:
                ax.add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=COL["outside"], edgecolor="#dddddd", lw=0.3, hatch="////"))
    for i in range(1, c0 + 1):
        for j in range(1, c0 + 1):
            if p["train"][i - 1, j - 1]: fc = COL["train"]
            elif p["vali"][i - 1, j - 1]: fc = COL["validation"]
            elif p["test"] is not None and p["test"][i - 1, j - 1]: fc = COL["test"]
            else: continue
            ax.add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=fc, edgecolor="white", lw=0.4))
    # outline of the c0 x c0 square
    ax.add_patch(Rectangle((.5, .5), c0, c0, fill=False, edgecolor="black", lw=1.0))
    # the latest observed diagonal of the full triangle
    ax.plot([n + .5, .5], [.5, n + .5], color="black", lw=0.6, ls="--")
    ax.set_xlim(.5, n + .5); ax.set_ylim(n + .5, .5); ax.set_aspect("equal")
    ax.set_xticks([1, 5, 10, 15, 20]); ax.set_yticks([1, 5, 10, 15, 20])
    ax.set_xlabel("development period $j$"); ax.set_ylabel("accident period $i$")
    ax.set_title(title, fontsize=9)

fig, axes = plt.subplots(1, 3, figsize=(10.5, 3.9))
labels = ["test partition 1: valuation year $c = 15$",
          "test partition 2: valuation year $c = 18$",
          "final partition: $c = 20$ (no test set)"]
for ax, p, lab in zip(axes, parts, labels):
    draw_partition(ax, p, n, lab)
from matplotlib.patches import Patch
handles = [Patch(facecolor=COL["train"], label="training cells"), Patch(facecolor=COL["validation"], label="validation cells"),
           Patch(facecolor=COL["test"], label="test cells (held-out calendar years)"), Patch(facecolor=COL["outside"], edgecolor="#bbbbbb", hatch="////", label="observed at year 20, outside the partition's square (unused here)"),
           Patch(facecolor=COL["future"], edgecolor="#bbbbbb", label="future cells (never used)")]
fig.legend(handles=handles, loc="lower center", ncol=3, fontsize=8, frameon=False, bbox_to_anchor=(0.5, -0.04))
fig.tight_layout(rect=(0, 0.1, 1, 1)); fig.savefig("figures/rolling_origin_partitions.png", dpi=170, bbox_inches="tight"); plt.close(fig)

# calendar diagonals of a small triangle (n = 7)
m = 7
fig, ax = plt.subplots(figsize=(4.2, 3.9))
for i in range(1, m + 1):
    for j in range(1, m + 1):
        cal = i + j - 1
        obs = cal <= m
        ax.add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=("#cfe8cf" if obs else "#f7d6d6"), edgecolor="white", lw=0.8))
        ax.text(j, i, str(cal), ha="center", va="center", fontsize=9, color=("black" if obs else "#8b0000"))
ax.plot([m + .5, .5], [.5, m + .5], color="black", lw=0.8)
ax.set_xlim(.5, m + .5); ax.set_ylim(m + .5, .5); ax.set_aspect("equal")
ax.set_xticks(range(1, m + 1)); ax.set_yticks(range(1, m + 1))
ax.set_xlabel("development period $j$"); ax.set_ylabel("accident period $i$")
ax.set_title("calendar period $i + j - 1$ of each cell ($n = 7$)\ngreen: observed at $n$, red: future", fontsize=9)
fig.tight_layout(); fig.savefig("figures/calendar_diagonals.png", dpi=170); plt.close(fig)

# claims split schematic
fig, ax = plt.subplots(figsize=(7.2, 2.6)); ax.axis("off")
def tri(ax, x0, y0, s, col, label):
    for i in range(1, 6):
        for j in range(1, 6):
            if i + j <= 6:
                ax.add_patch(Rectangle((x0 + (j - 1) * s, y0 - i * s), s, s, facecolor=col, edgecolor="white", lw=0.6))
    ax.text(x0 + 2.5 * s, y0 - 5.6 * s, label, ha="center", va="top", fontsize=8)
ax.set_xlim(0, 10); ax.set_ylim(-0.6, 2.4)
ax.text(0.9, 1.9, "individual claims,\nordered by accident\nperiod then claim no.", ha="center", va="center", fontsize=8)
for k in range(8):
    ax.add_patch(Rectangle((0.2 + k * 0.17, 0.6), 0.14, 0.5, facecolor=("#9ecae1" if k % 2 == 0 else "#fdae6b"), edgecolor="black", lw=0.4))
    ax.text(0.27 + k * 0.17, 0.4, "1" if k % 2 == 0 else "2", ha="center", fontsize=7)
ax.text(0.9, 0.05, "alternate allocation 1, 2, 1, 2, ...", ha="center", fontsize=7.5)
ax.add_patch(FancyArrowPatch((1.8, 0.85), (2.6, 1.5), arrowstyle="-|>", mutation_scale=10, color="black"))
ax.add_patch(FancyArrowPatch((1.8, 0.85), (2.6, 0.1), arrowstyle="-|>", mutation_scale=10, color="black"))
tri(ax, 2.7, 2.3, 0.22, "#9ecae1", "training half: triangle $\\mathcal{D}^{T}$")
tri(ax, 2.7, 0.9, 0.22, "#fdae6b", "validation half: triangle $\\mathcal{D}^{V}$")
ax.text(5.0, 1.9, "ccODP on $\\mathcal{D}^{T}$ $\\rightarrow$ start\nbCCNN trained on $\\mathcal{D}^{T}$\nfor $t = 0, 1, \\dots, T_{max}$", ha="left", va="center", fontsize=8)
ax.text(5.0, 0.35, "validation deviance of $\\mu_t$ on $\\mathcal{D}^{V}$\n$t^* = \\arg\\min_t\\, D(\\mathcal{D}^{V}, \\mu_t)$", ha="left", va="center", fontsize=8)
ax.add_patch(FancyArrowPatch((4.2, 1.5), (4.9, 1.8), arrowstyle="-|>", mutation_scale=10, color="black"))
ax.add_patch(FancyArrowPatch((4.2, 0.1), (4.9, 0.3), arrowstyle="-|>", mutation_scale=10, color="black"))
ax.text(8.6, 1.1, "refit: ccODP on the full\ntriangle $\\mathcal{D}$ $\\rightarrow$ start,\nbCCNN trained on $\\mathcal{D}$\nfor exactly $t^*$ steps", ha="center", va="center", fontsize=8,
        bbox=dict(boxstyle="round", facecolor="#f5f5f5", edgecolor="#888888"))
ax.add_patch(FancyArrowPatch((7.1, 0.6), (7.5, 1.0), arrowstyle="-|>", mutation_scale=10, color="black"))
fig.savefig("figures/claims_split.png", dpi=170, bbox_inches="tight"); plt.close(fig)

# network architecture diagram
fig, ax = plt.subplots(figsize=(9.6, 4.6)); ax.axis("off"); ax.set_xlim(-0.1, 10.1); ax.set_ylim(0, 5.2)
def box(x, y, w, h, text, fc="#ffffff", ec="black", fs=8, lw=0.9):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08", facecolor=fc, edgecolor=ec, lw=lw))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs)
def arrow(p, q, **kw):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=9, color=kw.get("color", "black"), lw=kw.get("lw", 0.9), connectionstyle=kw.get("cs", "arc3,rad=0")))
# inputs and embeddings
box(0.05, 3.9, 1.55, 0.55, "AccYear\n$i-1 \\in \\{0,\\dots,19\\}$", fc="#e8f0fe")
box(0.05, 1.1, 1.55, 0.55, "DevYear\n$j-1 \\in \\{0,\\dots,19\\}$", fc="#e8f0fe")
box(1.9, 3.9, 1.5, 0.55, "AY_embed\n$\\alpha_i$ (fixed, 20 x 1)", fc="#dbe9ff")
box(1.9, 1.1, 1.5, 0.55, "DY_embed\n$\\beta_j$ (fixed, 20 x 1)", fc="#dbe9ff")
arrow((1.6, 4.17), (1.9, 4.17)); arrow((1.6, 1.37), (1.9, 1.37))
# skip connection
box(3.9, 4.35, 1.5, 0.5, "cc0 = add\n$\\alpha_i + \\beta_j$", fc="#e0f3e0", ec="#2e7d32")
arrow((3.4, 4.3), (3.9, 4.55), color="#2e7d32"); arrow((3.4, 1.5), (3.9, 4.4), color="#2e7d32", cs="arc3,rad=0.25")
# concatenation and hidden layers
box(3.9, 2.4, 1.5, 0.5, "concate0\n$z^{(0)} = (\\alpha_i, \\beta_j) \\in \\mathbb{R}^2$", fc="#fff3e0")
arrow((3.4, 4.1), (3.9, 2.75)); arrow((3.4, 1.4), (3.9, 2.55))
xs = [5.75, 7.05, 8.35]
labs = ["hidden1\ntanh, $q_1 = 20$\n+ dropout 10%", "hidden2\ntanh, $q_2 = 15$\n+ dropout 10%", "hidden3\ntanh, $q_3 = 10$\n+ dropout 10%"]
for k, (x, lab) in enumerate(zip(xs, labs)):
    box(x, 2.25, 1.1, 0.8, lab, fc="#fff3e0")
arrow((5.4, 2.65), (5.75, 2.65)); arrow((6.85, 2.65), (7.05, 2.65)); arrow((8.15, 2.65), (8.35, 2.65))
# output
box(7.0, 4.35, 2.9, 0.5, "concate1 = $(\\alpha_i+\\beta_j,\\ z^{(3)}) \\in \\mathbb{R}^{11}$", fc="#f3e5f5")
arrow((5.4, 4.6), (7.0, 4.6), color="#2e7d32"); arrow((8.9, 3.05), (8.6, 4.35))
box(6.9, 0.4, 3.1, 0.85, "Response: dense(1), exponential\n$\\mu_{i,j} = \\exp\\{w(\\alpha_i+\\beta_j) + c + \\langle B, z^{(3)}\\rangle\\}$\nstart: $w = 1,\\ c = \\hat c,\\ B = 0$", fc="#ffe0e0", ec="#b71c1c")
arrow((8.45, 4.35), (8.45, 1.25))
ax.text(5.0, 0.3, "green: skip connection (the ccODP part); orange: feed-forward part; red: output neuron", fontsize=7.5, ha="center", color="#444444")
fig.savefig("figures/bccnn_architecture.png", dpi=170, bbox_inches="tight"); plt.close(fig)
print("figures written")
