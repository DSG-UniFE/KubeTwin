# ragbench, 3 clusters, 4 RPS: optimization with 2 RTT per call (25 November 2026)

Same search as `../opt3c_rps4` (kept as it was), with
`examples/ragbench_3c_2rtt.conf`: Bologna's injected RTTs (30/50 ms) with
`round_trips_per_call: 2` (new TCP connection per call, see
`../bologna_mc_20261123/README.md`) and cluster1 at 6.5 cores (6000m in the
model, 500m left to the guardrail). Against Bologna's runs this model gives
−1.3% / +0.5% on the mean for 46 / 8
(`../bologna_mc_20261123/kubetwin_2rtt_10seeds.csv`).

- `run_opt.sh`: NSGA-II, 30 generations, population 60, seed 12345 (~8.5 min).
  Output: `pareto_front_20261125105904.csv`,
  `final_allocation_multi_objective_20261125105904.json` (60 solutions, 43
  distinct allocations).
- `reeval/run_reeval.sh`: every distinct allocation with seeds 1000–1009 →
  `reeval/reeval_10seeds.csv` (plus the reference `all_c1_x3`). 41 stay
  non-dominated on (mean TTR, Gini, replicas).
- `reeval/run_percentiles.sh`: p50–p99 of the candidates →
  `reeval/kt_percentiles_candidates.csv`.
- `allocations_bologna_2rtt_rps4.json`: proposed candidates.

## Proposed candidates

A–D have the same 19 replicas, so they isolate the effect of spreading; E is
the cheapest. Allocation per service as cluster1/cluster2edge/cluster3edge;
pods per cluster include the guardrail on cluster1. No gateway on
cluster3edge (48, the only earlier candidate with one, had 27% connection
errors at Bologna).

| | sol. | mean (10 seeds) | p50 | p95 | p99 | Gini | repl. | pods c1/c2/c3 | gateway | embedder | vector-search | reranker | llm-generate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A, fastest | 3 | 644 ± 8 | 585 | 1021 | 1326 | 0.67 | 19 | 13/7/0 | 5/2/0 | 2/1/0 | 1/2/0 | 2/1/0 | 2/1/0 |
| B | 28 | 718 ± 16 | 648 | 1160 | 1525 | 0.50 | 19 | 9/10/1 | 3/4/0 | 2/1/0 | 1/1/1 | 1/2/0 | 1/2/0 |
| C | 44 | 821 ± 16 | 730 | 1417 | 1940 | 0.23 | 19 | 10/7/3 | 4/3/0 | 2/1/0 | 1/1/1 | 1/1/1 | 1/1/1 |
| D, most spread | 27 | 958 ± 12 | 826 | 1779 | 2436 | 0.10 | 19 | 8/8/4 | 3/3/0 | 1/1/1 | 1/1/1 | 1/2/1 | 1/1/1 |
| E, fewest replicas | 2 | 760 ± 24 | 646 | 1468 | 2019 | 0.87 | 15 | 13/3/0 | 3/0/0 | 2/1/0 | 1/2/0 | 3/0/0 | 3/0/0 |

Compared with the first front (`../opt3c_rps4`), spreading costs more: from
Gini ~0.7 to ~0.1 at fixed replicas adds ~310 ms here (A→D), ~195 ms before
(A→D there, 18 replicas). Allocations with 15–16 replicas spread over the
edges are near saturation (1.3–8.5 s, large sd across seeds).
