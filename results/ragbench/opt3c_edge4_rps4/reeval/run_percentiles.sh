#!/bin/zsh
# p50-p99 of the candidates (seeds 1000-1009), client-side TTR, k6 next to cluster1
cd "$(dirname "$0")/.."
export RBENV_VERSION=3.3.9 BUNDLE_GEMFILE=$HOME/code/KubeTwin/Gemfile RAGBENCH_RPS=4
bundle exec ruby -I $HOME/code/KubeTwin/lib $HOME/code/KubeTwin/results/ragbench/opt3c_rps4/reeval/kt_percentiles.rb \
  $HOME/code/KubeTwin/examples/ragbench_3c_2rtt_client_edge4.conf allocations_bologna_edge4_rps4.json 10 \
  reeval/kt_percentiles_candidates.csv > reeval/kt_percentiles.log 2>&1
echo "exit $?"
