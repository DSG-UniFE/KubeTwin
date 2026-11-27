# ragbench, 3 clusters, 4 RPS: optimization with edges at 4 cores (27 November 2026)

**Why**: at the meeting of 27 November 2026 Bologna reported that each Liqo
edge cluster offers **4 CPUs** to ragbench, not the 7000m of the earlier
confs. Consistent with round 2 (`../opt3c_2rtt_rps4`): every allocation
with at most 8 pods (500m each) on an edge deployed; solution_28, 10 pods on
cluster2edge, failed with "exceeded its progress deadline". 11 distinct
allocations of the previous front put more than 8 pods on an edge.

**Model**: `examples/ragbench_3c_2rtt_client_edge4.conf` = the reference
model `ragbench_3c_2rtt_client.conf` (2 RTT per call, client-side TTR,
cluster1 6000m + guardrail 500m) with cluster2edge and cluster3edge at
4000m (at most 8 pods each). The edge capacity only changes which
allocations fit: for an allocation that fits in both, the prediction is the
same as with the reference conf, so round 2's results stay valid.

## Plan

1. [x] `run_opt.sh`: NSGA-II, 30 generations, population 60, seed 12345 (same
   search as `../opt3c_2rtt_rps4`, ~8.5 min).
2. [x] Re-evaluation with 10 seeds, percentiles of the candidates.
3. [x] Candidates for Bologna: `allocations_bologna_edge4_rps4.json`, copied to
   ragbench `allocations/kubetwin_3c_edge4_4rps.json` with the "Round 3"
   instructions in its README.
4. [x] Figure of the front with the candidates: `fig_pareto_front.{pdf,png}`
   (`../plot_pareto_front.py`), in the paper as
   `img/ragbench_edge4_pareto_front.pdf`.
5. [ ] After Bologna's runs: comparison as in ragbench
   `results/multicluster_round2_20261126/`.

## Optimizer change

With 28 pods of capacity in total (12 + 8 + 8) instead of 40, random
allocations of the first generation often do not fit the federation at all
(up to 50 replicas). The simulation then stops before running and the first
run crashed on a nil mean TTR. `KOptimizerMultiobjective` now gives such
allocations objectives worse than any feasible one (mean TTR 10^6 s,
spreading 1, replicas 51), so they are always dominated. Nothing changes for
allocations that fit. As before, a pod that does not fit in its assigned
cluster but fits elsewhere is placed there by the scheduler, and the
exported allocation (`bmap`) records where it went: no allocation of the
front has more than 12 / 8 / 8 pods.

## Files

- `run_opt.sh` -> `pareto_front_20261127121907.csv`,
  `final_allocation_multi_objective_20261127121907.json` (60 solutions, 41
  distinct allocations).
- `reeval/run_reeval.sh` -> `reeval/reeval_10seeds.csv` (seeds 1000-1009, plus
  the reference `all_c1_x3`: 848 ± 35 ms). 39 of 41 stay non-dominated on
  (mean TTR, Gini, replicas).
- `make_candidates.py` -> `allocations_bologna_edge4_rps4.json` (checks
  non-dominance and pod counts); `reeval/run_percentiles.sh` ->
  `reeval/kt_percentiles_candidates.csv`, then `make_candidates.py --fill`.

## Candidates

A-D have the same 17 replicas, so they isolate the effect of spreading (the
most complete ladder of this front); E is the cheapest. Allocation per
service as cluster1/cluster2edge/cluster3edge; pods include the guardrail on
cluster1. No gateway on cluster3edge. KubeTwin, client-side TTR, k6 next to
cluster1, 10 seeds:

| | sol. | mean | p50 | p95 | p99 | Gini | repl. | pods c1/c2/c3 | gateway | embedder | vector-search | reranker | llm-generate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A, fastest | 28 | 670 ± 12 | 609 | 1106 | 1469 | 0.77 | 17 | 13/5/0 | 3/2/0 | 3/0/0 | 3/0/0 | 1/2/0 | 2/1/0 |
| B | 35 | 853 ± 17 | 719 | 1547 | 2129 | 0.42 | 17 | 10/6/2 | 4/1/0 | 2/1/0 | 1/2/0 | 1/1/1 | 1/1/1 |
| C | 51 | 968 ± 36 | 814 | 1878 | 2679 | 0.23 | 17 | 9/6/3 | 3/2/0 | 2/1/0 | 1/1/1 | 1/1/1 | 1/1/1 |
| D, most spread | 22 | 1094 ± 24 | 915 | 2179 | 3071 | 0.10 | 17 | 8/6/4 | 3/2/0 | 1/1/1 | 1/1/1 | 1/1/1 | 1/1/1 |
| E, fewest replicas | 3 | 792 ± 20 | 668 | 1539 | 2047 | 0.87 | 15 | 13/3/0 | 3/0/0 | 3/0/0 | 3/0/0 | 1/2/0 | 2/1/0 |

Fastest overall: solution 2 (18 replicas, 664 ms), within 1% of A. Five
allocations with 15-16 replicas spread over the edges are near saturation
(1.8-5.0 s, large sd across seeds); the figure leaves them out above 1.6 s.
At 17 replicas, going from A (Gini 0.77) to D (0.10) costs 424 ms (round 2's
front: 310 ms at 19 replicas). A-D here have 5 gateway replicas, round 2's
A-D 6-7 (not checked whether that is the cause).
