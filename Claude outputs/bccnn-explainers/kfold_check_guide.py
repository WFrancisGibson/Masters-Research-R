"""Companion V: how the three rolling-origin partitions are used, compared with
K-fold cross-validation.

Rebuilds the partitions of rolling_origin_sets() for the configuration of the
code (n = 20, test_periods = c(5, 2), vali_periods = 2, exclude = 2), counts
how the cells move between roles across the partitions, and draws the two
figures of companion V in the Guide style (Caladea):

  figures_guide/kfold_vs_rolling_origin_timeline.png
  figures_guide/kfold_vs_rolling_origin_coverage.png

The counts go to kfold_counts.json.  Run from this folder: python3 kfold_check_guide.py
"""
import json, os
from collections import Counter

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch, Rectangle

N, TEST, VP, EX, K = 20, (5, 2), 2, 2, 5
ORIGINS = [N - t for t in sorted(TEST, reverse=True)] + [N]


def r_round(x):                       # R's round(): halves to even
    return int(np.round(x))


def partition(tau):
    """Role of every cell (i, j) of the observed triangle in the partition at tau."""
    role = {}
    for i in range(1, N + 1):
        for j in range(1, N + 2 - i):
            k = i + j - 1
            if i > tau or j > tau:
                role[i, j] = "outside"
            elif k > tau:
                role[i, j] = "test"
            elif k > tau - VP and i > EX and j > EX:
                role[i, j] = "validation"
            else:
                role[i, j] = "train"
    m = VP * (EX - 1)
    lo, hi = EX + 1, tau - VP - EX + 1
    devs = list(range(EX, 1, -1))
    for q in range(1, m + 1):
        role[r_round(lo + (hi - lo) * (q - 0.5) / m), devs[(q - 1) % len(devs)]] = "validation"
    return role


P = {t: partition(t) for t in ORIGINS}
CELLS = sorted(P[N])
S = {t: {r: {c for c in CELLS if P[t][c] == r} for r in ("train", "validation", "test", "outside")} for t in ORIGINS}
U = {t: S[t]["train"] for t in ORIGINS}
V = {t: S[t]["validation"] for t in ORIGINS}
T = {t: S[t]["test"] for t in ORIGINS}
cal = lambda c: c[0] + c[1] - 1

held = Counter()
for t in ORIGINS:
    for c in V[t] | T[t]:
        held[c] += 1
trained = Counter()
for t in ORIGINS:
    for c in U[t]:
        trained[c] += 1
never = [c for c in CELLS if held[c] == 0]

counts = {
    "cells": len(CELLS),
    "per_partition": {t: {r: len(S[t][r]) for r in S[t]} for t in ORIGINS},
    "test_by_calendar": {t: dict(sorted(Counter(cal(c) for c in T[t]).items())) for t in ORIGINS[:-1]},
    "T15_and_T18": len(T[15] & T[18]),
    "T15_and_T18_by_calendar": dict(sorted(Counter(cal(c) for c in T[15] & T[18]).items())),
    "V15_in_U18": len(V[15] & U[18]), "V15_in_U20": len(V[15] & U[20]),
    "V18_in_U20": len(V[18] & U[20]), "V18_and_V20": sorted(V[18] & V[20]),
    "T15_in_U18": len(T[15] & U[18]), "T15_in_V18": len(T[15] & V[18]),
    "T15_in_U20": len(T[15] & U[20]), "T15_in_V20": len(T[15] & V[20]),
    "T18_in_U20": sorted(T[18] & U[20]), "T18_in_V20": len(T[18] & V[20]),
    "ever_validation": len(set().union(*V.values())), "ever_test": len(set().union(*T.values())),
    "ever_held_out": len(CELLS) - len(never), "never_held_out": len(never),
    "never_held_out_in_border": sum(1 for i, j in never if i <= EX or j <= EX),
    "held_out_multiplicity": dict(sorted(Counter(held[c] for c in CELLS).items())),
    "training_multiplicity": dict(sorted(Counter(trained[c] for c in CELLS).items())),
    "singleton_periods": {"accident period 20": [c for c in CELLS if c[0] == N], "development period 20": [c for c in CELLS if c[1] == N]},
}

# K-fold over cells: a random assignment of the 210 cells to K folds of (almost) equal size
rng = np.random.default_rng(2026)
fold = dict(zip(CELLS, rng.permutation(np.arange(len(CELLS)) % K) + 1))
lost = {}
for f in range(1, K + 1):
    train = [c for c in CELLS if fold[c] != f]
    rows = {i for i, _ in train}; cols = {j for _, j in train}
    lost[f] = {"held_out": sum(1 for c in CELLS if fold[c] == f),
               "accident_periods_without_training_cell": sorted(set(range(1, N + 1)) - rows),
               "development_periods_without_training_cell": sorted(set(range(1, N + 1)) - cols)}
counts["kfold_seed2026"] = lost
counts["kfold_folds_with_lost_period"] = sum(1 for f in lost.values() if f["accident_periods_without_training_cell"] or f["development_periods_without_training_cell"])

# random K-fold: probability that at least one fold leaves some period without a training cell
sims, bad = 2000, 0
for s in range(sims):
    a = dict(zip(CELLS, rng.permutation(np.arange(len(CELLS)) % K)))
    for f in range(K):
        rows = {c[0] for c in CELLS if a[c] != f}; cols = {c[1] for c in CELLS if a[c] != f}
        if len(rows) < N or len(cols) < N:
            bad += 1; break
counts["kfold_share_of_assignments_with_lost_period"] = bad / sims

os.makedirs("figures_guide", exist_ok=True)
json.dump(counts, open("kfold_counts.json", "w"), indent=1, default=str)
print(json.dumps(counts, indent=1, default=str))

# ------------------------------------------------------------------ figures --
plt.rcParams.update({"font.size": 9, "font.family": "Caladea", "mathtext.fontset": "custom", "mathtext.rm": "Caladea",
                     "mathtext.it": "Caladea:italic", "mathtext.bf": "Caladea:bold", "axes.titlesize": 9,
                     "legend.fontsize": 8, "savefig.dpi": 300})
COL = dict(train="#4daf4a", validation="#1b5e20", test="#e41a1c", unused="#f0f0f0")

# Figure 1: the cells of each calendar period by role, rolling origin against 5-fold CV
ORDER = ["validation", "test", "outside", "train"]
SHADE = {"train": COL["train"], "validation": COL["validation"], "test": COL["test"], "outside": COL["unused"]}
tot_k = Counter(cal(c) for c in CELLS)


def bar(ax, y, shares):
    for k in range(1, N + 1):
        y0 = y - .38
        for r in ORDER:
            h = .76 * shares[k].get(r, 0)
            if h > 0:
                ax.add_patch(Rectangle((k - .5, y0), 1, h, facecolor=SHADE[r], edgecolor="none"))
            y0 += h
        ax.add_patch(Rectangle((k - .5, y - .38), 1, .76, fill=False, edgecolor="white", lw=1.0))


fig, axes = plt.subplots(2, 1, figsize=(6.5, 5.0), gridspec_kw=dict(height_ratios=[3, 5]))
ax = axes[0]
for r, tau in enumerate(ORIGINS):
    sh = {k: {} for k in range(1, N + 1)}
    for c in CELLS:
        sh[cal(c)][P[tau][c]] = sh[cal(c)].get(P[tau][c], 0) + 1 / tot_k[cal(c)]
    bar(ax, len(ORIGINS) - 1 - r, sh)
ax.set_yticks(range(len(ORIGINS)))
ax.set_yticklabels([r"$\tau = %d$" % t + (" (final)" if t == N else " (test)") for t in reversed(ORIGINS)])
ax.set_xlim(.5, N + .5); ax.set_ylim(-.6, len(ORIGINS) - .4)
ax.set_xticks([1, 5, 10, 15, 20]); ax.set_xlabel("calendar period $k$")
ax.set_title("(a) Rolling origin: one partition per valuation period $\\tau$", loc="left")
for s_ in ("top", "right"): ax.spines[s_].set_visible(False)

ax = axes[1]
for f in range(1, K + 1):
    sh = {k: {} for k in range(1, N + 1)}
    for c in CELLS:
        r = "validation" if fold[c] == f else "train"
        sh[cal(c)][r] = sh[cal(c)].get(r, 0) + 1 / tot_k[cal(c)]
    bar(ax, K - f, sh)
ax.set_yticks(range(K)); ax.set_yticklabels(["fold %d" % f for f in range(K, 0, -1)])
ax.set_xlim(.5, N + .5); ax.set_ylim(-.6, K - .4)
ax.set_xticks([1, 5, 10, 15, 20]); ax.set_xlabel("calendar period $k$")
ax.set_title("(b) 5-fold cross-validation over the cells of the observed triangle", loc="left")
for s_ in ("top", "right"): ax.spines[s_].set_visible(False)
handles = [Patch(facecolor=COL["train"], label="training cells"),
           Patch(facecolor=COL["validation"], label="validation cells (held out)"),
           Patch(facecolor=COL["test"], label="test cells (scored, never used to choose)"),
           Patch(facecolor=COL["unused"], edgecolor="#bbbbbb", label="outside the partition's square (unused)")]
fig.legend(handles=handles, loc="lower center", ncol=2, frameon=False, bbox_to_anchor=(0.5, -0.01))
fig.tight_layout(rect=(0, 0.08, 1, 1))
fig.savefig("figures_guide/kfold_vs_rolling_origin_timeline.png", bbox_inches="tight"); plt.close(fig)

# Figure 2: how often each cell is held out, 5-fold CV against the rolling origin
fig, axes = plt.subplots(1, 2, figsize=(6.5, 4.1))
fcols = ["#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e"]
hcols = {0: "#ffffff", 1: "#c6dbef", 2: "#6baed6", 3: "#08519c"}
for ax, title in zip(axes, ["(a) 5-fold CV: fold of each cell", "(b) Rolling origin: times held out"]):
    for i in range(1, N + 1):
        for j in range(1, N + 1):
            if i + j - 1 > N:
                ax.add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor="#f0f0f0", edgecolor="#dddddd", lw=0.3))
    ax.set_xlim(.5, N + .5); ax.set_ylim(N + .5, .5); ax.set_aspect("equal")
    ax.set_xticks([1, 5, 10, 15, 20]); ax.set_yticks([1, 5, 10, 15, 20])
    ax.set_xlabel("development period $j$"); ax.set_ylabel("accident period $i$"); ax.set_title(title, loc="left")
for c in CELLS:
    i, j = c
    axes[0].add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=fcols[fold[c] - 1], edgecolor="white", lw=0.4))
    axes[1].add_patch(Rectangle((j - .5, i - .5), 1, 1, facecolor=hcols[held[c]], edgecolor="#bbbbbb", lw=0.3))
for c in [(N, 1), (1, N)]:
    axes[0].add_patch(Rectangle((c[1] - .5, c[0] - .5), 1, 1, fill=False, edgecolor="black", lw=1.4))
h1 = [Patch(facecolor=fcols[f], label="fold %d" % (f + 1)) for f in range(K)]
h2 = [Patch(facecolor=hcols[m], edgecolor="#bbbbbb", label="%d time%s (%d cells)" % (m, "" if m == 1 else "s", counts["held_out_multiplicity"][m])) for m in range(4)]
axes[0].legend(handles=h1, loc="upper center", fontsize=7, frameon=False, ncol=3, bbox_to_anchor=(0.5, -0.2))
axes[1].legend(handles=h2, loc="upper center", fontsize=7, frameon=False, ncol=2, bbox_to_anchor=(0.5, -0.2))
fig.tight_layout()
fig.savefig("figures_guide/kfold_vs_rolling_origin_coverage.png", bbox_inches="tight"); plt.close(fig)
