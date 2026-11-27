"""Candidates for Bologna from the re-evaluated edge-4-core front.

    python make_candidates.py            -> non-dominated check + allocations_bologna_edge4_rps4.json
    python make_candidates.py --fill     -> also fills p50-p99 from reeval/kt_percentiles_candidates.csv
"""
import csv
import glob
import json
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).parent
CANDIDATES = [  # solution_id, letter, role
    (28, "A", "Fastest (17 replicas)"),
    (35, "B", "Spreading ladder, 17 replicas"),
    (51, "C", "Spreading ladder, 17 replicas"),
    (22, "D", "Most spread, 17 replicas"),
    (3, "E", "Fewest replicas (15)"),
]

rows = [r for r in csv.DictReader(open(HERE / "reeval/reeval_10seeds.csv")) if r["solution_id"].isdigit()]
obj = {int(r["solution_id"]): (float(r["reeval_ttr_ms"]), float(r["spreading"]), int(r["total_replicas"]))
       for r in rows}


def dominated(a, b):
    return all(x <= y for x, y in zip(b, a)) and any(x < y for x, y in zip(b, a))


nd = {i for i, a in obj.items() if not any(dominated(a, b) for j, b in obj.items() if j != i)}
print(f"{len(nd)} of {len(obj)} non-dominated after the 10-seed re-evaluation")
for sid, letter, _ in CANDIDATES:
    print(letter, sid, obj[sid], "non-dominated" if sid in nd else "DOMINATED")

front = json.load(open(sorted(glob.glob(str(HERE / "final_allocation_multi_objective_*.json")))[-1]))
alloc = {s["solution_id"]: s["microservice_allocation"] for s in front}
sd = {int(r["solution_id"]): float(r["reeval_sd_ms"]) for r in rows}

pct = {}
if "--fill" in sys.argv:
    per = {}
    for r in csv.DictReader(open(HERE / "reeval/kt_percentiles_candidates.csv")):
        per.setdefault(int(r["solution_id"]), []).append(r)
    for sid, rs in per.items():
        pct[sid] = {f"{k}_ms": round(statistics.mean(float(r[f"{k}_ms"]) for r in rs), 1)
                    for k in ("p50", "p90", "p95", "p99")}

out = []
for sid, letter, role in CANDIDATES:
    a = alloc[sid]
    pods = {c: sum(v[c] for v in a.values()) for c in ("cluster1", "cluster2edge", "cluster3edge")}
    assert pods["cluster1"] <= 12 and pods["cluster2edge"] <= 8 and pods["cluster3edge"] <= 8, (sid, pods)
    out.append({
        "solution_id": sid,
        "candidate": letter,
        "role": role,
        "predicted": {"rps": 4, "mean_ttr_ms": obj[sid][0], "mean_ttr_sd_ms_10_seeds": sd[sid],
                      "gini": obj[sid][1], "total_replicas": obj[sid][2], **pct.get(sid, {})},
        "microservice_allocation": a,
    })
json.dump(out, open(HERE / "allocations_bologna_edge4_rps4.json", "w"), indent=1)
print("written allocations_bologna_edge4_rps4.json")
