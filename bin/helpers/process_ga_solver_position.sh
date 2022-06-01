#!/usr/bin/env bash
cd bin/helpers
echo "Generation,Position" > ../../ga_position_approx.txt
grep position_at $1 | cut -d ' ' -f 10,11- | sed 's/\[//' | sed 's/\]//'> ../../ga_position_approx.txt

#ruby process_approx_data.rb ../../ga_position_approx.txt ../example/noms_scenario_seed.conf "GA"
