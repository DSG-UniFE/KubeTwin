# Response Time Scenario Comparison

Generated at: `2026-07-29T08:01:18Z`

Simulator config: `examples/bookinfo-3c-xr.conf`

Allocation file: `final_allocation_kubetwin_2_objectives_16072026.json`

The simulator values below were recomputed with the current multicluster workflow model and the calibrated `rps_correction_factor` present in the configuration file.

![Scenario Comparison](response_time_scenarios_comparison.png)

| Scenario | Solution | Old Expected (ms) | Testbed Avg (ms) | Testbed P90 (ms) | Testbed P95 (ms) | Simulated Mean (ms) | Delta (ms) | Delta (%) | Spreading |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| OPTIMUUM 20 - Soluzione 0 del 16/07/2025 | 0 | 43.0 | 78.0 | 110.0 | 130.0 | 77.62 | -0.38 | -0.49 | 0.92 |
| OPTIMUUM 22 - Soluzione 2 del 16/07/2025 | 2 | 98.0 | 207.0 | 320.0 | 360.0 | 183.84 | -23.16 | -11.19 | 0.17 |
| OPTIMUUM 24 - Soluzione 4 del 16/07/2025 | 4 | 62.0 | 131.0 | 240.0 | 260.0 | 142.61 | 11.61 | 8.86 | 0.54 |
| OPTIMUUM 2_10 - Soluzione 10 del 16/07/2025 | 10 | 72.0 | 158.0 | 260.0 | 260.0 | 148.52 | -9.48 | -6.0 | 0.36 |

## Notes

- `Old Expected` is the value written in the original markdown file.
- `Simulated Mean` is the current simulator end-to-end mean TTR for the same allocation.
- `Delta` is `simulated_mean - testbed_avg`.
