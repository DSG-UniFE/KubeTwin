# frozen_string_literal: true

require 'rumale/ensemble/random_forest_regressor'
require 'rumale/model_selection/k_fold'
require 'rumale/model_selection/cross_validation'
require 'rumale/evaluation_measure/r2_score'
require 'rumale/evaluation_measure/mean_squared_error'
require 'rumale/evaluation_measure/mean_absolute_error'
require 'numo/narray'
require 'csv'
require 'logger'

module KUBETWIN
  # Offline analysis of a trained surrogate model.
  #
  # Loads a bundle file saved by KOptimizerACM2Surrogate and computes:
  #   - Regression quality metrics (R², CV-R², RMSE, MAE, MAPE)
  #   - MDI feature importances (Mean Decrease in Impurity)
  #   - Permutation feature importances
  #   - Aggregations by microservice and by category (replicas vs clusters)
  #
  # Usage:
  #   analysis = KUBETWIN::SurrogateAnalysis.new('surrogate_bundle_20260401.bin')
  #   analysis.run          # prints everything to stdout and saves CSVs
  class SurrogateAnalysis
    PERM_REPEATS = 10 # shuffles per feature for permutation importance

    attr_reader :bundle

    def initialize(bundle_path, logger: nil)
      raise ArgumentError, "File not found: #{bundle_path}" unless File.exist?(bundle_path)

      @bundle = Marshal.load(File.binread(bundle_path))
      @logger = logger || Logger.new($stdout, level: Logger::INFO)

      # Unpack bundle
      @model          = @bundle[:model]
      @x_samples      = @bundle[:x_samples]
      @y_samples      = @bundle[:y_samples]
      @feature_labels = @bundle[:feature_labels]
      @ms_names       = @bundle[:ms_names]
      @cluster_names  = @bundle[:cluster_names]
      @n_ms           = @bundle[:n_ms]
      @n_clusters     = @bundle[:n_clusters]
      @max_replicas   = @bundle[:max_replicas]
      @n_dims         = @bundle[:n_dims]
      @training_r2    = @bundle[:training_r2]
      @timestamp      = @bundle[:timestamp]

      # Convert to Numo arrays for computation
      @x_numo = Numo::DFloat.cast(@x_samples)
      @y_numo = Numo::DFloat.cast(@y_samples)

      # Baseline predictions (used by multiple metrics)
      @y_pred = @model.predict(@x_numo)

      # Build feature-to-group mappings
      @feature_category = build_feature_categories
      @feature_ms       = build_feature_microservices
    end

    # Run the full analysis pipeline: metrics, MDI, permutation importance.
    # Prints to stdout and saves CSV files.
    def run
      puts '=' * 72
      puts '  SURROGATE MODEL ANALYSIS'
      puts '=' * 72
      puts "  Bundle timestamp : #{@timestamp}"
      puts "  Training samples : #{@x_samples.length}"
      puts "  Features (dims)  : #{@n_dims}"
      puts "  Microservices    : #{@ms_names.join(', ')}"
      puts "  Clusters         : #{@cluster_names.join(', ')}"
      puts '=' * 72

      metrics = compute_metrics
      print_metrics(metrics)

      mdi = compute_mdi_importance
      print_importance_table('MDI (Mean Decrease in Impurity)', mdi)

      perm = compute_permutation_importance
      print_importance_table('Permutation Importance', perm, show_std: true)

      print_aggregated_importance(mdi, perm)

      # Save CSVs
      ts = @timestamp || Time.now.strftime('%Y%m%d%H%M%S')
      save_feature_csv(mdi, perm, "surrogate_analysis_#{ts}.csv")
      save_summary_csv(mdi, perm, "surrogate_analysis_summary_#{ts}.csv")
      save_metrics_csv(metrics, "surrogate_analysis_metrics_#{ts}.csv")

      puts "\nAnalysis complete."
    end

    # ─── Metrics ───

    def compute_metrics
      metrics = {}

      # Training R² (from bundle)
      metrics[:training_r2] = @training_r2

      # RMSE
      residuals = @y_numo - @y_pred
      metrics[:rmse] = Math.sqrt((residuals ** 2).mean)

      # MAE
      metrics[:mae] = residuals.abs.mean

      # MAPE (skip samples where y == 0 to avoid division by zero)
      nonzero_mask = @y_numo.ne(0)
      if nonzero_mask.count_true > 0
        abs_pct_errors = (residuals.abs / @y_numo.abs)
        # Only consider non-zero targets
        sum_pct = 0.0
        count = 0
        @y_numo.to_a.each_with_index do |y, i|
          next if y == 0.0

          sum_pct += (residuals[i].abs / y.abs)
          count += 1
        end
        metrics[:mape] = count > 0 ? (sum_pct / count) * 100.0 : Float::NAN
      else
        metrics[:mape] = Float::NAN
      end

      # 5-fold Cross-Validation R²
      metrics[:cv_r2_mean], metrics[:cv_r2_std] = compute_cv_r2(n_folds: 5)

      metrics
    end

    # ─── MDI Feature Importance ───

    def compute_mdi_importance
      importances = @model.feature_importances.to_a
      @feature_labels.each_with_index.map do |label, i|
        { index: i, label: label, importance: importances[i] }
      end.sort_by { |f| -f[:importance] }
    end

    # ─── Permutation Feature Importance ───

    def compute_permutation_importance
      @logger.info "Computing permutation importance (#{PERM_REPEATS} repeats x #{@n_dims} features)..."

      # Baseline R²
      baseline_r2 = r2_score(@y_numo, @y_pred)

      rng = Random.new(42)

      results = @feature_labels.each_with_index.map do |label, i|
        drops = Array.new(PERM_REPEATS) do
          x_shuffled = @x_numo.copy
          # Shuffle column i
          col = x_shuffled[true, i].to_a
          shuffled_col = col.shuffle(random: rng)
          x_shuffled[true, i] = Numo::DFloat.cast(shuffled_col)

          y_perm = @model.predict(x_shuffled)
          perm_r2 = r2_score(@y_numo, y_perm)
          baseline_r2 - perm_r2 # R² drop = importance
        end

        {
          index: i,
          label: label,
          importance: drops.sum / drops.length,
          std: std_dev(drops)
        }
      end

      results.sort_by { |f| -f[:importance] }
    end

    private

    # ─── Cross-validation ───

    def compute_cv_r2(n_folds: 5)
      @logger.info "Computing #{n_folds}-fold cross-validation R²..."

      kf = Rumale::ModelSelection::KFold.new(n_splits: n_folds, shuffle: true, random_seed: 42)

      n_max_features = Math.sqrt(@n_dims).ceil
      r2_scores = []

      kf.split(@x_numo, @y_numo).each_with_index do |(train_idx, test_idx), fold|
        x_train = @x_numo[train_idx, true]
        y_train = @y_numo[train_idx]
        x_test  = @x_numo[test_idx, true]
        y_test  = @y_numo[test_idx]

        fold_model = Rumale::Ensemble::RandomForestRegressor.new(
          n_estimators: 100,
          max_depth: nil,
          max_features: n_max_features,
          min_samples_leaf: 2,
          random_seed: 42
        )
        fold_model.fit(x_train, y_train)
        y_pred_fold = fold_model.predict(x_test)

        r2 = r2_score(y_test, y_pred_fold)
        r2_scores << r2
        @logger.info "  Fold #{fold + 1}/#{n_folds}: R² = #{r2.round(4)}"
      end

      mean = r2_scores.sum / r2_scores.length
      std  = std_dev(r2_scores)
      [mean, std]
    end

    # ─── Group mappings ───

    def build_feature_categories
      @feature_labels.map do |label|
        label.start_with?('replicas_') ? 'replica_count' : 'cluster_assignment'
      end
    end

    def build_feature_microservices
      @feature_labels.map do |label|
        # Extract MS name: "replicas_productpage" -> "productpage"
        #                   "cluster_productpage_r0" -> "productpage"
        if label.start_with?('replicas_')
          label.sub('replicas_', '')
        else
          label.sub('cluster_', '').sub(/_r\d+$/, '')
        end
      end
    end

    # ─── Printing ───

    def print_metrics(metrics)
      puts ''
      puts '── Regression Quality Metrics ──'
      puts ''
      puts format('  %-25s %s', 'Training R²:', format_val(metrics[:training_r2]))
      puts format('  %-25s %s', "CV R² (5-fold):",
                  "#{format_val(metrics[:cv_r2_mean])} +/- #{format_val(metrics[:cv_r2_std])}")
      puts format('  %-25s %s', 'RMSE:', format_val(metrics[:rmse]))
      puts format('  %-25s %s', 'MAE:', format_val(metrics[:mae]))
      puts format('  %-25s %s', 'MAPE:', "#{format_val(metrics[:mape])}%")
      puts ''
    end

    def print_importance_table(title, ranked_features, show_std: false, top_n: nil)
      puts "── #{title} ──"
      puts ''

      features = top_n ? ranked_features.first(top_n) : ranked_features

      # Header
      if show_std
        puts format('  %-4s  %-30s  %-14s  %-12s  %-18s  %s',
                    'Rank', 'Feature', 'Category', 'Microservice', 'Importance', 'Std')
        puts '  ' + '-' * 100
      else
        puts format('  %-4s  %-30s  %-14s  %-12s  %s',
                    'Rank', 'Feature', 'Category', 'Microservice', 'Importance')
        puts '  ' + '-' * 80
      end

      features.each_with_index do |f, rank|
        cat = @feature_category[f[:index]]
        ms  = @feature_ms[f[:index]]
        if show_std
          puts format('  %-4d  %-30s  %-14s  %-12s  %-18s  %s',
                      rank + 1, f[:label], cat, ms,
                      format_val(f[:importance]), format_val(f[:std] || 0.0))
        else
          puts format('  %-4d  %-30s  %-14s  %-12s  %s',
                      rank + 1, f[:label], cat, ms, format_val(f[:importance]))
        end
      end
      puts ''
    end

    def print_aggregated_importance(mdi, perm)
      puts '── Aggregated Importance ──'
      puts ''

      # By category
      puts '  By category (replica_count vs cluster_assignment):'
      puts format('    %-20s  %-18s  %s', 'Category', 'MDI (sum)', 'Permutation (sum)')
      puts '    ' + '-' * 60

      %w[replica_count cluster_assignment].each do |cat|
        mdi_sum  = sum_importance_for(mdi, :category, cat)
        perm_sum = sum_importance_for(perm, :category, cat)
        puts format('    %-20s  %-18s  %s', cat, format_val(mdi_sum), format_val(perm_sum))
      end
      puts ''

      # By microservice
      puts '  By microservice:'
      puts format('    %-20s  %-18s  %-18s  %-18s  %s',
                  'Microservice', 'MDI (total)', 'MDI (replicas)', 'MDI (clusters)', 'Perm (total)')
      puts '    ' + '-' * 95

      @ms_names.each do |ms|
        mdi_total    = sum_importance_for(mdi, :ms, ms)
        mdi_rep      = sum_importance_for(mdi, :ms_cat, [ms, 'replica_count'])
        mdi_clust    = sum_importance_for(mdi, :ms_cat, [ms, 'cluster_assignment'])
        perm_total   = sum_importance_for(perm, :ms, ms)
        puts format('    %-20s  %-18s  %-18s  %-18s  %s',
                    ms, format_val(mdi_total), format_val(mdi_rep),
                    format_val(mdi_clust), format_val(perm_total))
      end
      puts ''
    end

    # ─── CSV output ───

    def save_feature_csv(mdi, perm, path)
      # Build lookup hashes by feature index
      mdi_by_idx  = mdi.each_with_index.map  { |f, rank| [f[:index], { importance: f[:importance], rank: rank + 1 }] }.to_h
      perm_by_idx = perm.each_with_index.map { |f, rank| [f[:index], { importance: f[:importance], std: f[:std], rank: rank + 1 }] }.to_h

      CSV.open(path, 'w') do |csv|
        csv << %w[feature_index feature_name microservice category
                  mdi_importance mdi_rank perm_importance_mean perm_importance_std perm_rank]

        @feature_labels.each_with_index do |label, i|
          csv << [
            i, label, @feature_ms[i], @feature_category[i],
            mdi_by_idx[i][:importance],  mdi_by_idx[i][:rank],
            perm_by_idx[i][:importance], perm_by_idx[i][:std], perm_by_idx[i][:rank]
          ]
        end
      end

      puts "  Feature-level CSV saved to: #{path}"
    end

    def save_summary_csv(mdi, perm, path)
      CSV.open(path, 'w') do |csv|
        csv << %w[group_type group_name mdi_importance perm_importance]

        # By category
        %w[replica_count cluster_assignment].each do |cat|
          csv << ['category', cat,
                  sum_importance_for(mdi, :category, cat),
                  sum_importance_for(perm, :category, cat)]
        end

        # By microservice
        @ms_names.each do |ms|
          csv << ['microservice', ms,
                  sum_importance_for(mdi, :ms, ms),
                  sum_importance_for(perm, :ms, ms)]
        end

        # By microservice x category
        @ms_names.each do |ms|
          %w[replica_count cluster_assignment].each do |cat|
            csv << ['microservice_category', "#{ms}_#{cat}",
                    sum_importance_for(mdi, :ms_cat, [ms, cat]),
                    sum_importance_for(perm, :ms_cat, [ms, cat])]
          end
        end
      end

      puts "  Summary CSV saved to: #{path}"
    end

    def save_metrics_csv(metrics, path)
      CSV.open(path, 'w') do |csv|
        csv << %w[metric value]
        csv << ['training_r2', metrics[:training_r2]]
        csv << ['cv_r2_mean', metrics[:cv_r2_mean]]
        csv << ['cv_r2_std', metrics[:cv_r2_std]]
        csv << ['rmse', metrics[:rmse]]
        csv << ['mae', metrics[:mae]]
        csv << ['mape', metrics[:mape]]
        csv << ['n_samples', @x_samples.length]
        csv << ['n_dims', @n_dims]
        csv << ['n_microservices', @n_ms]
        csv << ['n_clusters', @n_clusters]
      end

      puts "  Metrics CSV saved to: #{path}"
    end

    # ─── Helpers ───

    def r2_score(y_true, y_pred)
      ss_res = ((y_true - y_pred) ** 2).sum
      ss_tot = ((y_true - y_true.mean) ** 2).sum
      ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0
    end

    def std_dev(arr)
      return 0.0 if arr.length <= 1

      mean = arr.sum / arr.length.to_f
      variance = arr.sum { |v| (v - mean) ** 2 } / (arr.length - 1).to_f
      Math.sqrt(variance)
    end

    def format_val(v)
      v.is_a?(Float) ? format('%.6f', v) : v.to_s
    end

    # Sum importances for a group of features, given a grouping criterion.
    # criterion can be :category, :ms, or :ms_cat
    def sum_importance_for(ranked_features, criterion, value)
      ranked_features.select do |f|
        idx = f[:index]
        case criterion
        when :category
          @feature_category[idx] == value
        when :ms
          @feature_ms[idx] == value
        when :ms_cat
          ms, cat = value
          @feature_ms[idx] == ms && @feature_category[idx] == cat
        end
      end.sum { |f| f[:importance] }
    end
  end
end
