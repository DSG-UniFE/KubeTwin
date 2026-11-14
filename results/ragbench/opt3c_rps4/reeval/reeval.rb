# Re-evaluates every distinct allocation of a Pareto-front JSON with N seeds.
# usage: reeval.rb CONF FRONT_JSON N_RUNS OUT_CSV
require 'kube_twin'
require 'json'
require 'csv'
conf_file, front, runs, out = ARGV
opt = KUBETWIN::KOptimizerMultiobjective.new(conf_file, runs: runs.to_i, seed: 1000)
conf = opt.instance_variable_get(:@sim_conf)
clusters = JSON.parse(conf.federation, symbolize_names: true)[:resources].keys.map(&:to_s)
rss0 = opt.instance_variable_get(:@rss)
sols = JSON.parse(File.read(front)).uniq { |s| s['microservice_allocation'] }
# plus a reference: three replicas per service, all on cluster1
ref = { 'solution_id' => 'all_c1_x3', 'objectives' => {},
        'microservice_allocation' => rss0.keys.to_h { |k| [conf.replica_sets[k][:selector].to_s, { 'cluster1' => 3, 'cluster2edge' => 0, 'cluster3edge' => 0 }] } }
CSV.open(out, 'w') do |csv|
  csv << %w[solution_id opt_ttr_ms reeval_ttr_ms reeval_sd_ms spreading total_replicas alloc]
  (sols + [ref]).each do |s|
    alloc = s['microservice_allocation']
    counts = []; mapping = []
    rss0.each_key do |k|
      a = alloc[conf.replica_sets[k][:selector].to_s]
      per = clusters.map { |c| a[c].to_i }
      counts << per.sum
      per.each_with_index { |n, ci| n.times { mapping << ci } }
    end
    rss, = opt.encode_replicas_set(counts)
    ttrs = (0...runs.to_i).map do |i|
      sim = KUBETWIN::KSimulation.new(configuration: conf, evaluator: KUBETWIN::Evaluator.new(conf), random_seed: 1000 + i)
      sim.evaluate_allocation_multiobjective(rss, nil, nil, nil, nil, mapping)
    end
    m = ttrs.map { |x| x[:mean_ttr] }
    mean = m.sum / m.size
    sd = Math.sqrt(m.sum { |v| (v - mean)**2 } / [m.size - 1, 1].max)
    csv << [s['solution_id'], s.dig('objectives', 'mean_ttr')&.*(1000)&.round(1), (mean * 1000).round(1), (sd * 1000).round(1),
            ttrs.first[:overall_spreading].round(3), counts.sum, alloc.map { |k, v| "#{k}:#{clusters.map { |c| v[c] }.join('/')}" }.join(' ')]
    csv.flush
  end
end
