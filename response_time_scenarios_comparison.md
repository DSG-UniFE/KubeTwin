# Response Time Scenario Comparison

Generated at: `2026-07-28T12:18:05Z`

Simulator config: `examples/bookinfo-3c-xr.conf`

Allocation file: `final_allocation_kubetwin_2_objectives_16072026.json`

The simulator values below were recomputed with the current multicluster workflow model and the calibrated `rps_correction_factor` present in the configuration file.

| Scenario | Solution | Old Expected (ms) | Testbed Avg (ms) | Testbed P90 (ms) | Testbed P95 (ms) | Simulated Mean (ms) | Delta (ms) | Delta (%) | Spreading |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| OPTIMUUM 20 - Soluzione 0 del 16/07/2025 | 0 | 43.0 | 78.0 | 110.0 | 130.0 | 77.24 | -0.76 | -0.97 | 0.92 |
| OPTIMUUM 22 - Soluzione 2 del 16/07/2025 | 2 | 98.0 | 207.0 | 320.0 | 360.0 | 179.57 | -27.43 | -13.25 | 0.17 |
| OPTIMUUM 24 - Soluzione 4 del 16/07/2025 | 4 | 62.0 | 131.0 | 240.0 | 260.0 | 138.38 | 7.38 | 5.63 | 0.54 |
| OPTIMUUM 2_10 - Soluzione 10 del 16/07/2025 | 10 | 72.0 | 158.0 | 260.0 | 260.0 | 142.99 | -15.01 | -9.5 | 0.36 |

## Notes

- `Old Expected` is the value written in the original markdown file.
- `Simulated Mean` is the current simulator end-to-end mean TTR for the same allocation.
- `Delta` is `simulated_mean - testbed_avg`.
