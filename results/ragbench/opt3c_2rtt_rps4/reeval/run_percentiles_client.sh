#!/bin/zsh
# candidates with the client-side TTR: k6 next to cluster1 (client) and on Elisa's laptop (laptop)
cd "$(dirname "$0")/.."
export RBENV_VERSION=3.3.9 BUNDLE_GEMFILE=$HOME/code/KubeTwin/Gemfile RAGBENCH_RPS=4
for v in client laptop; do
  bundle exec ruby -I $HOME/code/KubeTwin/lib $HOME/code/KubeTwin/results/ragbench/opt3c_rps4/reeval/kt_percentiles.rb \
    $HOME/code/KubeTwin/examples/ragbench_3c_2rtt_$v.conf allocations_bologna_2rtt_rps4.json 10 \
    reeval/kt_percentiles_candidates_$v.csv > reeval/kt_percentiles_$v.log 2>&1
done
echo "exit $?"
