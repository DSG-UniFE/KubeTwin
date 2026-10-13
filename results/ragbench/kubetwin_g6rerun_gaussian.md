# ragbench: KubeTwin vs testbed

Generated at `2026-10-12T15:50:57Z`, config `examples/ragbench.conf`, data `/Users/filippopoltronieri/code/ragbench/data_g6rerun_20261012`.

| scenario | RPS | real mean | sim mean | Δ% | real p50 | sim p50 | Δ% | real p90 | sim p90 | Δ% | real p95 | sim p95 | Δ% | real p99 | sim p99 | Δ% |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1 | 413.2 | 415.6 | +0.6 | 412.6 | 415.9 | +0.8 | 422.6 | 425.1 | +0.6 | 424.8 | 427.3 | +0.6 | 430.2 | 430.3 | +0.0 |
| gateway_6 | 4 | 456.4 | 457.3 | +0.2 | 416.5 | 418.7 | +0.5 | 576.1 | 579.8 | +0.6 | 609.9 | 599.6 | -1.7 | 819.6 | 821.8 | +0.3 |
| gateway_6 | 6 | 582.9 | 559.4 | -4.0 | 491.5 | 475.9 | -3.2 | 903.7 | 847.5 | -6.2 | 1064.9 | 952.7 | -10.5 | 1424.4 | 1334.4 | -6.3 |

## Mean |Δ%| per scenario

| scenario | mean | p50 | p90 | p95 | p99 |
|---|---:|---:|---:|---:|---:|
| baseline | 0.6 | 0.8 | 0.6 | 0.6 | 0.0 |
| gateway_6 | 2.1 | 1.8 | 3.4 | 6.1 | 3.3 |
