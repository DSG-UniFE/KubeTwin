# frozen_string_literal: true

require 'mhl'
require 'logger'
require 'csv'
require 'json'

module KUBETWIN
	class KOptimizerMultiobjective
		MAX_REPLICAS = 10

		def initialize(configuration_file)
			time = Time.now.strftime('%Y%m%d%H%M%S')
			ga_log = "KT_optimizer_moo_log_#{time}.log"

			@logger = Logger.new($stdout)
			@logger.level = Logger::INFO

			File.delete(ga_log) if File.exist?(ga_log)
			@ga_logger = Logger.new(ga_log)
			@ga_logger.level = Logger::INFO

			@sim_conf = KUBETWIN::Configuration.load_from_file(configuration_file)

			@n_ms = @sim_conf.microservice_types.length
			@rss = @sim_conf.replica_sets
			@cluster_repository = KUBETWIN::KSimulation.create_cluster_configuration(@sim_conf)
			@n_clusters = @cluster_repository.length
			@max_replicas = MAX_REPLICAS
		end

		# Encode the first n_ms elements of x as replica counts into replica sets.
		# Returns [updated_rss, replicas_per_ms_hash].
		def encode_replicas_set(x)
			rss = @rss.each_with_object({}) { |(k, v), h| h[k] = v.dup }
			ra = rss.keys.to_a
			replicas_per_ms = {}

			(0..(@n_ms - 1)).each do |sj|
				rss[ra[sj]][:replicas] = x[sj]
				replicas_per_ms[ra[sj]] = x[sj]
			end

			[rss, replicas_per_ms]
		end

		# Decode the cluster assignment section into a flat replicas mapping.
		def decode_cluster_mapping(vector)
			replica_counts = vector[0...@n_ms]
			cluster_section = vector[@n_ms..]
			replicas_mapping = []

			(0...@n_ms).each do |ms_idx|
				n_reps = replica_counts[ms_idx]
				block_start = ms_idx * @max_replicas
				n_reps.times do |r|
					replicas_mapping << cluster_section[block_start + r]
				end
			end

			replicas_mapping
		end

		def optimize(num_iterations: 10, population_size: 40)
			to_optimize = lambda do |component_allocation|
				component_allocation = component_allocation.map(&:to_i)

				new_rss, = encode_replicas_set(component_allocation[0...@n_ms])
				replicas_mapping = decode_cluster_mapping(component_allocation)

				sim = KUBETWIN::KSimulation.new(configuration: @sim_conf,
																				evaluator: KUBETWIN::Evaluator.new(@sim_conf))

				# Retrieve both objectives directly from simulation
				metrics = sim.evaluate_allocation_multiobjective(new_rss, nil, nil, nil, nil, replicas_mapping)

				# Return objectives: mean TTR, per-microservice spreading, and global cluster spreading (all minimized)
				#[metrics[:mean_ttr], metrics[:replica_spreading], metrics[:global_cluster_spreading]]
				[metrics[:mean_ttr], metrics[:overall_spreading]]
			end

			# Fixed-size vector: n_ms replica counts + n_ms * MAX_REPLICAS cluster assignments
			solver_conf = {
				population_size: population_size || 40,
				num_objectives: 2,
				constraints: {
					min: [@n_clusters] * @n_ms + [0] * (@n_ms * @max_replicas),
					max: [@max_replicas] * @n_ms + [@n_clusters] * (@n_ms * @max_replicas)
				},
				logger: @ga_logger,
				log_level: :info,
				exit_condition: ->(iteration, _) { iteration > num_iterations }
			}

			solver = MHL::NSGA2Solver.new(solver_conf)
			pareto_front = solver.solve(to_optimize, { concurrent: false })
			csv_path = export_pareto_front_csv(pareto_front)
			csv_path_json = export_pareto_solution_allocations_json(pareto_front)

			@logger.info("NSGA-II completed with Pareto front size: #{pareto_front.size}")
			@logger.info("Pareto front exported to #{csv_path}")
			pareto_front
		end

		private

		def export_pareto_front_csv(pareto_front)
			timestamp = Time.now.strftime('%Y%m%d%H%M%S')
			file_path = "pareto_front_#{timestamp}.csv"

			max_variables = pareto_front.map { |entry| entry[:variables].length }.max || 0
			headers = ['solution_id', 'mean_ttr', 'overall_spreading']
			headers += (0...max_variables).map { |i| "var_#{i}" }

			CSV.open(file_path, 'w') do |csv|
				csv << headers
				pareto_front.each_with_index do |entry, index|
					objectives = entry[:objectives] || []
					variables = entry[:variables] || []
					row = [index, objectives[0], objectives[1]]
					row += variables
					row += [nil] * (max_variables - variables.length)
					csv << row
				end
			end

			file_path
		end

		def export_pareto_solution_allocations_json(pareto_front)
        	timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        	file_path = "final_allocation_multi_objective_#{timestamp}.json"

        	allocations = pareto_front.each_with_index.map do |entry, index|
            	component_allocation = (entry[:variables] || []).map(&:to_i)

            	new_rss, = encode_replicas_set(component_allocation[0...@n_ms])
            	replicas_mapping = decode_cluster_mapping(component_allocation)

            	sim = KUBETWIN::KSimulation.new(
                	configuration: @sim_conf,
                	evaluator: KUBETWIN::Evaluator.new(@sim_conf)
           	 	)

            	metrics = sim.evaluate_allocation_multiobjective(
                	new_rss, nil, nil, nil, nil, replicas_mapping
            	)

            	{
                	solution_id: index,
                	objectives: {
                    	mean_ttr: (entry[:objectives] || [])[0],
	                    #replica_spreading: (entry[:objectives] || [])[1],
	                    #global_cluster_spreading: (entry[:objectives] || [])[2]
						overall_spreading: (entry[:objectives] || [])[1]
                	},
                	microservice_allocation: metrics[:bmap]
            	}
        	end

        	File.open(file_path, 'w') do |f|
            	f.write(JSON.pretty_generate(allocations))
        	end

        	file_path
    	end
	end
end
