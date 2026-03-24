#!/usr/bin/env ruby

require 'mhl'
require 'rumale/ensemble/random_forest_regressor'
require 'numo/narray'
require_relative './configuration'
require_relative './ksimulation'
require 'logger'

module KUBETWIN
  # Surrogate-assisted variant of KOptimizerACM2.
  #
  # Instead of running the (expensive) simulator for every PSO evaluation,
  # this optimizer:
  #   1. Samples N initial points with the real simulator to build a dataset.
  #   2. Trains a RandomForest surrogate model on {vector -> fitness}.
  #   3. Runs PSO against the surrogate (thousands of cheap evaluations).
  #   4. Validates the top-K candidates with the real simulator.
  #   5. Returns the best validated solution.
  class KOptimizerACM2Surrogate
    MAX_REPLICAS = 10

    def initialize(configuration_file)
      time = Time.now.strftime('%Y%m%d%H%M%S')
      ga_log = "KT_surrogate_optimizer_log_#{time}.log"
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

      # Total dimensionality of the search vector
      @n_dims = @n_ms + @n_ms * @max_replicas

      # Constraint bounds (fixed-size vector)
      @constraints = {
        min: [1] * @n_ms + [0] * (@n_ms * @max_replicas),
        max: [@max_replicas] * @n_ms + [@n_clusters] * (@n_ms * @max_replicas)
      }

      # Dedicated RNG for sampling — immune to srand() calls inside the simulator
      @sampling_rng = Random.new

      rps = ENV['RPS'] ? ENV['RPS'].to_i : 10
      @logger.info "Setting RPS to #{rps}"
      @start_time = @sim_conf.start_time
    end

    # ─── Vector encoding / decoding (same as KOptimizerACM2) ───

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

    # ─── Real simulation evaluation ───

    # Run the actual (expensive) simulator for a single integer vector.
    # Returns the fitness value (negative weighted sum — higher is better).
    def evaluate_real(int_vector)
      new_rss, = encode_replicas_set(int_vector[0...@n_ms])
      replicas_mapping = decode_cluster_mapping(int_vector)

      sim = KUBETWIN::KSimulation.new(configuration: @sim_conf,
                                      evaluator: KUBETWIN::Evaluator.new(@sim_conf))
      sim.evaluate_allocation(new_rss, nil, nil, nil, nil, replicas_mapping)
    end

    # ─── Sampling ───

    # Generate n_samples random integer vectors within the constraints and
    # evaluate each with the real simulator.
    # Returns [X, y] where X is an array of vectors and y is an array of fitness values.
    def sample_initial_points(n_samples)
      mins = @constraints[:min]
      maxs = @constraints[:max]

      x_samples = []
      y_samples = []

      @logger.info "Surrogate: sampling #{n_samples} initial points with real simulator..."

      n_samples.times do |i|
        # Uniform random integer vector within bounds
        # NOTE: Must use @sampling_rng instead of Kernel.rand because
        # Service#initialize calls srand(SEED) which resets the global RNG,
        # causing all vectors after the first evaluation to be identical.
        vec = mins.zip(maxs).map { |lo, hi| @sampling_rng.rand(lo..hi) }
        fitness = evaluate_real(vec)

        x_samples << vec
        y_samples << fitness

        if (i + 1) % 20 == 0
          @logger.info "  Sampled #{i + 1}/#{n_samples} (last fitness: #{fitness.round(4)})"
        end
        @ga_logger.info "Sample #{i + 1}: fitness=#{fitness.round(4)} vector=#{vec.inspect}"
      end

      @logger.info "Surrogate: sampling complete. Fitness range: [#{y_samples.min.round(4)}, #{y_samples.max.round(4)}]"

      [x_samples, y_samples]
    end

    # ─── Surrogate model ───

    # Train a RandomForest regressor on the collected samples.
    # Returns the trained Rumale model.
    def train_surrogate(x_samples, y_samples)
      @logger.info "Surrogate: training RandomForest on #{x_samples.length} samples " \
                    "(#{@n_dims} features)..."

      # Convert to Numo arrays (Rumale's expected format)
      x_numo = Numo::DFloat.cast(x_samples)
      y_numo = Numo::DFloat.cast(y_samples)

      # max_features: sqrt(n_dims) — standard RF heuristic for regression
      n_max_features = Math.sqrt(@n_dims).ceil

      model = Rumale::Ensemble::RandomForestRegressor.new(
        n_estimators: 100,
        max_depth: nil,          # grow trees fully
        max_features: n_max_features,
        min_samples_leaf: 2,
        random_seed: 42
      )

      model.fit(x_numo, y_numo)

      # R² on training data (sanity check)
      y_pred = model.predict(x_numo)
      ss_res = ((y_numo - y_pred) ** 2).sum
      ss_tot = ((y_numo - y_numo.mean) ** 2).sum
      r2 = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0
      @logger.info "Surrogate: training R² = #{r2.round(4)}"
      @ga_logger.info "Surrogate model R² on training data: #{r2.round(4)}"

      model
    end

    # ─── PSO on surrogate ───

    # Run PSO using the surrogate model as the objective function.
    # This is very fast since model.predict is O(ms) instead of O(seconds).
    # Returns the best solution hash from MHL: { position: [...], height: ... }
    def run_pso_on_surrogate(model, num_iterations:, swarm_size:)
      @logger.info "Surrogate: running PSO (#{swarm_size} particles, #{num_iterations} iterations)..."

      surrogate_fn = lambda do |position|
        int_vec = position.map(&:to_i)
        # Rumale expects a 2D Numo array: 1 row x n_dims columns
        x = Numo::DFloat.cast([int_vec])
        model.predict(x)[0]
      end

      solver_conf = {
        swarm_size: swarm_size,
        constraints: @constraints,
        logger: @ga_logger,
        log_level: :info,
        exit_condition: ->(iteration, _) { iteration > num_iterations }
      }

      solver = MHL::QuantumPSOSolver.new(solver_conf)
      best = solver.solve(surrogate_fn, { concurrent: false })

      @logger.info "Surrogate PSO: best predicted fitness = #{best[:height].round(4)}"
      @ga_logger.info "Surrogate PSO best: fitness=#{best[:height].round(4)} " \
                      "position=#{best[:position].map(&:to_i).inspect}"

      best
    end

    # ─── Validation ───

    # Collect the top-K distinct candidate vectors from the PSO swarm and
    # re-evaluate them with the real simulator.
    # Returns { position: [...], fitness: ... } for the best validated candidate.
    def validate_candidates(candidates, top_k)
      @logger.info "Surrogate: validating top #{top_k} candidates with real simulator..."

      results = []
      candidates.first(top_k).each_with_index do |vec, i|
        int_vec = vec.map(&:to_i)
        fitness = evaluate_real(int_vec)
        results << { position: int_vec, fitness: fitness }
        @logger.info "  Candidate #{i + 1}/#{top_k}: real fitness = #{fitness.round(4)}"
        @ga_logger.info "Validation #{i + 1}: fitness=#{fitness.round(4)} vector=#{int_vec.inspect}"
      end

      best = results.max_by { |r| r[:fitness] }
      @logger.info "Surrogate: best validated fitness = #{best[:fitness].round(4)}"
      best
    end

    # ─── Main optimization entry point ───

    # Surrogate-assisted optimization flow:
    #   1. Sample n_initial_samples real evaluations
    #   2. Train a RandomForest surrogate
    #   3. Run PSO on the surrogate (cheap)
    #   4. Validate top_k candidates with the real simulator
    #   5. Return the best validated result
    #
    # Total real simulator calls: n_initial_samples + top_k
    # (vs. swarm_size * num_iterations for pure PSO)
    def optimize(n_initial_samples: 200, surrogate_iterations: 50,
                 surrogate_swarm_size: 100, top_k: 5)
      total_start = Time.now

      # Phase 1: Sample initial points
      x_samples, y_samples = sample_initial_points(n_initial_samples)

      # Phase 2: Train surrogate
      model = train_surrogate(x_samples, y_samples)

      # Phase 3: PSO on surrogate
      pso_result = run_pso_on_surrogate(model,
                                        num_iterations: surrogate_iterations,
                                        swarm_size: surrogate_swarm_size)

      # Collect diverse candidate vectors from the PSO result.
      # We take the PSO best, plus generate nearby perturbations to get top_k
      # distinct candidates for validation.
      best_vec = pso_result[:position].map(&:to_i)
      candidates = [best_vec]
      candidates += generate_nearby_candidates(best_vec, top_k - 1)

      # Phase 4: Validate with real simulator
      best = validate_candidates(candidates, top_k)

      # Phase 5: Final simulation with the best parameters.
      # This ensures final_allocation.{json,txt} reflect the best solution found,
      # since evaluate_allocation overwrites those files on every call.
      @logger.info 'Running final simulation with best parameters...'
      evaluate_real(best[:position])

      elapsed = (Time.now - total_start).round(1)
      @logger.info "Surrogate optimization complete in #{elapsed}s"
      @logger.info "Total real simulator calls: #{n_initial_samples + top_k + 1} " \
                    "(vs #{surrogate_swarm_size * surrogate_iterations} surrogate evaluations)"

      puts "Best configuration: #{best[:position].inspect}"
      puts "Best fitness: #{best[:fitness].round(4)}"

      best[:fitness]
    end

    private

    # Generate n_candidates vectors near the given vector by small random perturbations.
    # This gives diversity in the validation phase.
    def generate_nearby_candidates(base_vec, n_candidates)
      mins = @constraints[:min]
      maxs = @constraints[:max]
      candidates = []

      n_candidates.times do
        perturbed = base_vec.each_with_index.map do |val, i|
          # Perturbation: ±1 or ±2 with clamping to bounds
          delta = @sampling_rng.rand(-2..2)
          [[val + delta, mins[i]].max, maxs[i]].min
        end
        candidates << perturbed
      end

      candidates
    end
  end
end # module KUBETWIN
