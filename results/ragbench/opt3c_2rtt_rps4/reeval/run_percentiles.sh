#!/bin/zsh
cd "$(dirname "$0")/.."
export RBENV_VERSION=3.3.9 BUNDLE_GEMFILE=$HOME/code/KubeTwin/Gemfile RAGBENCH_RPS=4
bundle exec ruby -I $HOME/code/KubeTwin/lib $HOME/code/KubeTwin/results/ragbench/opt3c_rps4/reeval/kt_percentiles.rb \
  $HOME/code/KubeTwin/examples/ragbench_3c_2rtt.conf allocations_bologna_2rtt_rps4.json 10 reeval/kt_percentiles_candidates.csv > reeval/kt_percentiles.log 2>&1
echo "exit $?"
