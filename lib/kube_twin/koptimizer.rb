#!/usr/bin/env ruby

require 'mhl'
require_relative './configuration'
require_relative './ksimulation'

module KUBETWIN
    class KOptimizer
        def do_abort(message)
            abort <<-EOS.gsub(/^\s+\|/, '')
            |#{message}
            |
            |Usage:
            |    #{File.basename(__FILE__)} simulator_config_file 
            |
            EOS
        end
        
        
        if File.expand_path(__FILE__) == File.expand_path($0)
            # make sure both required arguments were given
            case ARGV.size
            when 0 then
            do_abort("Missing simulator configuration files!")
            end
        
            # make sure simulator config file exists
            unless File.exist? ARGV[0]
            do_abort("Invalid simulator configuration file!")
            end
        end

        def initialize(configuration_file)
            # here run the optimizer on the oracle
            # load simulation configuration
            time = Time.now.strftime('%Y%m%d%H%M%S')
            ga_log = "KT_optimizer_log_#{time}.log"
            File.delete(ga_log) if File.exist?(ga_log)
            @ga_logger = Logger.new(ga_log)
            @ga_logger.level = Logger::INFO

            @sim_conf = KUBETWIN::Configuration.load_from_file(configuration_file)

            @n_ms = @sim_conf.microservice_types.length
            @rss = @sim_conf.replica_sets
            @msc = @sim_conf.microservice_types
            @cluster_repository = KUBETWIN::KSimulation.create_cluster_configuration(@sim_conf)
            @n_clusters = @cluster_repository.length
            @start_time = @sim_conf.start_time
        end

        def encode_replicas_set(x, n_ms, rss)
            ra = rss.keys.to_a
            replicas_per_ms = {}
            (0..(n_ms - 1)).each do |sj|
                rss[ra[sj]][:replicas] = x[sj]
                replicas_per_ms[ra[sj]] = x[sj]
            end  
            # here decide the load balancing configuration
            # 0 would be round robin 1 is random
            #$logger.debug "Replica Sets: #{rss}"
            return rss, replicas_per_ms
        end

        def optimize(num_iterations: 5, population_size: 32)

            to_optimize = lambda do |component_allocation|
                # load simulation configuration
                #conf = KUBETWIN::Configuration.load_from_file(ARGV[0])
                rss = @sim_conf.replica_sets
                rss, _ = encode_replicas_set(component_allocation, @n_ms, rss)
                # Let's map the replicas to the clusters
                # 0 means cluster 0, 1 means cluster 1, etc., n_clusters means random
                mapping = component_allocation[@n_ms..(@n_ms + @n_clusters - 1)]
                sim = KUBETWIN::KSimulation.new(configuration: @sim_conf,
                                            evaluator: KUBETWIN::Evaluator.new(@sim_conf))

                @ga_logger.debug component_allocation
                res = sim.evaluate_allocation(rss, nil, nil, nil, mapping)
                res
            end
            solver_conf = {
            population_size: population_size || 32,
            genotype_space_type: :integer,
            mutation_probability: 0.5,
            recombination_probability: 0.5,
            logger: @ga_logger,
            log_level: "INFO",
            recombination_threshold: 0.40,
            genotype_space_conf: {
                dimensions: @n_ms * 2,
                recombination_type: :intermediate,
                random_func: lambda { Array.new(@n_ms) { rand(1..10) } + Array.new(@n_ms) {rand(0..@n_clusters)}},
                constraints: 
                    Array.new(@n_ms) {{from: 1, to: 10}} + Array.new(@n_ms) {{from: 0, to: @n_clusters}},
            },
            exit_condition: lambda { |iteration, _| iteration > num_iterations }
            }

            solver = MHL::GeneticAlgorithmSolver.new(solver_conf)

            # run the solver
            best = solver.solve(to_optimize, {concurrent: false})

            puts best
            puts "Best configuration"

            to_optimize.call(best[:genotype])
        end
    end
end # module KUBETWIN