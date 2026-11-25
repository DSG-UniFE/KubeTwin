#!/bin/zsh
# NSGA-II on ragbench_3c_2rtt.conf (2 RTT per call, cluster1 6.5 cores), 4 RPS
cd "$(dirname "$0")"
export RBENV_VERSION=3.3.9 BUNDLE_GEMFILE=$HOME/code/KubeTwin/Gemfile RAGBENCH_RPS=4
date
bundle exec ruby -I $HOME/code/KubeTwin/lib $HOME/code/KubeTwin/bin/optimizer_optimuum \
  $HOME/code/KubeTwin/examples/ragbench_3c_2rtt.conf --generations 30 --population 60 --seed 12345 > opt_g30_p60.log 2>&1
echo "exit $?"
date
