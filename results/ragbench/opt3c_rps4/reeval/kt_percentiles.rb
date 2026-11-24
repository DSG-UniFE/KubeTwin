# KubeTwin latency statistics for the allocations of an allocation file, N seeds.
# usage: kt_percentiles.rb CONF ALLOCATIONS_JSON N_RUNS OUT_CSV
require 'kube_twin'
require 'json'
require 'csv'
conf_file, alloc_file, runs, out = ARGV
opt = KUBETWIN::KOptimizerMultiobjective.new(conf_file, runs: runs.to_i, seed: 1000)
conf = opt.instance_variable_get(:@sim_conf)
clusters = JSON.parse(conf.federation, symbolize_names: true)[:resources].keys.map(&:to_s)
rss0 = opt.instance_variable_get(:@rss)
keys = %i[mean_ttr p50_ttr p90_ttr p95_ttr p99_ttr]
CSV.open(out, 'w') do |csv|
  csv << ['solution_id', 'seed', *keys.map { |k| "#{k.to_s.sub('_ttr', '')}_ms" }]
  JSON.parse(File.read(alloc_file)).each do |s|
    alloc = s['microservice_allocation']
    counts = []; mapping = []
    rss0.each_key do |k|
      per = clusters.map { |c| alloc[conf.replica_sets[k][:selector].to_s][c].to_i }
      counts << per.sum
      per.each_with_index { |n, ci| n.times { mapping << ci } }
    end
    rss, = opt.encode_replicas_set(counts)
    runs.to_i.times do |i|
      sim = KUBETWIN::KSimulation.new(configuration: conf, evaluator: KUBETWIN::Evaluator.new(conf), random_seed: 1000 + i)
      r = sim.evaluate_allocation_multiobjective(rss, nil, nil, nil, nil, mapping)
      csv << [s['solution_id'], 1000 + i, *keys.map { |k| (r[k] * 1000).round(1) }]
      csv.flush
    end
  end
end
