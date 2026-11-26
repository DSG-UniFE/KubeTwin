"""
Train the Bookinfo MDNs on Bologna's dataset with CPU limits (1 replica per
service, 13 RPS levels 1-120) and install their weights in KubeTwin's
mdn_models/ (bookinfo_limits_*_weights.json, used by
examples/bookinfo_with_limits.conf).

Moved here from OPTIMUUM-estensioni/bookinfo_with_limits/
train_bookinfo_limits_mdn.py (commit 29808ae): same overrides of
mdn_service_time_predictor (trace files, namespace suffix), which parses the
Istio/Jaeger traces itself.

Usage (from the KubeTwin root):
    python tools/mdn/train_bookinfo_limits.py <dir with limits_traces_<rps>RPS.json> --mode train [--seed N]
    python tools/mdn/train_bookinfo_limits.py <dir> --mode export
    python tools/mdn/train_bookinfo_limits.py <dir> --mode install [--prefix bookinfo_limits_]
"""
import argparse
import random
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mdn_service_time_predictor as mdn  # noqa: E402

RPS_LEVELS = [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
SERVICES = ["productpage", "details", "reviews", "ratings"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", type=Path, help="dir with limits_traces_<rps>RPS.json")
    ap.add_argument("--mode", choices=["train", "export", "install"], default="train")
    ap.add_argument("--out", type=Path, default=HERE / "models" / "bookinfo_limits")
    ap.add_argument("--seed", type=int, default=12345, help="numpy/torch seed for training")
    ap.add_argument("--prefix", default="bookinfo_limits_",
                    help="file prefix in mdn_models/ (install)")
    ap.add_argument("--mdn-models", type=Path, default=HERE.parent.parent / "mdn_models")
    a = ap.parse_args()

    mdn.TRACE_FILES = {rps: f"limits_traces_{rps}RPS.json" for rps in RPS_LEVELS}
    mdn.NAMESPACE_SUFFIX = ".validation"
    mdn.MICROSERVICES = SERVICES
    mdn.MODEL_DIR = a.out
    a.out.mkdir(parents=True, exist_ok=True)
    if a.mode == "train":
        random.seed(a.seed)
        mdn.np.random.seed(a.seed)
        mdn.torch.manual_seed(a.seed)
        mdn.run_training(base_dir=str(a.data))
    elif a.mode == "export":
        print("Exported:", mdn.export_weights_json(model_dir=a.out))
    else:
        for s in SERVICES:
            if not (a.out / f"{s}_weights.json").exists():
                continue
            dst = a.mdn_models / f"{a.prefix}{s}_weights.json"
            shutil.copyfile(a.out / f"{s}_weights.json", dst)
            print(f"  {s} -> {dst}")


if __name__ == "__main__":
    main()
