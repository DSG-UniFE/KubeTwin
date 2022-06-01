#!/usr/bin/env ruby

LIBDIR = File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib'))
$:.unshift(LIBDIR) unless $:.include?(LIBDIR)

require 'csv'
require 'mhl'
require 'phileas'

def do_abort(message)
    $stderr.puts message
    abort
  end

def encode_service_activation(x, start_time)
sas = Hash.new
n_sc = x.length
  (1..n_sc).each do |si|
    #sas[si] = { type_id: si, at: { time: Time.now, device_id: (x[(si - 1)] + 1) } }
    sas[si] = { type_id: si, at: { time: start_time, device_id: (x[(si - 1)] + 1) } }
  end
  sas
end


if File.expand_path(__FILE__) == File.expand_path($0)
    # make sure the input file exists
    do_abort('No input file given') unless ARGV.size >= 2
    do_abort("File #{ARGV[0]} does not exist!") unless File.exists?(ARGV[0])
    do_abort("File #{ARGV[1]} does not exist!") unless File.exists?(ARGV[1])
end

puts "Processing approx_data"

position_data = CSV.read(ARGV[0])
previous_allocation = []
previous_voi = 0
if ARGV[2] == "GA"
  benchmark = File.open("../simulation_results/ga_approx_voi.csv", 'w')
else
 benchmark = File.open("../simulation_results/pso_approx_voi.csv", 'w')
end
benchmark << "Generation,Value\n"

# check here, sim_conf is already defined 

# init some parameters here
sim_conf = Phileas::Configuration.load_from_file(ARGV[1])
n_devices = sim_conf.devices.length
n_sc = sim_conf.service_types.length
start_time = sim_conf.start_time


# keep track of this data in memory also
# it could not be feasible
position_voi = []
position_data.each do |iter|
  puts "iter #{iter}"
  iter_discretized = iter.map(&:to_i)
  gen = iter_discretized[0]
  allocation = iter_discretized[1..iter_discretized.length]
  if allocation == previous_allocation
    benchmark << "#{gen},#{previous_voi}\n"
    next
  end
  sim_conf = Phileas::Configuration.load_from_file(ARGV[1])
  sim = Phileas::Simulator.new(configuration: sim_conf)
  service_activations = encode_service_activation( allocation, start_time)
  #puts "evaluating VoI for #{service_activations}"
  begin
    total_voi = sim.run service_activations
  rescue
    puts "Skipping iteration"
    next
  end
  previous_allocation = allocation
  previous_voi = total_voi
  benchmark << "#{gen},#{total_voi}\n"
  position_voi << { allocation: allocation, voi: total_voi}
end

benchmark.close


puts "Figures generated #{position_voi}"

# find the best VoI allocation
# 0 element of array

best_allocation = position_voi.sort_by!{ |e| -e[:voi] }[0]

puts "Best allocation found is #{best_allocation}"

`Rscript --vanilla generate_pso_voi.r #{File.expand_path(benchmark)}`


# start mix and match here from this solution

# here run the optimizer on the oracle
# load simulation configuration

$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO
time = Time.now.strftime('%Y%m%d%H%M%S')

if ARGV[2] == "GA"
  
  puts "It does not work quite well"
  allocation_conf = best_allocation[:allocation].map(&:to_i)
  GA_LOG = "../simulation_results/ga_log_mix_#{time}.log"

  File.delete(GA_LOG) if File.exist?(GA_LOG)
  ga_logger = Logger.new(GA_LOG)
  ga_logger.level = Logger::INFO
  # here --- need to specify starting position
  # and the other parameters as for the PSO models
  # let's try again
  sim_conf = Phileas::Configuration.load_from_file(ARGV[1])
  n_devices = sim_conf.devices.length
  n_sc = sim_conf.service_types.length

  puts "Allocation conf #{allocation_conf}"
  population = []
  #127.times { population << Array.new(allocation_conf.length) {0} }

  127.times do 
    population << Array.new(allocation_conf.length) {
      |e| (allocation_conf[e] * SecureRandom.random_number).to_i
    }
  end

  population << allocation_conf

  solver_conf = {
    population_size: 128,
    genotype_space_type: :integer,
    mutation_probability: 0.5,
    recombination_probability: 0.5,
    logger: ga_logger,
    log_level: "INFO",
    recombination_threshold: 0.40,
    genotype_space_conf: {
        dimensions: n_sc,
        start_population: population,
        recombination_type: :intermediate,
        #random_func: lambda { Array.new(n_sc) { rand(0..(n_devices - 1)) } },
        constraints: [
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
          {from: 0, to: (n_devices - 1)},
        ]
    },
    exit_condition: lambda { |iteration, _| iteration > 15.0 }
  }

  to_optimize = lambda do |component_allocation|
    puts "Component allocation #{component_allocation}"
    service_activations = encode_service_activation( component_allocation, start_time)
    sim_conf = Phileas::Configuration.load_from_file(ARGV[1])
    sim_conf.freeze
    sim = Phileas::Simulator.new(configuration: sim_conf)
    total_voi = sim.run service_activations
    puts "Total voi: #{total_voi}"
    total_voi
  end

  # run the solver here
  solver = MHL::GeneticAlgorithmSolver.new(solver_conf)
  best = solver.solve(to_optimize, {concurrent: true})

else

PSO_LOG = "../simulation_results/pso_log_mix_#{time}.log"
File.delete(PSO_LOG) if File.exist?(PSO_LOG)
pso_mix_logger = Logger.new(PSO_LOG)
pso_mix_logger.level = Logger::INFO

pso_mix_logger.info "Len #{position_voi.length}"
pso_mix_logger.info "Best allocation found is #{best_allocation[:allocation]}"

# check here, sim_conf is already defined 
sim_conf = Phileas::Configuration.load_from_file(ARGV[1])
n_devices = sim_conf.devices.length
n_sc = sim_conf.service_types.length
start_time = sim_conf.start_time


to_optimize = lambda do |component_allocation|
  # log component allocation here
  puts component_allocation
  service_activations = encode_service_activation(component_allocation, start_time)
  sim_conf = Phileas::Configuration.load_from_file(ARGV[1])
  sim = Phileas::Simulator.new(configuration: sim_conf)
  total_voi = sim.run service_activations
  total_voi
end

$logger.info "n_devices #{n_devices}"

# I cannot use the allocation array as a starting position
# I need the entire swarm here
# let's try to do some rocket science

swarm_array = []

# this works quite well as mix and match
# on the other hand, I would like to assign different values to 
# the other particles in the swarm

# floatize the particle's components
allocation_conf = best_allocation[:allocation].map(&:to_f)

# let's generate 39 random particles starting from the one
# that generated the best allocation within the approx model

39.times do 
  swarm_array << Array.new(allocation_conf.length) {
    |e| allocation_conf[e] * SecureRandom.random_number
  }
end


#39.times {swarm_array << Array.new(best_allocation[:allocation].length) {0}}
swarm_array << best_allocation[:allocation].map(&:to_f)


solver_conf = {
  swarm_size: 40,
  start_positions: swarm_array,
  constraints: {
    min: [ 0 ] * n_sc,
    max: [ (n_devices -1) ] * n_sc,
  },
  exit_condition: lambda {|gen, best| gen >= 15 },
  logger: pso_mix_logger,
  log_level: :info,
}

solver = MHL::QuantumPSOSolver.new(solver_conf)

# run the solver
best = solver.solve(to_optimize, {concurrent: true})

#`tail -f #{PSO_LOG}`
# it does not print the best here
#puts best

end # ending if
