#!/bin/zsh
# 10-seed re-evaluation of the edge-4-core front (seeds 1000-1009)
cd "$(dirname "$0")/.."
export RBENV_VERSION=3.3.9 BUNDLE_GEMFILE=$HOME/code/KubeTwin/Gemfile RAGBENCH_RPS=4
bundle exec ruby -I $HOME/code/KubeTwin/lib $HOME/code/KubeTwin/results/ragbench/opt3c_rps4/reeval/reeval.rb \
  $HOME/code/KubeTwin/examples/ragbench_3c_2rtt_client_edge4.conf $(ls final_allocation_multi_objective_*.json | tail -1) 10 reeval/reeval_10seeds.csv > reeval/reeval.log 2>&1
echo "exit $?"
