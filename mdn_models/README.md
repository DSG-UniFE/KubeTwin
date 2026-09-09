# MDN - Mixture Density Network for Service Time Prediction

## Overview

The MDN (Mixture Density Network) takes **RPS** (Requests Per Second) as input and returns a full distribution of service times, not a single value.

This better captures real variability: at higher RPS, service times not only increase on average but also spread more.

## Architecture

```
Input: Normalized RPS (1 value)
    ↓
Hidden Layer 1: Linear(1, 128) + ReLU + Dropout(0.1)
    ↓
Hidden Layer 2: Linear(128, 128) + ReLU + Dropout(0.1)
    ↓
Hidden Layer 3: Linear(128, 128) + ReLU + Dropout(0.1)
    ↓
┌─────────────┬─────────────┬─────────────┐
│   pi_head   │   mu_head  │ sigma_head │
│  (128→5)   │  (128→5)   │  (128→5)   │
└─────────────┴─────────────┴─────────────┘
    ↓           ↓           ↓
    π (5)      μ (5)       σ (5)
  (softmax) (unconstrained) (ELU+1+ε)
```

- **π (pi)**: 5 mixture weights (sums to 1) - which component is more likely
- **μ (mu)**: 5 means in log-space
- **σ (sigma)**: 5 standard deviations (always positive)

The 5 Gaussian components allow modeling multimodal distributions.

## Training

```python
# Loss: Negative Log-Likelihood
NLL = -log_likelihood(y | π, μ, σ)
```

Minimizing NLL = maximizing the probability of observed data.

Training data comes from Jaeger traces at different RPS levels: 1, 10, 30, 50, 70, 90, 110.

## Hyperparameters

| Parameter | Value |
|-----------|-------|
| N_COMPONENTS | 5 |
| HIDDEN_SIZE | 128 |
| N_HIDDEN_LAYERS | 3 |
| DROPOUT | 0.1 |
| BATCH_SIZE | 512 |
| LEARNING_RATE | 1e-3 |
| NUM_EPOCHS | 500 |
| SIGMA_MIN | 1e-4 |

## Inference (Sampling)

```python
# 1. Forward pass → π, μ, σ
pi, mu, sigma = model(x)

# 2. Select component (Gumbel-max trick)
k = argmax(log(π) + Gumbel(0,1))

# 3. Sample from Gaussian k
z = randn()
log_sample = mu[k] + sigma[k] * z

# 4. Convert from log-microseconds to seconds
service_time = exp(log_sample) / 1e6
```

## Why MDN instead of LSTM?

| | LSTM | MDN |
|---|-----|-----|
| **Output** | Sequence of values | Parametric distribution |
| **Training** | Seq2seq | Supervised regression |
| **Problems** | Hard to train, unstable | Stable, probabilistic |
| **Export** | weights + architecture | Only weights (π,μ,σ explicit) |

MDN is more stable and directly produces distribution parameters, useful for the simulator where we sample service times probabilistically.

## Files

- `<service>_mdn.pt` - Trained PyTorch model
- `<service>_scaler.pkl` - Scaler parameters (normalization)
- `<service>_config.json` - Model configuration
- `<service>_mdn_scripted.pt` - TorchScript export (for torch-rb - not working)
- `<service>_weights.json` - JSON weights export (for torch-rb)

## Usage

### Train models

```bash
python mdn_service_time_predictor.py --mode train
```

### Generate service times

```bash
python mdn_service_time_predictor.py --mode generate --rps 50 --service productpage --n 1000
```

### Evaluate model

```bash
python mdn_service_time_predictor.py --mode evaluate --service productpage
```

### Export for torch-rb (JSON)

```bash
python mdn_service_time_predictor.py --mode export-json
```

This creates `<service>_weights.json` files that can be loaded by Ruby.

## Ruby Integration

```ruby
require 'kube_twin/mdn'

model = KUBETWIN::MDN.new(
  weights_path: 'mdn_models/productpage_weights.json',
  scaler_path: 'mdn_models/productpage_weights.json'
)

# Sample service time for given RPS
service_time = model.forward(50)  # => 0.027 seconds (27ms)
```

The Ruby implementation (`lib/kube_twin/mdn.rb`) replicates the PyTorch forward pass using torch-rb tensor operations.