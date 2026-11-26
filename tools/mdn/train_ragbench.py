"""
Train the ragbench MDNs (one per service) from a ragbench data directory and
install their weights in KubeTwin's mdn_models/.

Moved here from OPTIMUUM-estensioni/ragbench_bologna/train_ragbench_mdn.py
(never committed there); trace parsing from span_segments.py (a copy of
tracesim's). The MDN pipeline is mdn_service_time_predictor.py, unchanged.

Data: the baseline's 1-RPS traces only (blind: no what-if or higher-load
data), labelled RPS 1. Processing time of a service = the sum of its self
segments in one request (muBench compute_pi + framework). The guardrail is
not modelled. The current weights (mdn_models/ragbench_bologna_*_weights.json)
come from Bologna's one-cluster campaign:
ragbench/data_bologna_20261106/ragbench/ragbench_halfrequests_1/data.

Usage (from the KubeTwin root):
    python tools/mdn/train_ragbench.py <data dir> --mode train [--seed N]
    python tools/mdn/train_ragbench.py <data dir> --mode export
    python tools/mdn/train_ragbench.py <data dir> --mode install [--prefix ragbench_bologna_]

train writes models, scalers and extracted data to --out (default
tools/mdn/models/ragbench); export writes <service>_weights.json there;
install copies them to mdn_models/<prefix><service>_weights.json.
"""
import argparse
import random
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mdn_service_time_predictor as mdn  # noqa: E402
from span_segments import load_level  # noqa: E402

SERVICES = ["gateway", "embedder", "vector-search", "reranker", "llm-generate"]
LEVELS = {"baseline": [1]}


def extract(data_dir):
    def extract_data(base_dir="."):
        data = {s: [] for s in SERVICES}
        for scenario, levels in LEVELS.items():
            for rps in levels:
                df, _ = load_level(Path(data_dir) / scenario / f"traces_{rps}RPS.json",
                                   root_service="gateway")
                for s in SERVICES:
                    cols = [c for c in df.columns if c.startswith(f"{s}.self")]
                    pt_us = df[cols].sum(axis=1).dropna() * 1000.0
                    data[s] += [(float(v), rps) for v in pt_us if v > 0]
        for s in SERVICES:
            print(f"  {s}: {len(data[s])} samples")
        return data
    return extract_data


def seed_everything(seed):
    random.seed(seed)
    mdn.np.random.seed(seed)
    mdn.torch.manual_seed(seed)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", help="ragbench data dir (with baseline/traces_1RPS.json)")
    ap.add_argument("--mode", choices=["train", "export", "install"], default="train")
    ap.add_argument("--out", type=Path, default=HERE / "models" / "ragbench")
    ap.add_argument("--seed", type=int, default=12345, help="numpy/torch seed for training")
    ap.add_argument("--prefix", default="ragbench_bologna_",
                    help="file prefix in mdn_models/ (install)")
    ap.add_argument("--mdn-models", type=Path, default=HERE.parent.parent / "mdn_models")
    a = ap.parse_args()

    mdn.MICROSERVICES = SERVICES
    mdn.MODEL_DIR = a.out
    a.out.mkdir(parents=True, exist_ok=True)
    if a.mode == "train":
        seed_everything(a.seed)
        mdn.extract_data = extract(a.data)
        mdn.run_training()
    elif a.mode == "export":
        print("Exported:", mdn.export_weights_json(model_dir=a.out))
    else:
        for s in SERVICES:
            dst = a.mdn_models / f"{a.prefix}{s}_weights.json"
            shutil.copyfile(a.out / f"{s}_weights.json", dst)
            print(f"  {s} -> {dst}")


if __name__ == "__main__":
    main()
