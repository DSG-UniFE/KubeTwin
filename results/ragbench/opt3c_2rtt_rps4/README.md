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

## Validation at Bologna (round 2, 26 November 2026)

Blind test of four candidates (A, C, D, E; B produced no data), analysis in
the ragbench repo, `results/multicluster_round2_20261126/`. Mean response
time, KubeTwin vs measured (k6 client): A −3.0%, C −1.5%, D −2.6%, E +5.6%;
p50–p95 within ±10% for all; ranking A < E < C < D preserved. Independent
pod-to-pod RTT through Liqo: 30.85 / 51.21 ms; cluster1 has 7.1 cores free.

### Client-side response time (added after the round-2 runs)

By default KubeTwin's TTR starts when a request reaches the first container,
so it leaves out the client's connection set-up and the hop from cluster1
(where k6's requests enter, through the NodePort) to a gateway on an edge.
`"ttr_from_client": true` in the federation measures it from the request's
generation, as k6 does; `"client_connect_time"` sets the set-up time (default
1.48 ms). All of Bologna's requests enter through cluster1, so k6 on a laptop
adds a fixed laptop<->cluster1 path: 28.6 ms from round 1 (vector_remote at
1 RPS, 30.6 ms gap minus ~2 ms with k6 next to the node); round 2's
low-quantile client − root-span gap (24–26 ms for A and E) shows it again.

`reeval/run_percentiles_client.sh` → `kt_percentiles_candidates_{client,laptop}.csv`.
Δ mean (p50, p95) vs Bologna's round 2, k6 client:

| | blind (TTR from arrival) | client-side, k6 next to cluster1 | client-side + laptop (30.1 ms) |
|---|---|---|---|
| A (3) | −3.0% (−2.2, −5.4) | −1.2% (+0.6, −3.3) | +3.6% (+6.0, +0.7) |
| C (44) | −1.5% (−2.7, +1.1) | +0.5% (−0.5, +2.6) | +3.8% (+3.5, +3.7) |
| D (27) | −2.6% (−3.0, +0.0) | −0.7% (−0.6, +1.3) | +3.2% (+3.0, +4.4) |
| E (2) | +5.6% (+4.4, +9.2) | +6.1% (+5.0, +9.5) | +13.0% (+12.0, +15.2) |

The complete model (client-side + laptop) overestimates by 3–4% on A, C, D
and 13% on E, the busiest gateways (0.65 per worker): the blind numbers were
partly an offset between the missing ingress/laptop time and a slight
overestimate of the queues. The blind column is the true out-of-sample test.
