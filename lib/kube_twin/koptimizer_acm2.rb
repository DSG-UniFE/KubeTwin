#!/usr/bin/env ruby

require 'mhl'
require_relative './configuration'
require_relative './ksimulation'
require 'logger'

module KUBETWIN
  class KOptimizerACM2
    MAX_REPLICAS = 10

    def do_abort(message)
      abort <<-EOS.gsub(/^\s+\|/, '')
            |#{message}
            |
            |Usage:
            |    #{File.basename(__FILE__)} simulator_config_file#{' '}
            |
      EOS
    end

    if File.expand_path(__FILE__) == File.expand_path($0)
      # make sure both required arguments were given
      case ARGV.size
      when 0
        do_abort('Missing simulator configuration files!')
      end

      # make sure simulator config file exists
      do_abort('Invalid simulator configuration file!') unless File.exist? ARGV[0]
    end

    def initialize(configuration_file)
      # here run the optimizer on the oracle
      # load simulation configuration
      time = Time.now.strftime('%Y%m%d%H%M%S')
      ga_log = "KT_optimizer_log_#{time}.log"
      @logger = Logger.new($stdout)
      @logger.level = Logger::DEBUG
      File.delete(ga_log) if File.exist?(ga_log)
      @ga_logger = Logger.new(ga_log)
      @ga_logger.level = Logger::INFO

      @sim_conf = KUBETWIN::Configuration.load_from_file(configuration_file)

      @n_ms = @sim_conf.microservice_types.length
      @rss = @sim_conf.replica_sets
      @msc = @sim_conf.microservice_types
      @cluster_repository = KUBETWIN::KSimulation.create_cluster_configuration(@sim_conf)
      @n_clusters = @cluster_repository.length
      @max_replicas = MAX_REPLICAS
      # Read environment variables RPS, set default to 10 if not set
      rps = ENV['RPS'] ? ENV['RPS'].to_i : 10
      @logger.info "Setting RPS to #{rps}"

      @start_time = @sim_conf.start_time
    end

    # Encode the first n_ms elements of x as replica counts into the replica sets hash.
    # Returns [updated_rss, replicas_per_ms_hash].
    def encode_replicas_set(x)
      # Deep copy: @rss values are hashes that must not be mutated
      rss = @rss.each_with_object({}) { |(k, v), h| h[k] = v.dup }
      ra = rss.keys.to_a
      replicas_per_ms = {}
      (0..(@n_ms - 1)).each do |sj|
        rss[ra[sj]][:replicas] = x[sj]
        replicas_per_ms[ra[sj]] = x[sj]
      end
      [rss, replicas_per_ms]
    end

    # Decode the cluster assignment portion of the vector into a flat replicas_mapping
    # array indexed by global pod_id.
    #
    # The vector layout is:
    #   [rep_ms0, rep_ms1, ..., rep_msN,          # @n_ms values (1..MAX_REPLICAS)
    #    c_ms0_r0, c_ms0_r1, ..., c_ms0_r(MAX-1), # MAX_REPLICAS values per MS
    #    c_ms1_r0, c_ms1_r1, ..., c_ms1_r(MAX-1),
    #    ...]
    #
    # For each microservice i with replica_count[i] replicas, we only take
    # the first replica_count[i] cluster assignments from its block of MAX_REPLICAS,
    # and ignore the rest (padding).
    #
    # Returns a flat array where index = global pod_id, value = cluster_id.
    def decode_cluster_mapping(vector)
      replica_counts = vector[0...@n_ms]
      cluster_section = vector[@n_ms..]
      replicas_mapping = []

      (0...@n_ms).each do |ms_idx|
        n_reps = replica_counts[ms_idx]
        # Each MS has a block of @max_replicas entries in the cluster section
        block_start = ms_idx * @max_replicas
        n_reps.times do |r|
          replicas_mapping << cluster_section[block_start + r]
        end
      end

      replicas_mapping
    end

    def optimize(num_iterations: 5, population_size: 40)
      to_optimize = lambda do |component_allocation|
        component_allocation = component_allocation.map(&:to_i)
        puts component_allocation.inspect

        # Decode replica counts and update replica sets
        new_rss, = encode_replicas_set(component_allocation[0...@n_ms])

        # Decode the flat replicas_mapping (only uses active replicas, ignores padding)
        replicas_mapping = decode_cluster_mapping(component_allocation)

        sim = KUBETWIN::KSimulation.new(configuration: @sim_conf,
                                        evaluator: KUBETWIN::Evaluator.new(@sim_conf))
        @ga_logger.debug component_allocation
        res = sim.evaluate_allocation(new_rss, nil, nil, nil, nil, replicas_mapping)
        res
      end

      # Fixed-size vector: n_ms replica counts + n_ms * MAX_REPLICAS cluster assignments
      # Padding positions (beyond actual replica count) are ignored during decoding.
      solver_conf = {
        swarm_size: population_size || 40,
        constraints: {
          min: [1] * @n_ms + [0] * (@n_ms * @max_replicas),
          max: [@max_replicas] * @n_ms + [@n_clusters] * (@n_ms * @max_replicas)
        },
        logger: @ga_logger,
        log_level: :info,
        exit_condition: ->(iteration, _) { iteration > num_iterations }
      }

      solver = MHL::QuantumPSOSolver.new(solver_conf)

      # run the solver
      best = solver.solve(to_optimize, { concurrent: false })

      puts best
      puts 'Best configuration'

      to_optimize.call(best[:position])
    end
  end
end # module KUBETWIN
