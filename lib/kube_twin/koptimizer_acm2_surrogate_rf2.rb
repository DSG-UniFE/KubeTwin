#!/usr/bin/env ruby

require 'mhl'
require 'rumale/ensemble/random_forest_regressor'
require 'numo/narray'
require_relative './configuration'
require_relative './ksimulation'
require 'logger'

module KUBETWIN
  # Two-phase RandomForest surrogate optimizer with feature selection.
  #
  # Improves on KOptimizerACM2Surrogate by concentrating the model on the
  # features that actually matter, dramatically improving the
  # samples-to-feature ratio and reducing overfitting.
  #
  # Flow:
  #   1. Sample N initial points with the real simulator.
  #   2. Train a full-dimensional RF on all features (Phase 1).
  #   3. Compute MDI feature importances and select the top-K features
  #      that together account for a configurable fraction of total
  #      importance (default: 80%).
  #   4. Retrain a new RF on only the selected features (Phase 2).
  #   5. Run PSO on the reduced-dimension surrogate.
  #   6. Validate the top candidates with the real simulator.
  #   7. Return the best validated solution.
  class KOptimizerACM2SurrogateRF2
    MAX_REPLICAS = 10

    def initialize(configuration_file)
      time = Time.now.strftime('%Y%m%d%H%M%S')
      ga_log = "KT_surrogate_rf2_optimizer_log_#{time}.log"
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

      # Dedicated RNG for sampling -- immune to srand() calls inside the simulator
      @sampling_rng = Random.new

      # Microservice names in vector order (derived from replica_sets ordering)
      @ms_names = @rss.map { |_k, v| v[:selector] }
      @cluster_names = @cluster_repository.keys.map(&:to_s)

      # Human-readable label for each dimension of the search vector
      @feature_labels = build_feature_labels

      rps = ENV['RPS'] ? ENV['RPS'].to_i : 10
      @logger.info "Setting RPS to #{rps}"
      @start_time = @sim_conf.start_time
    end

    # --- Vector encoding / decoding (same as KOptimizerACM2) ---

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

    # --- Real simulation evaluation ---

    def evaluate_real(int_vector)
      new_rss, = encode_replicas_set(int_vector[0...@n_ms])
      replicas_mapping = decode_cluster_mapping(int_vector)

      sim = KUBETWIN::KSimulation.new(configuration: @sim_conf,
                                      evaluator: KUBETWIN::Evaluator.new(@sim_conf))
      sim.evaluate_allocation(new_rss, nil, nil, nil, nil, replicas_mapping)
    end

    # --- Sampling ---

    def sample_initial_points(n_samples)
      mins = @constraints[:min]
      maxs = @constraints[:max]

      x_samples = []
      y_samples = []

      @logger.info "RF2 Surrogate: sampling #{n_samples} initial points with real simulator..."

      n_samples.times do |i|
        vec = mins.zip(maxs).map { |lo, hi| @sampling_rng.rand(lo..hi) }
        fitness = evaluate_real(vec)

        x_samples << vec
        y_samples << fitness

        if (i + 1) % 20 == 0
          @logger.info "  Sampled #{i + 1}/#{n_samples} (last fitness: #{fitness.round(4)})"
        end
        @ga_logger.info "Sample #{i + 1}: fitness=#{fitness.round(4)} vector=#{vec.inspect}"
      end

      @logger.info "RF2 Surrogate: sampling complete. Fitness range: " \
                   "[#{y_samples.min.round(4)}, #{y_samples.max.round(4)}]"

      [x_samples, y_samples]
    end

    # --- Phase 1: Full-dimensional RF for feature selection ---

    # Train a RandomForest on all features and return [model, r2, mdi_importances].
    def train_full_rf(x_samples, y_samples)
      @logger.info "Phase 1: training full RF on #{x_samples.length} samples " \
                   "(#{@n_dims} features)..."

      x_numo = Numo::DFloat.cast(x_samples)
      y_numo = Numo::DFloat.cast(y_samples)

      n_max_features = Math.sqrt(@n_dims).ceil

      model = Rumale::Ensemble::RandomForestRegressor.new(
        n_estimators: 100,
        max_depth: nil,
        max_features: n_max_features,
        min_samples_leaf: 2,
        random_seed: 42
      )
      model.fit(x_numo, y_numo)

      y_pred = model.predict(x_numo)
      ss_res = ((y_numo - y_pred) ** 2).sum
      ss_tot = ((y_numo - y_numo.mean) ** 2).sum
      r2 = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0

      importances = model.feature_importances.to_a

      @logger.info "Phase 1: training R² = #{r2.round(4)}"
      @ga_logger.info "Phase 1 full RF: R² = #{r2.round(4)}"

      [model, r2, importances]
    end

    # --- Feature selection ---

    # Select feature indices whose cumulative MDI importance reaches the
    # threshold fraction of total importance.
    # Returns an array of original feature indices, sorted by importance (descending).
    def select_top_features(importances, threshold:)
      total = importances.sum
      return (0...importances.length).to_a if total <= 0

      # Sort by importance descending, keeping track of original index
      ranked = importances.each_with_index
                          .map { |imp, idx| { idx: idx, imp: imp } }
                          .sort_by { |h| -h[:imp] }

      selected = []
      cumulative = 0.0

      ranked.each do |h|
        selected << h[:idx]
        cumulative += h[:imp]
        break if cumulative / total >= threshold
      end

      @logger.info "Feature selection: #{selected.length}/#{importances.length} features " \
                   "cover #{(cumulative / total * 100).round(1)}% of total MDI importance"
      @ga_logger.info "Selected features (#{selected.length}): #{selected.inspect}"

      # Log which features were selected
      selected.each_with_index do |idx, rank|
        @logger.info "  #{rank + 1}. #{@feature_labels[idx]} " \
                     "(MDI: #{importances[idx].round(6)})"
      end

      selected
    end

    # --- Phase 2: Reduced-dimensional RF ---

    # Train a new RF using only the selected feature columns.
    # Returns [model, r2].
    def train_reduced_rf(x_samples, y_samples, selected_indices)
      n_selected = selected_indices.length
      @logger.info "Phase 2: retraining RF on #{n_selected} selected features " \
                   "(was #{@n_dims})..."

      x_full = Numo::DFloat.cast(x_samples)
      y_numo = Numo::DFloat.cast(y_samples)

      # Extract only selected columns
      x_reduced = x_full[true, selected_indices]

      n_max_features = [Math.sqrt(n_selected).ceil, 1].max

      model = Rumale::Ensemble::RandomForestRegressor.new(
        n_estimators: 200,       # more trees since fewer features
        max_depth: nil,
        max_features: n_max_features,
        min_samples_leaf: 2,
        random_seed: 42
      )
      model.fit(x_reduced, y_numo)

      y_pred = model.predict(x_reduced)
      ss_res = ((y_numo - y_pred) ** 2).sum
      ss_tot = ((y_numo - y_numo.mean) ** 2).sum
      r2 = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0

      @logger.info "Phase 2: reduced RF training R² = #{r2.round(4)} " \
                   "(samples/features ratio: #{(x_samples.length.to_f / n_selected).round(1)})"
      @ga_logger.info "Phase 2 reduced RF: R² = #{r2.round(4)}, " \
                      "#{x_samples.length} samples / #{n_selected} features"

      [model, r2]
    end

    # --- PSO on reduced surrogate ---

    # Run PSO using the reduced surrogate.  PSO still explores the full
    # 44-dim space, but only the selected columns are fed to the model.
    def run_pso_on_surrogate(model, selected_indices, num_iterations:, swarm_size:)
      @logger.info "RF2 Surrogate: running PSO (#{swarm_size} particles, " \
                   "#{num_iterations} iterations, #{selected_indices.length} active features)..."

      surrogate_fn = lambda do |position|
        int_vec = position.map(&:to_i)
        # Extract only the selected features for prediction
        reduced = selected_indices.map { |i| int_vec[i] }
        x = Numo::DFloat.cast([reduced])
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

    # --- Validation ---

    def validate_candidates(candidates, top_k)
      @logger.info "RF2 Surrogate: validating top #{top_k} candidates with real simulator..."

      results = []
      candidates.first(top_k).each_with_index do |vec, i|
        int_vec = vec.map(&:to_i)
        fitness = evaluate_real(int_vec)
        results << { position: int_vec, fitness: fitness }
        @logger.info "  Candidate #{i + 1}/#{top_k}: real fitness = #{fitness.round(4)}"
        @ga_logger.info "Validation #{i + 1}: fitness=#{fitness.round(4)} vector=#{int_vec.inspect}"
      end

      best = results.max_by { |r| r[:fitness] }
      @logger.info "RF2 Surrogate: best validated fitness = #{best[:fitness].round(4)}"
      best
    end

    # --- Main optimization entry point ---

    # Two-phase surrogate-assisted optimization:
    #   1. Sample n_initial_samples real evaluations
    #   2. Train full RF -> compute MDI -> select top features (>= importance_threshold)
    #   3. Retrain reduced RF on selected features only
    #   4. Run PSO on the reduced surrogate (cheap)
    #   5. Validate top_k candidates with the real simulator
    #   6. Return the best validated result
    #
    # Total real simulator calls: n_initial_samples + top_k + 1
    def optimize(n_initial_samples: 200, importance_threshold: 0.80,
                 surrogate_iterations: 50, surrogate_swarm_size: 100, top_k: 5)
      total_start = Time.now

      # Phase 1: Sample + full RF for feature selection
      x_samples, y_samples = sample_initial_points(n_initial_samples)
      full_model, full_r2, importances = train_full_rf(x_samples, y_samples)

      # Feature selection: keep features covering >= threshold of MDI importance
      @selected_indices = select_top_features(importances, threshold: importance_threshold)

      # Phase 2: Retrain on selected features only
      reduced_model, reduced_r2 = train_reduced_rf(x_samples, y_samples, @selected_indices)

      # Persist both models + training data for offline analysis
      save_surrogate_bundle(full_model, reduced_model, x_samples, y_samples,
                            full_r2, reduced_r2, importances)

      # Phase 3: PSO on reduced surrogate
      pso_result = run_pso_on_surrogate(reduced_model, @selected_indices,
                                        num_iterations: surrogate_iterations,
                                        swarm_size: surrogate_swarm_size)

      best_vec = pso_result[:position].map(&:to_i)
      candidates = [best_vec]
      candidates += generate_nearby_candidates(best_vec, top_k - 1)

      # Phase 4: Validate with real simulator
      best = validate_candidates(candidates, top_k)

      # Phase 5: Final simulation so final_allocation.{json,txt} are saved
      @logger.info 'Running final simulation with best parameters...'
      evaluate_real(best[:position])

      elapsed = (Time.now - total_start).round(1)
      @logger.info "RF2 Surrogate optimization complete in #{elapsed}s"
      @logger.info "Total real simulator calls: #{n_initial_samples + top_k + 1} " \
                   "(vs #{surrogate_swarm_size * surrogate_iterations} surrogate evaluations)"
      @logger.info "Feature reduction: #{@n_dims} -> #{@selected_indices.length} " \
                   "(#{(@selected_indices.length.to_f / @n_dims * 100).round(1)}% of original)"

      puts "Best configuration: #{best[:position].inspect}"
      puts "Best fitness: #{best[:fitness].round(4)}"

      best[:fitness]
    end

    private

    def build_feature_labels
      labels = @ms_names.map { |name| "replicas_#{name}" }
      @ms_names.each do |name|
        @max_replicas.times { |r| labels << "cluster_#{name}_r#{r}" }
      end
      labels
    end

    # Save a bundle compatible with SurrogateAnalysis, plus the extra
    # RF2-specific fields (reduced model, selected features, etc.).
    def save_surrogate_bundle(full_model, reduced_model, x_samples, y_samples,
                              full_r2, reduced_r2, importances)
      timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      path = "surrogate_rf2_bundle_#{timestamp}.bin"

      # Build labels for the reduced feature set
      selected_labels = @selected_indices.map { |i| @feature_labels[i] }

      bundle = {
        # Standard fields (compatible with SurrogateAnalysis)
        model: full_model,
        x_samples: x_samples,
        y_samples: y_samples,
        feature_labels: @feature_labels,
        ms_names: @ms_names,
        cluster_names: @cluster_names,
        n_ms: @n_ms,
        n_clusters: @n_clusters,
        max_replicas: @max_replicas,
        n_dims: @n_dims,
        timestamp: timestamp,
        training_r2: full_r2,
        # RF2-specific fields
        surrogate_type: 'rf2_feature_selection',
        reduced_model: reduced_model,
        reduced_r2: reduced_r2,
        selected_feature_indices: @selected_indices,
        selected_feature_labels: selected_labels,
        mdi_importances: importances,
        importance_threshold: 0.80,
        n_selected_features: @selected_indices.length
      }

      File.open(path, 'wb') { |f| f.write(Marshal.dump(bundle)) }
      @logger.info "RF2 Surrogate bundle saved to #{path}"
      @ga_logger.info "RF2 Surrogate bundle saved to #{path}"
      path
    end

    def generate_nearby_candidates(base_vec, n_candidates)
      mins = @constraints[:min]
      maxs = @constraints[:max]
      candidates = []

      n_candidates.times do
        perturbed = base_vec.each_with_index.map do |val, i|
          delta = @sampling_rng.rand(-2..2)
          [[val + delta, mins[i]].max, maxs[i]].min
        end
        candidates << perturbed
      end

      candidates
    end
  end
end # module KUBETWIN
