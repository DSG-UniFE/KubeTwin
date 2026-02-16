# KubeTwin Benchmarking Scripts

This directory contains scripts for running automated benchmarks of KubeTwin configurations with different request rates.

## Scripts

### `benchmark_rates`
Automated benchmark script that runs simulations with varying request rates and collects performance metrics.

#### Usage:
```bash
bin/benchmark_rates [options] config_file
```

#### Options:
- `-s, --start RATE`: Starting rate (default: 25)
- `-e, --end RATE`: Ending rate (default: 400)  
- `-t, --step STEP`: Rate step (default: 25)
- `-o, --output FILE`: Output CSV file (default: benchmark_TIMESTAMP.csv)
- `-v, --verbose`: Verbose output
- `-h, --help`: Show help

#### Examples:
```bash
# Basic usage - benchmark from 25 to 400 RPS with 25 step
bin/benchmark_rates examples/bookinfo-revised-extension.conf

# Custom range and output
bin/benchmark_rates -s 50 -e 200 -t 25 -o my_benchmark.csv examples/bookinfo-revised-extension.conf

# Verbose output for debugging
bin/benchmark_rates -v examples/bookinfo-revised-extension.conf
```

#### Output:
- CSV file with performance metrics for each rate
- Console summary with performance analysis
- Columns: Rate, TTR Mean, QTIME Mean, Requests Received/Closed, Completion Rate, Simulation Time, Exit Status

### `analyze_benchmark`
Analysis script for benchmark results that provides performance insights and optionally generates plotting scripts.

#### Usage:
```bash
bin/analyze_benchmark [options] csv_file
```

#### Options:
- `-p, --plot`: Generate Python plot script
- `-h, --help`: Show help

#### Examples:
```bash
# Basic analysis
bin/analyze_benchmark benchmark_20260209_095023.csv

# Generate analysis with plotting script
bin/analyze_benchmark -p benchmark_20260209_095023.csv
```

#### Output:
- Performance analysis with saturation points
- System efficiency metrics  
- Recommendations for optimal operation
- Python plotting script (with -p option)

## Workflow Example

1. **Run benchmark:**
   ```bash
   bin/benchmark_rates examples/bookinfo-revised-extension.conf
   ```

2. **Analyze results:**
   ```bash
   bin/analyze_benchmark -p benchmark_20260209_095023.csv
   ```

3. **Generate plots (if Python/matplotlib available):**
   ```bash
   python benchmark_20260209_095023_plot.py
   ```

## Configuration Requirements

The benchmark script modifies the `request_distribution` parameter in your configuration file. Ensure your config has:

```ruby
request_gen \
1 => {
    workflow_types: 1,
    starting_time: start_time,
    request_distribution: {distribution: :exponential, args: { rate: 200, seed: seed }},
    # ... other parameters
}
```

The script will automatically substitute different rate values during benchmarking.

## Understanding Results

### Key Metrics:
- **TTR (Time To Response)**: Total response time including queueing and processing
- **QTIME**: Queue waiting time only  
- **Completion Rate**: Percentage of requests that completed successfully
- **Throughput**: Actual requests processed per second

### Performance Regions:
- **Linear Region**: Where TTR increases slowly with rate
- **Saturation Point**: Where TTR starts increasing rapidly (>50% increase)
- **Degradation**: Performance drop compared to baseline

### Sample Results Interpretation:
```
Linear performance region: 25-125 RPS     # Stable performance
Saturation point: 275 RPS                 # Performance cliff
Best performance: 50 RPS (TTR: 0.0254s)   # Optimal operating point
```

## Troubleshooting

### Common Issues:

1. **"Configuration file not found"**
   - Ensure the config file path is correct
   - Use absolute paths if needed

2. **"Simulation failed with exit status 1"** 
   - Check config file syntax
   - Run manually once to verify: `bundle exec bin/kube_twin your_config.conf`

3. **"Could not parse simulation output"**
   - Verbose mode (`-v`) shows detailed output for debugging
   - Check if TTR/QTIME metrics are in simulation output

### Performance Tips:

- Use smaller ranges for initial testing: `-s 25 -e 100 -t 25`
- Higher rates take longer to simulate
- Consider duration settings in your config for faster benchmarks
- Use verbose mode only for debugging (creates more output)