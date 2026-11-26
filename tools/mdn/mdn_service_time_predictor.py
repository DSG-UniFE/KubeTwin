# Copied from OPTIMUUM-estensioni (branch trace-driven-sim, commit 149761e,
# mdn_service_time_predictor.py) unchanged below this header, so that KubeTwin
# can regenerate its MDN weights (mdn_models/*_weights.json) by itself.
# The defaults (TRACE_FILES, MICROSERVICES, NAMESPACE_SUFFIX) are Bookinfo's;
# the train_*.py scripts in this folder override them per application.

"""
Mixture Density Network (MDN) for Service Time Prediction in Bookinfo Microservices.

Given an input RPS (requests per second), the MDN outputs the parameters of a
Gaussian Mixture Model in log-space, capturing the full conditional distribution
    p(log_processing_time | RPS)

This allows sampling realistic, variable service times that reflect how
processing time distributions shift and spread under different load levels.

Architecture:
    Input:  RPS (scalar, normalized)
    Hidden: Fully-connected layers with ReLU
    Output: For each of K mixture components:
        - pi_k:    mixing coefficient  (via softmax)
        - mu_k:    mean in log-space
        - sigma_k: std in log-space    (via exp, with floor)

Loss: Negative log-likelihood of the Gaussian mixture.

Usage:
    # Train models from scratch:
    python mdn_service_time_predictor.py --mode train

    # Generate service times with a trained model:
    python mdn_service_time_predictor.py --mode generate --rps 50 --service productpage --n 1000

    # Extract data only (for inspection):
    python mdn_service_time_predictor.py --mode extract

    # Evaluate a trained model (plots + metrics):
    python mdn_service_time_predictor.py --mode evaluate --service productpage
"""

import argparse
import json
import os
import pickle
import warnings
from pathlib import Path

import ijson
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset

warnings.filterwarnings("ignore")

# ============================================================================
# Configuration
# ============================================================================

TRACE_FILES = {
    1: "jaeger_traces_1RPS.json",
    10: "jaeger_traces_10RPS.json",
    30: "jaeger_traces_30RPS.json",
    50: "jaeger_traces_50RPS.json",
    70: "jaeger_traces_70RPS.json",
    90: "jaeger_traces_90RPS.json",
    110: "jaeger_traces_110RPS.json",
}

MICROSERVICES = ["productpage", "details", "reviews", "ratings"]

# Namespace suffix used in service names within these trace files
NAMESPACE_SUFFIX = ".bookinfo"

# MDN Hyperparameters
N_COMPONENTS = 5  # Number of Gaussian mixture components
HIDDEN_SIZE = 128  # Hidden layer size
N_HIDDEN_LAYERS = 3  # Number of hidden layers
DROPOUT = 0.1  # Dropout rate
BATCH_SIZE = 512
LEARNING_RATE = 1e-3
NUM_EPOCHS = 500
PATIENCE = 30  # Early stopping patience
SIGMA_MIN = 1e-4  # Minimum sigma to avoid numerical issues


def _get_device():
    if torch.cuda.is_available():
        return torch.device("cuda")
    elif torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


DEVICE = _get_device()

# Output directory for models
MODEL_DIR = Path("mdn_models")


# ============================================================================
# 1. Data Extraction - Parse Jaeger traces to get processing times
#    (Same logic as lstm_service_time_predictor.py)
# ============================================================================


def trace_generator(file_path):
    """
    Stream trace objects from a large JSON array file without loading
    the entire file into memory.
    """
    if not os.path.exists(file_path):
        print(f"  [WARNING] File not found: {file_path}")
        return

    try:
        with open(file_path, "rb") as f:
            for trace in ijson.items(f, "item"):
                yield trace
    except ijson.JSONError as e:
        print(f"  [ERROR] JSON parsing error: {e}")
    except Exception as e:
        print(f"  [ERROR] Unexpected error: {e}")


def _recursive_depth(span, trace_spans_by_id, counter=0):
    """Compute the depth of a span in the call tree."""
    if counter >= 15:
        return None
    if "depth" in span:
        return span["depth"]
    if not span["references"]:
        span["depth"] = 0
        return 0
    parent_id = span["references"][0]["spanID"]
    parent_span = trace_spans_by_id.get(parent_id)
    if parent_span is None:
        span["depth"] = 0
        return 0
    parent_depth = _recursive_depth(parent_span, trace_spans_by_id, counter + 1)
    if parent_depth is None:
        return None
    span["depth"] = parent_depth + 1
    return span["depth"]


def parse_trace(trace):
    """
    Parse a single Jaeger trace and extract processing times for each
    microservice. Processing time = total span duration - time spent
    waiting for downstream calls.

    Returns dict {service_name: processing_time_us} or None if trace is
    malformed.
    """
    service_map = {}
    for key, p in trace["processes"].items():
        service_map[key] = p["serviceName"]

    spans_by_id = {s["spanID"]: s for s in trace["spans"]}

    for span in trace["spans"]:
        span["serviceName"] = service_map.get(span["processID"], "unknown")
        if "depth" not in span:
            _recursive_depth(span, spans_by_id)

    t_productpage_total = None
    t_productpage_waiting = 0
    t_reviews_total = None
    t_reviews_waiting = 0
    t_details_total = None
    t_ratings_total = None

    for span in trace["spans"]:
        depth = span.get("depth")
        if depth is None:
            continue
        svc = span["serviceName"]
        dur = span["duration"]

        if depth == 2:
            t_productpage_total = dur
        elif depth == 3:
            t_productpage_waiting += dur
        elif depth == 4:
            if svc == f"details{NAMESPACE_SUFFIX}":
                t_details_total = dur
            else:
                t_reviews_total = dur
        elif depth == 5:
            t_reviews_waiting += dur
        elif depth == 6:
            t_ratings_total = dur

    try:
        pt_productpage = t_productpage_total - t_productpage_waiting
        pt_reviews = t_reviews_total - t_reviews_waiting
        pt_details = t_details_total
        pt_ratings = t_ratings_total

        if any(
            v is None or v <= 0
            for v in [pt_productpage, pt_reviews, pt_details, pt_ratings]
        ):
            return None

        return {
            "productpage": pt_productpage,
            "details": pt_details,
            "reviews": pt_reviews,
            "ratings": pt_ratings,
        }
    except (TypeError, ValueError):
        return None


def extract_data(base_dir="."):
    """
    Extract processing times from all trace files.

    Returns:
        dict: {service_name: list of (processing_time_us, rps)}
              for each service.
    """
    data = {svc: [] for svc in MICROSERVICES}

    for rps, filename in sorted(TRACE_FILES.items()):
        filepath = os.path.join(base_dir, filename)
        print(f"Processing {filename} (RPS={rps})...")

        trace_count = 0
        valid_count = 0

        for trace in trace_generator(filepath):
            trace_count += 1

            result = parse_trace(trace)
            if result is not None:
                valid_count += 1
                for svc in MICROSERVICES:
                    data[svc].append((result[svc], rps))

            if trace_count % 500 == 0:
                print(f"  Processed {trace_count} traces, {valid_count} valid...")

        print(f"  Done: {trace_count} traces, {valid_count} valid.\n")

    for svc in MICROSERVICES:
        print(f"  {svc}: {len(data[svc])} samples")

    return data


# ============================================================================
# 2. Preprocessing
# ============================================================================


class MDNDataset(Dataset):
    """
    PyTorch Dataset for the MDN.

    Each sample:
        X: (1,) - normalized RPS
        y: (1,) - log processing time (NOT z-score normalized, raw log)

    We work in log-space because processing times are lognormally distributed.
    The MDN will learn to predict the parameters of a Gaussian mixture in
    log-space directly.
    """

    def __init__(self, rps_norm, log_pt):
        self.X = rps_norm.reshape(-1, 1).astype(np.float32)
        self.y = log_pt.reshape(-1, 1).astype(np.float32)

    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        return torch.from_numpy(self.X[idx]), torch.from_numpy(self.y[idx])


def preprocess_service_data(service_data):
    """
    Preprocess raw (processing_time_us, rps) tuples.

    Strategy:
        - Log-transform processing times
        - Normalize RPS to [0, 1] using min-max
        - Z-score normalize log_pt using training set stats (helps MDN
          convergence; we denormalize when sampling)
        - Split: 70% train, 15% val, 15% test (shuffled, since MDN is i.i.d.)

    Returns:
        (train_dataset, val_dataset, test_dataset, scaler_dict)
    """
    times = np.array([x[0] for x in service_data], dtype=np.float64)
    rps_values = np.array([x[1] for x in service_data], dtype=np.float64)

    # Log-transform processing times
    log_pt = np.log(times).astype(np.float32)

    # Normalize RPS: min-max to [0, 1]
    rps_min, rps_max = float(rps_values.min()), float(rps_values.max())
    if rps_max > rps_min:
        rps_norm = ((rps_values - rps_min) / (rps_max - rps_min)).astype(np.float32)
    else:
        rps_norm = np.zeros_like(rps_values, dtype=np.float32)

    # Shuffle indices (MDN treats samples as i.i.d.)
    n = len(log_pt)
    indices = np.random.permutation(n)

    train_end = int(n * 0.70)
    val_end = int(n * 0.85)

    train_idx = indices[:train_end]
    val_idx = indices[train_end:val_end]
    test_idx = indices[val_end:]

    # Z-score normalization of log_pt based on training set
    log_pt_mean = float(log_pt[train_idx].mean())
    log_pt_std = float(log_pt[train_idx].std())
    if log_pt_std < 1e-8:
        log_pt_std = 1.0

    log_pt_norm = (log_pt - log_pt_mean) / log_pt_std

    # Create datasets
    train_ds = MDNDataset(rps_norm[train_idx], log_pt_norm[train_idx])
    val_ds = MDNDataset(rps_norm[val_idx], log_pt_norm[val_idx])
    test_ds = MDNDataset(rps_norm[test_idx], log_pt_norm[test_idx])

    scaler = {
        "log_pt_mean": log_pt_mean,
        "log_pt_std": log_pt_std,
        "rps_min": rps_min,
        "rps_max": rps_max,
    }

    return train_ds, val_ds, test_ds, scaler


# ============================================================================
# 3. MDN Model
# ============================================================================


class MixtureDensityNetwork(nn.Module):
    """
    Mixture Density Network.

    Given input x (normalized RPS), outputs the parameters of a Gaussian
    Mixture Model:
        pi:    (batch, K)  mixing coefficients (sum to 1)
        mu:    (batch, K)  means
        sigma: (batch, K)  standard deviations (positive)

    where K = n_components.
    """

    def __init__(
        self,
        input_dim=1,
        n_components=N_COMPONENTS,
        hidden_size=HIDDEN_SIZE,
        n_hidden_layers=N_HIDDEN_LAYERS,
        dropout=DROPOUT,
    ):
        super().__init__()
        self.n_components = n_components
        self.sigma_min: float = SIGMA_MIN

        # Build hidden layers
        layers = []
        in_features = input_dim
        for i in range(n_hidden_layers):
            layers.append(nn.Linear(in_features, hidden_size))
            layers.append(nn.ReLU())
            if dropout > 0:
                layers.append(nn.Dropout(dropout))
            in_features = hidden_size

        self.hidden = nn.Sequential(*layers)

        # Output heads: one for each mixture parameter
        # pi (mixing coefficients): K values, will be passed through softmax
        self.pi_head = nn.Linear(hidden_size, n_components)
        # mu (means): K values, unconstrained
        self.mu_head = nn.Linear(hidden_size, n_components)
        # sigma (std devs): K values, will be passed through exp
        self.sigma_head = nn.Linear(hidden_size, n_components)

    def forward(
        self, x: torch.Tensor
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """
        Args:
            x: (batch, input_dim) - normalized RPS

        Returns:
            pi:    (batch, K) - mixing coefficients (softmax)
            mu:    (batch, K) - means
            sigma: (batch, K) - standard deviations (positive)
        """
        h = self.hidden(x)

        pi = torch.softmax(self.pi_head(h), dim=-1)
        mu = self.mu_head(h)
        # ELU + 1 + epsilon ensures sigma > 0 and is smoother than exp
        # (avoids exploding gradients that exp can cause)
        sigma = nn.functional.elu(self.sigma_head(h)) + 1.0 + self.sigma_min

        return pi, mu, sigma


def mdn_log_likelihood(pi, mu, sigma, y):
    """
    Compute the log-likelihood of observations y under the Gaussian mixture.

    Args:
        pi:    (batch, K)  mixing coefficients
        mu:    (batch, K)  means
        sigma: (batch, K)  standard deviations
        y:     (batch, 1)  target values

    Returns:
        log_likelihood: (batch,) log p(y | pi, mu, sigma)
    """
    # Expand y to match components: (batch, K)
    y = y.expand_as(mu)

    # Log probability of y under each Gaussian component
    # log N(y; mu_k, sigma_k) = -0.5*log(2*pi) - log(sigma_k) - 0.5*((y-mu_k)/sigma_k)^2
    log_normal = (
        -0.5 * np.log(2 * np.pi) - torch.log(sigma) - 0.5 * ((y - mu) / sigma) ** 2
    )

    # log p(y) = log sum_k pi_k * N(y; mu_k, sigma_k)
    # Use logsumexp for numerical stability
    log_pi = torch.log(pi + 1e-10)
    log_prob = torch.logsumexp(log_pi + log_normal, dim=-1)  # (batch,)

    return log_prob


def mdn_loss(pi, mu, sigma, y):
    """
    Negative log-likelihood loss for the MDN.
    """
    log_prob = mdn_log_likelihood(pi, mu, sigma, y)
    return -log_prob.mean()


# ============================================================================
# 4. Training
# ============================================================================


def train_model(
    model,
    train_loader,
    val_loader,
    service_name,
    num_epochs=NUM_EPOCHS,
    patience=PATIENCE,
    lr=LEARNING_RATE,
):
    """
    Train one MDN model with early stopping based on validation NLL.
    """
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-5)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="min", factor=0.5, patience=patience // 3
    )

    best_val_loss = float("inf")
    best_state = None
    no_improve = 0

    for epoch in range(num_epochs):
        # --- Training ---
        model.train()
        train_loss = 0.0
        train_batches = 0
        for X_batch, y_batch in train_loader:
            X_batch, y_batch = X_batch.to(DEVICE), y_batch.to(DEVICE)
            optimizer.zero_grad()

            pi, mu, sigma = model(X_batch)
            loss = mdn_loss(pi, mu, sigma, y_batch)

            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
            optimizer.step()

            train_loss += loss.item()
            train_batches += 1

        avg_train_loss = train_loss / max(train_batches, 1)

        # --- Validation ---
        model.eval()
        val_loss = 0.0
        val_batches = 0
        with torch.no_grad():
            for X_batch, y_batch in val_loader:
                X_batch, y_batch = X_batch.to(DEVICE), y_batch.to(DEVICE)
                pi, mu, sigma = model(X_batch)
                loss = mdn_loss(pi, mu, sigma, y_batch)
                val_loss += loss.item()
                val_batches += 1

        avg_val_loss = val_loss / max(val_batches, 1)
        scheduler.step(avg_val_loss)

        if (epoch + 1) % 10 == 0 or epoch == 0:
            current_lr = optimizer.param_groups[0]["lr"]
            print(
                f"  [{service_name}] Epoch {epoch + 1:3d}/{num_epochs} | "
                f"Train NLL: {avg_train_loss:.4f} | "
                f"Val NLL: {avg_val_loss:.4f} | "
                f"LR: {current_lr:.2e}"
            )

        # Early stopping
        if avg_val_loss < best_val_loss:
            best_val_loss = avg_val_loss
            best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= patience:
                print(
                    f"  [{service_name}] Early stopping at epoch {epoch + 1}. "
                    f"Best val NLL: {best_val_loss:.4f}"
                )
                break

    if best_state is not None:
        model.load_state_dict(best_state)
    model.to(DEVICE)
    return best_val_loss


# ============================================================================
# 5. Evaluation
# ============================================================================


def evaluate_model(model, test_loader, scaler):
    """
    Evaluate the MDN on the test set.

    Returns metrics comparing samples from the learned mixture against
    the true processing times, plus the test NLL.
    """
    model.eval()

    all_pi, all_mu, all_sigma = [], [], []
    all_y = []

    with torch.no_grad():
        for X_batch, y_batch in test_loader:
            X_batch = X_batch.to(DEVICE)
            pi, mu, sigma = model(X_batch)
            all_pi.append(pi.cpu().numpy())
            all_mu.append(mu.cpu().numpy())
            all_sigma.append(sigma.cpu().numpy())
            all_y.append(y_batch.numpy())

    pi = np.concatenate(all_pi, axis=0)  # (N, K)
    mu = np.concatenate(all_mu, axis=0)  # (N, K)
    sigma = np.concatenate(all_sigma, axis=0)  # (N, K)
    y_norm = np.concatenate(all_y, axis=0).flatten()  # (N,)

    # Compute test NLL
    # Convert back to torch for the log-likelihood computation
    pi_t = torch.from_numpy(pi)
    mu_t = torch.from_numpy(mu)
    sigma_t = torch.from_numpy(sigma)
    y_t = torch.from_numpy(y_norm).unsqueeze(-1)
    test_nll = -mdn_log_likelihood(pi_t, mu_t, sigma_t, y_t).mean().item()

    # Denormalize targets to log-space then microseconds
    y_log = y_norm * scaler["log_pt_std"] + scaler["log_pt_mean"]
    y_us = np.exp(y_log)

    # Sample from the mixture for each test point
    n = len(y_norm)
    samples_norm = np.zeros(n)
    for i in range(n):
        # Choose component
        k = np.random.choice(len(pi[i]), p=pi[i])
        # Sample from that Gaussian
        samples_norm[i] = np.random.normal(mu[i, k], sigma[i, k])

    # Denormalize samples
    samples_log = samples_norm * scaler["log_pt_std"] + scaler["log_pt_mean"]
    samples_us = np.exp(samples_log)

    # Compute metrics in microseconds
    mae_us = np.mean(np.abs(samples_us - y_us))
    rmse_us = np.sqrt(np.mean((samples_us - y_us) ** 2))
    # Use the mixture mean (weighted) as point prediction for MAPE
    mu_denorm = mu * scaler["log_pt_std"] + scaler["log_pt_mean"]
    weighted_mean_log = np.sum(pi * mu_denorm, axis=1)  # (N,)
    pred_us = np.exp(weighted_mean_log)
    mape = np.mean(np.abs((y_us - pred_us) / y_us)) * 100

    return {
        "test_nll": float(test_nll),
        "mae_us": float(mae_us),
        "rmse_us": float(rmse_us),
        "mape_percent": float(mape),
        "mean_true_us": float(np.mean(y_us)),
        "mean_pred_us": float(np.mean(pred_us)),
        "std_true_us": float(np.std(y_us)),
        "std_samples_us": float(np.std(samples_us)),
    }


def evaluate_per_rps(model, service_data, scaler):
    """
    Evaluate the model's distribution at each known RPS level by comparing
    statistics of generated samples vs real data.
    """
    model.eval()
    rps_levels = sorted(TRACE_FILES.keys())
    results = {}

    for rps in rps_levels:
        # Get real data for this RPS
        real_times = np.array(
            [x[0] for x in service_data if x[1] == rps], dtype=np.float64
        )
        if len(real_times) == 0:
            continue

        # Generate same number of samples from MDN
        rps_norm = (rps - scaler["rps_min"]) / max(
            scaler["rps_max"] - scaler["rps_min"], 1e-8
        )
        x_input = torch.tensor([[rps_norm]], dtype=torch.float32).to(DEVICE)

        with torch.no_grad():
            pi, mu, sigma = model(x_input)

        pi_np = pi.cpu().numpy().flatten()
        mu_np = mu.cpu().numpy().flatten()
        sigma_np = sigma.cpu().numpy().flatten()

        # Denormalize mu and sigma to log-space
        mu_log = mu_np * scaler["log_pt_std"] + scaler["log_pt_mean"]
        sigma_log = sigma_np * scaler["log_pt_std"]

        # Sample
        n_samples = len(real_times)
        generated = np.zeros(n_samples)
        for i in range(n_samples):
            k = np.random.choice(len(pi_np), p=pi_np)
            log_sample = np.random.normal(mu_log[k], sigma_log[k])
            generated[i] = np.exp(log_sample)

        results[rps] = {
            "n_real": len(real_times),
            "real_mean": float(np.mean(real_times)),
            "real_std": float(np.std(real_times)),
            "real_median": float(np.median(real_times)),
            "real_p95": float(np.percentile(real_times, 95)),
            "gen_mean": float(np.mean(generated)),
            "gen_std": float(np.std(generated)),
            "gen_median": float(np.median(generated)),
            "gen_p95": float(np.percentile(generated, 95)),
            "mixture_weights": pi_np.tolist(),
            "mixture_means_log": mu_log.tolist(),
            "mixture_stds_log": sigma_log.tolist(),
        }

    return results


# ============================================================================
# 6. Service Time Generator (for simulator use)
# ============================================================================


class ServiceTimeGenerator:
    """
    Generate service times for a given microservice at a specified RPS.

    Loads a trained MDN and its scaler, and produces service time values
    sampled from the learned conditional distribution.

    Unlike the LSTM-based generator, this is stateless: each sample is
    drawn independently from p(service_time | RPS).

    The output unit can be chosen at construction time:
        - "us" (default): microseconds (as in the training data)
        - "ms": milliseconds
        - "s":  seconds

    Usage:
        # Default: microseconds
        gen = ServiceTimeGenerator("productpage", model_dir="mdn_models")
        t_us = gen.generate_one(rps=50)

        # For a simulator that expects seconds:
        gen = ServiceTimeGenerator("productpage", output_unit="s")
        t_s = gen.generate_one(rps=50)

        # Batch generation
        times = gen.generate(rps=50, n_samples=1000)
    """

    _UNIT_DIVISORS = {"us": 1.0, "ms": 1e3, "s": 1e6}

    def __init__(
        self, service_name, model_dir=MODEL_DIR, device=None, output_unit="us"
    ):
        if output_unit not in self._UNIT_DIVISORS:
            raise ValueError(
                f"output_unit must be one of {list(self._UNIT_DIVISORS.keys())}, "
                f"got '{output_unit}'"
            )
        self.service_name = service_name
        self.output_unit = output_unit
        self._divisor = self._UNIT_DIVISORS[output_unit]
        self.device = device or DEVICE
        model_path = Path(model_dir)

        # Load scaler
        with open(model_path / f"{service_name}_scaler.pkl", "rb") as f:
            self.scaler = pickle.load(f)

        # Load model config
        config_path = model_path / f"{service_name}_config.json"
        if config_path.exists():
            with open(config_path, "r") as f:
                config = json.load(f)
            self.model = MixtureDensityNetwork(
                n_components=config["n_components"],
                hidden_size=config["hidden_size"],
                n_hidden_layers=config["n_hidden_layers"],
            )
        else:
            self.model = MixtureDensityNetwork()

        state = torch.load(
            model_path / f"{service_name}_mdn.pt",
            map_location=self.device,
            weights_only=True,
        )
        self.model.load_state_dict(state)
        self.model.to(self.device)
        self.model.eval()

        # Pre-compute mixture parameters cache for common RPS values
        self._cache = {}

    def _normalize_rps(self, rps):
        rmin = self.scaler["rps_min"]
        rmax = self.scaler["rps_max"]
        if rmax > rmin:
            return (rps - rmin) / (rmax - rmin)
        return 0.0

    def _get_mixture_params(self, rps):
        """
        Get mixture parameters for a given RPS.
        Caches results for repeated calls with the same RPS.
        """
        if rps in self._cache:
            return self._cache[rps]

        rps_norm = self._normalize_rps(rps)
        x = torch.tensor([[rps_norm]], dtype=torch.float32).to(self.device)

        with torch.no_grad():
            pi, mu, sigma = self.model(x)

        pi_np = pi.cpu().numpy().flatten()
        mu_np = mu.cpu().numpy().flatten()
        sigma_np = sigma.cpu().numpy().flatten()

        # Denormalize to log-space
        mu_log = mu_np * self.scaler["log_pt_std"] + self.scaler["log_pt_mean"]
        sigma_log = sigma_np * self.scaler["log_pt_std"]

        params = (pi_np, mu_log, np.abs(sigma_log))
        self._cache[rps] = params
        return params

    def generate_one(self, rps):
        """
        Generate a single service time given the current RPS.

        Returns the value in the unit specified at construction
        (default: microseconds).
        """
        pi, mu_log, sigma_log = self._get_mixture_params(rps)

        # Choose mixture component
        k = np.random.choice(len(pi), p=pi)
        # Sample from that Gaussian in log-space
        log_sample = np.random.normal(mu_log[k], sigma_log[k])
        # Convert to microseconds, then to requested unit
        service_time = np.exp(log_sample) / self._divisor

        return max(service_time, 1.0 / self._divisor)

    def generate(self, rps, n_samples=100):
        """
        Generate n_samples service times at a given RPS.

        Args:
            rps: Requests per second (load level)
            n_samples: Number of service times to generate

        Returns:
            np.array of service times in the unit specified at construction
            (default: microseconds).
        """
        pi, mu_log, sigma_log = self._get_mixture_params(rps)

        # Vectorized sampling
        # 1. Choose components for all samples
        components = np.random.choice(len(pi), size=n_samples, p=pi)

        # 2. Sample from the selected Gaussians
        log_samples = np.random.normal(mu_log[components], sigma_log[components])

        # 3. Convert to microseconds, then to requested unit
        samples = np.exp(log_samples) / self._divisor
        return np.maximum(samples, 1.0 / self._divisor)

    def get_distribution_params(self, rps):
        """
        Return the mixture parameters at a given RPS for inspection.

        Returns:
            dict with keys: pi, mu_log, sigma_log, mu_us (approximate means
            in microseconds), sigma_us_approx
        """
        pi, mu_log, sigma_log = self._get_mixture_params(rps)
        mu_us = np.exp(mu_log + 0.5 * sigma_log**2)  # E[X] for lognormal
        return {
            "pi": pi.tolist(),
            "mu_log": mu_log.tolist(),
            "sigma_log": sigma_log.tolist(),
            "mu_us": mu_us.tolist(),
        }


# ============================================================================
# 7. TorchScript Export (for torch.rb / libtorch)
# ============================================================================


class ScriptableMDNSampler(nn.Module):
    """
    Self-contained TorchScript-compatible module that wraps:
      1. The trained MDN network
      2. Scaler constants (rps_min, rps_max, log_pt_mean, log_pt_std)
      3. Mixture sampling logic
      4. Conversion from log-space microseconds to seconds

    This module can be loaded directly from torch.rb (or any libtorch binding)
    and used with a single forward call:

        Ruby:
            model = Torch::JIT.load("productpage_mdn_scripted.pt")
            service_time_s = model.forward(Torch.tensor([50.0])).item

        The input is the raw RPS value (not normalized).
        The output is a service time in seconds.
    """

    def __init__(
        self,
        mdn: MixtureDensityNetwork,
        rps_min: float,
        rps_max: float,
        log_pt_mean: float,
        log_pt_std: float,
    ):
        super().__init__()
        self.mdn = mdn
        self.rps_min = rps_min
        self.rps_max = rps_max
        self.log_pt_mean = log_pt_mean
        self.log_pt_std = log_pt_std
        # 1e6 us per second
        self.us_to_s = 1e-6

    @torch.jit.export
    def get_mixture_params(
        self, rps: torch.Tensor
    ) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        """
        Given raw RPS (scalar tensor), return (pi, mu_log, sigma_log)
        where mu_log and sigma_log are in original log-microsecond space.
        """
        # Normalize RPS
        rps_range = self.rps_max - self.rps_min
        if rps_range > 1e-8:
            rps_norm = (rps - self.rps_min) / rps_range
        else:
            rps_norm = torch.zeros_like(rps)

        x = rps_norm.unsqueeze(0).unsqueeze(-1)  # (1, 1)
        pi, mu, sigma = self.mdn(x)

        # Denormalize mu and sigma to log-microsecond space
        mu_log = mu * self.log_pt_std + self.log_pt_mean
        sigma_log = torch.abs(sigma * self.log_pt_std)

        return pi.squeeze(0), mu_log.squeeze(0), sigma_log.squeeze(0)

    def forward(self, rps: torch.Tensor) -> torch.Tensor:
        """
        Sample a service time in seconds given a raw RPS value.

        Args:
            rps: scalar tensor with the RPS value (e.g. torch.tensor(50.0))

        Returns:
            scalar tensor: service time in seconds
        """
        pi, mu_log, sigma_log = self.get_mixture_params(rps)

        # Sample mixture component using Gumbel-max trick
        # (torch.multinomial is not always available in all TorchScript contexts)
        gumbel_noise = -torch.log(-torch.log(torch.rand_like(pi) + 1e-10) + 1e-10)
        k = torch.argmax(torch.log(pi + 1e-10) + gumbel_noise)

        # Sample from the selected Gaussian
        mu_k = mu_log[k]
        sigma_k = sigma_log[k]
        z = torch.randn(1)
        log_sample = mu_k + sigma_k * z[0]

        # Convert: exp(log_us) -> us -> seconds
        service_time_s = torch.exp(log_sample) * self.us_to_s

        # Floor at 1 microsecond = 1e-6 seconds
        return torch.clamp(service_time_s, min=1e-6)

    @torch.jit.export
    def sample_batch(self, rps: torch.Tensor, n: int) -> torch.Tensor:
        """
        Sample n service times in seconds given a raw RPS value.
        More efficient than calling forward() n times.

        Args:
            rps: scalar tensor with the RPS value
            n: number of samples

        Returns:
            tensor of shape (n,): service times in seconds
        """
        pi, mu_log, sigma_log = self.get_mixture_params(rps)
        K = pi.shape[0]

        # Sample components for all n samples (Gumbel-max trick)
        gumbel_noise = -torch.log(-torch.log(torch.rand(n, K) + 1e-10) + 1e-10)
        log_pi = torch.log(pi + 1e-10).unsqueeze(0).expand(n, -1)
        components = torch.argmax(log_pi + gumbel_noise, dim=-1)  # (n,)

        # Gather mu and sigma for selected components
        mu_selected = mu_log[components]  # (n,)
        sigma_selected = sigma_log[components]  # (n,)

        # Sample from Gaussians
        z = torch.randn(n)
        log_samples = mu_selected + sigma_selected * z

        # Convert to seconds
        samples_s = torch.exp(log_samples) * self.us_to_s
        return torch.clamp(samples_s, min=1e-6)


def export_torchscript(model_dir=MODEL_DIR):
    """
    Export all trained MDN models as TorchScript modules that can be
    loaded from torch.rb or any libtorch binding.

    Each exported model is self-contained: it includes the network weights,
    scaler constants, sampling logic, and us->seconds conversion.
    """
    model_path = Path(model_dir)
    exported = []

    for svc in MICROSERVICES:
        mdn_file = model_path / f"{svc}_mdn.pt"
        scaler_file = model_path / f"{svc}_scaler.pkl"
        config_file = model_path / f"{svc}_config.json"

        if not mdn_file.exists() or not scaler_file.exists():
            print(f"  [SKIP] {svc}: model or scaler not found")
            continue

        # Load scaler
        with open(scaler_file, "rb") as f:
            scaler = pickle.load(f)

        # Load MDN
        if config_file.exists():
            with open(config_file, "r") as f:
                config = json.load(f)
            mdn = MixtureDensityNetwork(
                n_components=config["n_components"],
                hidden_size=config["hidden_size"],
                n_hidden_layers=config["n_hidden_layers"],
            )
        else:
            mdn = MixtureDensityNetwork()

        state = torch.load(mdn_file, map_location="cpu", weights_only=True)
        mdn.load_state_dict(state)
        mdn.eval()

        # Create the scriptable sampler
        sampler = ScriptableMDNSampler(
            mdn=mdn,
            rps_min=scaler["rps_min"],
            rps_max=scaler["rps_max"],
            log_pt_mean=scaler["log_pt_mean"],
            log_pt_std=scaler["log_pt_std"],
        )
        sampler.eval()

        # Script it
        scripted = torch.jit.script(sampler)

        # Save
        out_path = model_path / f"{svc}_mdn_scripted.pt"
        scripted.save(str(out_path))
        exported.append(svc)
        print(f"  {svc}: exported to {out_path}")

    return exported


def export_weights_json(model_dir=MODEL_DIR):
    """
    Export trained MDN model weights and scaler as JSON for torch-rb.

    This creates a JSON file containing:
    - weights: all model parameters as plain lists
    - scaler: normalization parameters (rps_min, rps_max, log_pt_mean, log_pt_std)

    The JSON can be loaded in Ruby and used for manual forward pass.
    """
    model_path = Path(model_dir)
    exported = []

    for svc in MICROSERVICES:
        mdn_file = model_path / f"{svc}_mdn.pt"
        scaler_file = model_path / f"{svc}_scaler.pkl"
        config_file = model_path / f"{svc}_config.json"

        if not mdn_file.exists() or not scaler_file.exists():
            print(f"  [SKIP] {svc}: model or scaler not found")
            continue

        # Load scaler
        with open(scaler_file, "rb") as f:
            scaler = pickle.load(f)

        # Load model
        if config_file.exists():
            with open(config_file, "r") as f:
                config = json.load(f)
            mdn = MixtureDensityNetwork(
                n_components=config["n_components"],
                hidden_size=config["hidden_size"],
                n_hidden_layers=config["n_hidden_layers"],
            )
        else:
            mdn = MixtureDensityNetwork()

        state = torch.load(mdn_file, map_location="cpu", weights_only=True)
        mdn.load_state_dict(state)
        mdn.eval()

        # Extract weights as plain lists
        weights = {}
        for key, value in state.items():
            weights[key] = value.cpu().numpy().tolist()

        # Build scaler dict (convert numpy to native Python types)
        scaler_export = {
            "rps_min": float(scaler["rps_min"]),
            "rps_max": float(scaler["rps_max"]),
            "log_pt_mean": float(scaler["log_pt_mean"]),
            "log_pt_std": float(scaler["log_pt_std"]),
        }

        # Save as JSON
        export_data = {
            "weights": weights,
            "scaler": scaler_export,
        }

        out_path = model_path / f"{svc}_weights.json"
        with open(out_path, "w") as f:
            json.dump(export_data, f, indent=2)

        exported.append(svc)
        print(f"  {svc}: exported to {out_path}")

    return exported


# ============================================================================
# 8. Main Pipeline
# ============================================================================


def run_training(base_dir="."):
    """Run the full training pipeline for all microservices."""
    MODEL_DIR.mkdir(exist_ok=True)

    # Step 1: Extract data
    print("=" * 60)
    print("STEP 1: Extracting data from Jaeger traces")
    print("=" * 60)
    data = extract_data(base_dir)

    # Save extracted data for reuse
    cache_path = MODEL_DIR / "extracted_data.pkl"
    with open(cache_path, "wb") as f:
        pickle.dump(data, f)
    print(f"\nExtracted data cached to {cache_path}\n")

    results = {}

    for svc in MICROSERVICES:
        print("=" * 60)
        print(f"STEP 2: Training MDN for '{svc}'")
        print("=" * 60)

        if len(data[svc]) < 50:
            print(
                f"  [SKIP] Not enough data for {svc} "
                f"({len(data[svc])} samples, need >= 50)"
            )
            continue

        # Preprocess
        train_ds, val_ds, test_ds, scaler = preprocess_service_data(data[svc])
        print(f"  Train: {len(train_ds)}, Val: {len(val_ds)}, Test: {len(test_ds)}")

        # Save scaler
        with open(MODEL_DIR / f"{svc}_scaler.pkl", "wb") as f:
            pickle.dump(scaler, f)

        # Save model config for reproducibility
        config = {
            "n_components": N_COMPONENTS,
            "hidden_size": HIDDEN_SIZE,
            "n_hidden_layers": N_HIDDEN_LAYERS,
            "dropout": DROPOUT,
        }
        with open(MODEL_DIR / f"{svc}_config.json", "w") as f:
            json.dump(config, f, indent=2)

        # Create data loaders
        train_loader = DataLoader(
            train_ds,
            batch_size=BATCH_SIZE,
            shuffle=True,
            num_workers=0,
            pin_memory=True,
        )
        val_loader = DataLoader(
            val_ds,
            batch_size=BATCH_SIZE,
            shuffle=False,
            num_workers=0,
            pin_memory=True,
        )
        test_loader = DataLoader(
            test_ds,
            batch_size=BATCH_SIZE,
            shuffle=False,
            num_workers=0,
            pin_memory=True,
        )

        # Create and train model
        model = MixtureDensityNetwork().to(DEVICE)
        param_count = sum(p.numel() for p in model.parameters() if p.requires_grad)
        print(f"  Model parameters: {param_count:,}")
        print(f"  Mixture components: {N_COMPONENTS}")
        print(f"  Device: {DEVICE}")
        print()

        best_val = train_model(model, train_loader, val_loader, svc)

        # Save model
        torch.save(model.state_dict(), MODEL_DIR / f"{svc}_mdn.pt")
        print(f"\n  Model saved to {MODEL_DIR / f'{svc}_mdn.pt'}")

        # Evaluate on test set
        metrics = evaluate_model(model, test_loader, scaler)
        results[svc] = {"test_metrics": metrics}

        print(f"\n  Test metrics for '{svc}':")
        print(f"    NLL:                {metrics['test_nll']:.4f}")
        print(f"    MAE (us):           {metrics['mae_us']:.1f}")
        print(f"    RMSE (us):          {metrics['rmse_us']:.1f}")
        print(f"    MAPE:               {metrics['mape_percent']:.1f}%")
        print(f"    Mean true (us):     {metrics['mean_true_us']:.1f}")
        print(f"    Mean pred (us):     {metrics['mean_pred_us']:.1f}")
        print(f"    Std true (us):      {metrics['std_true_us']:.1f}")
        print(f"    Std samples (us):   {metrics['std_samples_us']:.1f}")

        # Per-RPS evaluation
        per_rps = evaluate_per_rps(model, data[svc], scaler)
        results[svc]["per_rps"] = per_rps

        print(f"\n  Per-RPS comparison for '{svc}':")
        for rps_level, r in sorted(per_rps.items()):
            print(
                f"    RPS={rps_level:3d}: "
                f"real_mean={r['real_mean']:10.1f} us, "
                f"gen_mean={r['gen_mean']:10.1f} us | "
                f"real_std={r['real_std']:10.1f} us, "
                f"gen_std={r['gen_std']:10.1f} us | "
                f"real_p95={r['real_p95']:10.1f} us, "
                f"gen_p95={r['gen_p95']:10.1f} us"
            )
        print()

    # Summary
    print("=" * 60)
    print("TRAINING SUMMARY")
    print("=" * 60)
    for svc, res in results.items():
        m = res["test_metrics"]
        print(
            f"  {svc:15s} | NLL: {m['test_nll']:7.4f} | "
            f"MAPE: {m['mape_percent']:6.1f}% | "
            f"Mean true: {m['mean_true_us']:10.1f} us | "
            f"Std true: {m['std_true_us']:10.1f} us"
        )

    # Save summary
    summary_path = MODEL_DIR / "training_summary.json"
    with open(summary_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nSummary saved to {summary_path}")


def run_generate(service_name, rps, n_samples):
    """Generate service times using a trained MDN model."""
    print(f"Loading MDN model for '{service_name}'...")
    gen = ServiceTimeGenerator(service_name)

    print(f"Generating {n_samples} service times at {rps} RPS...")
    times = gen.generate(rps=rps, n_samples=n_samples)

    print(f"\nResults for '{service_name}' at {rps} RPS:")
    print(f"  Mean:   {np.mean(times):10.1f} us ({np.mean(times) / 1e3:.2f} ms)")
    print(f"  Median: {np.median(times):10.1f} us ({np.median(times) / 1e3:.2f} ms)")
    print(f"  Std:    {np.std(times):10.1f} us")
    print(f"  Min:    {np.min(times):10.1f} us")
    print(f"  Max:    {np.max(times):10.1f} us")
    print(f"  P95:    {np.percentile(times, 95):10.1f} us")
    print(f"  P99:    {np.percentile(times, 99):10.1f} us")

    # Show mixture parameters
    params = gen.get_distribution_params(rps)
    print(f"\n  Mixture parameters at RPS={rps}:")
    for k in range(len(params["pi"])):
        print(
            f"    Component {k}: "
            f"pi={params['pi'][k]:.4f}, "
            f"mu_log={params['mu_log'][k]:.4f}, "
            f"sigma_log={params['sigma_log'][k]:.4f}, "
            f"~mean_us={params['mu_us'][k]:.1f}"
        )

    return times


def run_extract(base_dir="."):
    """Extract data only and print summary statistics."""
    data = extract_data(base_dir)

    MODEL_DIR.mkdir(exist_ok=True)
    cache_path = MODEL_DIR / "extracted_data.pkl"
    with open(cache_path, "wb") as f:
        pickle.dump(data, f)
    print(f"\nData saved to {cache_path}")

    for svc in MICROSERVICES:
        samples = data[svc]
        if not samples:
            print(f"\n{svc}: no data")
            continue
        times = np.array([x[0] for x in samples])
        rps_vals = np.array([x[1] for x in samples])
        print(f"\n{svc} ({len(samples)} samples):")
        print(
            f"  Processing time: mean={np.mean(times):.1f} us, "
            f"median={np.median(times):.1f} us, std={np.std(times):.1f} us"
        )
        for rps_level in sorted(TRACE_FILES.keys()):
            mask = rps_vals == rps_level
            if mask.any():
                t = times[mask]
                print(
                    f"    RPS={rps_level:3d}: n={mask.sum():6d}, "
                    f"mean={np.mean(t):.1f} us, "
                    f"median={np.median(t):.1f} us, "
                    f"std={np.std(t):.1f} us"
                )


def run_evaluate(service_name, base_dir="."):
    """Evaluate a trained model and optionally generate plots."""
    print(f"Loading MDN model for '{service_name}'...")
    gen = ServiceTimeGenerator(service_name)

    # Load real data
    cache_path = MODEL_DIR / "extracted_data.pkl"
    if cache_path.exists():
        print("Loading cached data...")
        with open(cache_path, "rb") as f:
            data = pickle.load(f)
    else:
        print("Extracting data from traces...")
        data = extract_data(base_dir)

    service_data = data[service_name]

    print(f"\nDistribution comparison for '{service_name}':")
    print("-" * 70)

    for rps in sorted(TRACE_FILES.keys()):
        real_times = np.array(
            [x[0] for x in service_data if x[1] == rps], dtype=np.float64
        )
        if len(real_times) == 0:
            continue

        gen_times = gen.generate(rps=rps, n_samples=len(real_times))
        params = gen.get_distribution_params(rps)

        print(f"\n  RPS = {rps}  ({len(real_times)} samples)")
        print(f"    {'':20s} {'Real':>12s} {'Generated':>12s}")
        print(
            f"    {'Mean (us)':20s} {np.mean(real_times):12.1f} {np.mean(gen_times):12.1f}"
        )
        print(
            f"    {'Median (us)':20s} {np.median(real_times):12.1f} {np.median(gen_times):12.1f}"
        )
        print(
            f"    {'Std (us)':20s} {np.std(real_times):12.1f} {np.std(gen_times):12.1f}"
        )
        print(
            f"    {'P5 (us)':20s} {np.percentile(real_times, 5):12.1f} {np.percentile(gen_times, 5):12.1f}"
        )
        print(
            f"    {'P95 (us)':20s} {np.percentile(real_times, 95):12.1f} {np.percentile(gen_times, 95):12.1f}"
        )
        print(
            f"    {'Min (us)':20s} {np.min(real_times):12.1f} {np.min(gen_times):12.1f}"
        )
        print(
            f"    {'Max (us)':20s} {np.max(real_times):12.1f} {np.max(gen_times):12.1f}"
        )

        print(f"    Mixture: ", end="")
        for k in range(len(params["pi"])):
            if params["pi"][k] > 0.01:
                print(
                    f"[pi={params['pi'][k]:.3f}, ~{params['mu_us'][k]:.0f}us] ",
                    end="",
                )
        print()

    # Try to generate plots if matplotlib is available
    try:
        import matplotlib.pyplot as plt

        fig, axes = plt.subplots(1, len(TRACE_FILES), figsize=(5 * len(TRACE_FILES), 4))
        if len(TRACE_FILES) == 1:
            axes = [axes]

        for ax, rps in zip(axes, sorted(TRACE_FILES.keys())):
            real_times = np.array(
                [x[0] for x in service_data if x[1] == rps], dtype=np.float64
            )
            if len(real_times) == 0:
                continue

            gen_times = gen.generate(rps=rps, n_samples=len(real_times))

            # Plot in log-space for better visualization
            ax.hist(
                np.log(real_times),
                bins=80,
                density=True,
                alpha=0.5,
                label="Real",
                color="steelblue",
            )
            ax.hist(
                np.log(gen_times),
                bins=80,
                density=True,
                alpha=0.5,
                label="MDN",
                color="coral",
            )
            ax.set_title(f"{service_name} @ {rps} RPS")
            ax.set_xlabel("log(processing time) [log-us]")
            ax.set_ylabel("Density")
            ax.legend()

        plt.tight_layout()
        plot_path = MODEL_DIR / f"{service_name}_mdn_eval.png"
        plt.savefig(plot_path, dpi=150, bbox_inches="tight")
        print(f"\n  Plot saved to {plot_path}")
        plt.close()

    except ImportError:
        print("\n  [INFO] matplotlib not available, skipping plots.")


# ============================================================================
# Entry point
# ============================================================================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="MDN-based Service Time Predictor for Bookinfo Microservices"
    )
    parser.add_argument(
        "--mode",
        choices=["train", "generate", "extract", "evaluate", "export", "export-json"],
        default="train",
        help=(
            "Mode: 'train' to train models, 'generate' to produce service times, "
            "'extract' to extract and inspect data, 'evaluate' to compare distributions, "
            "'export' to export TorchScript models, 'export-json' to export weights as JSON for torch-rb."
        ),
    )
    parser.add_argument(
        "--service",
        type=str,
        default="productpage",
        choices=MICROSERVICES,
        help="Microservice name (for generate/evaluate modes).",
    )
    parser.add_argument(
        "--rps",
        type=float,
        default=30,
        help="RPS level for generation.",
    )
    parser.add_argument(
        "--n",
        type=int,
        default=1000,
        help="Number of service times to generate.",
    )
    parser.add_argument(
        "--base-dir",
        type=str,
        default=".",
        help="Base directory containing the Jaeger trace JSON files.",
    )

    args = parser.parse_args()

    if args.mode == "train":
        run_training(args.base_dir)
    elif args.mode == "generate":
        run_generate(args.service, args.rps, args.n)
    elif args.mode == "extract":
        run_extract(args.base_dir)
    elif args.mode == "evaluate":
        run_evaluate(args.service, args.base_dir)
    elif args.mode == "export":
        print("=" * 60)
        print("Exporting TorchScript models for torch.rb")
        print("=" * 60)
        exported = export_torchscript()
        if exported:
            print(f"\nExported {len(exported)} models: {', '.join(exported)}")
            print("\nUsage in Ruby:")
            print("  model = Torch::JIT.load('mdn_models/<service>_mdn_scripted.pt')")
            print("  time_s = model.forward(Torch.tensor([50.0])).item")
            print("  times = model.sample_batch(Torch.tensor([50.0]), 100)")
        else:
            print("\nNo models found to export. Run --mode train first.")
    elif args.mode == "export-json":
        print("Exporting model weights as JSON for torch-rb")
        print("=" * 60)
        exported = export_weights_json()
        if exported:
            print(f"\nExported {len(exported)} models: {', '.join(exported)}")
            print("\nUsage in Ruby:")
            print("  model = KUBETWIN::MDN.new(")
            print("    weights_path: 'mdn_models/<service>_weights.json',")
            print("    scaler_path: 'mdn_models/<service>_weights.json'")
            print("  )")
            print("  time_s = model.forward(50)")
        else:
            print("\nNo models found to export. Run --mode train first.")
