# MDN training for KubeTwin

Scripts that produce the MDN service-time models KubeTwin reads through
`:mdn_file` (`mdn_models/<prefix><service>_weights.json`). An MDN gives, for
an input RPS, a Gaussian mixture over the log of a service's processing time.

| file | what |
|---|---|
| `mdn_service_time_predictor.py` | MDN, training, evaluation and JSON export; copied unchanged from OPTIMUUM-estensioni (commit 149761e) |
| `span_segments.py` | per-request segments from muBench/Jaeger traces; copied from tracesim (commit fb572c2) |
| `train_ragbench.py` | ragbench → `mdn_models/ragbench_bologna_*_weights.json` |
| `train_bookinfo_limits.py` | Bookinfo with CPU limits → `mdn_models/bookinfo_limits_*_weights.json` |

Python 3.10+ with `pip install -r tools/mdn/requirements.txt`.

## ragbench

Trained on the baseline deployment (one replica per service) at 1 RPS of a
ragbench data directory; nothing else, so every other scenario is predicted
blind. Processing time of a service = the sum of its self segments in one
request. The guardrail is not modelled.

```
D=<ragbench>/data_bologna_20261106/ragbench/ragbench_halfrequests_1/data
python tools/mdn/train_ragbench.py $D --mode train      # tools/mdn/models/ragbench/
python tools/mdn/train_ragbench.py $D --mode export     # <service>_weights.json there
python tools/mdn/train_ragbench.py $D --mode install    # -> mdn_models/ragbench_bologna_*
```

## Bookinfo with CPU limits

Bologna's dataset with CPU limits, one replica per service, 13 RPS levels
(1, 10, ..., 120); the traces `limits_traces_<rps>RPS.json` are in
OPTIMUUM-estensioni/bookinfo_with_limits/.

```
python tools/mdn/train_bookinfo_limits.py <dir with the traces> --mode train
python tools/mdn/train_bookinfo_limits.py <dir> --mode export
python tools/mdn/train_bookinfo_limits.py <dir> --mode install   # -> mdn_models/bookinfo_limits_*
```

## Reproducibility

Training is seeded (`--seed`, default 12345): the same data and seed give
identical weights. The weights currently in `mdn_models/` were trained
before this folder existed, without a seed, so a retraining gives slightly
different weights, not the same files. Checked on 26 November 2026: the
ragbench data extracted here is identical to the data the current weights
were trained on, and KubeTwin with retrained weights (seed 12345) predicts
the round-2 candidates (`ragbench_3c_2rtt_client.conf`) within +0.0…+0.8%
on the mean for A–D and +2.6% for E, the most loaded (p95 up to +5.4%).
That is the spread due to training alone. `install` overwrites the files in
`mdn_models/`; use `--mdn-models <dir>` to install somewhere else first.

`tools/mdn/models/` (models, scalers, extracted data) is not tracked.
