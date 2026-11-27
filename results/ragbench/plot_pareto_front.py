"""Pareto front of a ragbench 3-cluster optimization, with the candidates
deployed at Bologna highlighted.

The front has three objectives (mean TTR, replica spreading as normalized
Gini, total replicas): x = spreading, y = mean TTR re-evaluated with 10 seeds,
colour = total replicas (one sequential hue, light = few, dark = many).
Candidates: ringed and labelled with their letter.

    python plot_pareto_front.py <reeval_10seeds.csv> <allocations_*.json> <out prefix>

writes <out prefix>.pdf and .png (white background).
"""
from __future__ import annotations

import csv
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.colors import LinearSegmentedColormap  # noqa: E402

C_GRID, C_INK, C_INK2 = "#e4e3df", "#0b0b0b", "#52514e"
BG = "#ffffff"
# one hue (blue), light -> dark
SEQ = LinearSegmentedColormap.from_list("seq", ["#b9d3f2", "#2a78d6", "#0d3266"])


def main(reeval_csv: str, candidates_json: str, out: str, ymax: float | None = None):
    with open(reeval_csv) as f:
        rows = [r for r in csv.DictReader(f) if r["solution_id"].isdigit()]
    cands = json.load(open(candidates_json))
    by_id = {int(r["solution_id"]): r for r in rows}

    x = [float(r["spreading"]) for r in rows]
    y = [float(r["reeval_ttr_ms"]) for r in rows]
    c = [int(r["total_replicas"]) for r in rows]

    fig, ax = plt.subplots(figsize=(4.8, 3.6), facecolor=BG)
    ax.set_facecolor(BG)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(C_INK2)
    ax.tick_params(colors=C_INK2, labelsize=8)
    ax.grid(color=C_GRID, lw=.8)
    ax.set_axisbelow(True)

    sc = ax.scatter(x, y, c=c, cmap=SEQ, s=34, edgecolors=BG, linewidths=1, zorder=2)
    for cand in cands:
        r = by_id[int(cand["solution_id"])]
        px, py = float(r["spreading"]), float(r["reeval_ttr_ms"])
        ax.scatter([px], [py], s=150, facecolors="none", edgecolors=C_INK, linewidths=1.4, zorder=3)
        ax.annotate(cand["candidate"], (px, py), xytext=(7, 5), textcoords="offset points",
                    fontsize=9, fontweight="bold", color=C_INK, zorder=4)
    cb = fig.colorbar(sc, ax=ax, pad=.02)
    cb.set_label("total replicas", color=C_INK2, fontsize=8)
    cb.ax.tick_params(colors=C_INK2, labelsize=8)
    cb.outline.set_visible(False)
    ax.set_xlabel("replica spreading (normalized Gini)", color=C_INK2, fontsize=9)
    ax.set_ylabel("mean response time, KubeTwin (ms)", color=C_INK2, fontsize=9)
    if ymax:
        ax.set_ylim(top=ymax)
        n_off = sum(v > ymax for v in y)
        if n_off:
            ax.text(.98, .98, f"{n_off} allocations above {ymax / 1000:g} s not shown",
                    transform=ax.transAxes, ha="right", va="top", fontsize=7, color=C_INK2)
    fig.tight_layout()
    fig.savefig(out + ".pdf")
    fig.savefig(out + ".png", dpi=160)


if __name__ == "__main__":
    main(*sys.argv[1:4], *(float(v) for v in sys.argv[4:5]))
