# frozen_string_literal: true

require 'rumale/ensemble/random_forest_regressor'
require 'numo/narray'
require 'logger'

module KUBETWIN
  class RandomForestSurrogateRF2
    attr_reader :full_model,
                :reduced_model,
                :full_r2,
                :reduced_r2,
                :mdi_importances,
                :selected_feature_indices,
                :selected_feature_labels,
                :importance_threshold,
                :feature_labels,
                :ms_names,
                :cluster_names,
                :n_ms,
                :n_clusters,
                :max_replicas,
                :n_dims

    def initialize(feature_labels:, ms_names:, cluster_names:, n_ms:, n_clusters:, max_replicas:, logger: nil)
      @feature_labels = feature_labels
      @ms_names = ms_names
      @cluster_names = cluster_names
      @n_ms = n_ms
      @n_clusters = n_clusters
      @max_replicas = max_replicas
      @n_dims = feature_labels.length
      @logger = logger || Logger.new($stdout, level: Logger::INFO)
    end

    def fit(x_samples, y_samples, importance_threshold: 0.80)
      @importance_threshold = importance_threshold
      @full_model, @full_r2, @mdi_importances = train_rf(x_samples, y_samples, feature_indices: nil)
      @selected_feature_indices = select_top_features(@mdi_importances, threshold: importance_threshold)
      @selected_feature_labels = @selected_feature_indices.map { |i| @feature_labels[i] }
      @reduced_model, @reduced_r2, = train_rf(x_samples, y_samples, feature_indices: @selected_feature_indices)
      self
    end

    def predict(vector, reduced: true)
      raise 'Surrogate must be trained before prediction' if model_for(reduced).nil?

      input = reduced ? @selected_feature_indices.map { |i| vector[i].to_i } : vector.map(&:to_i)
      model_for(reduced).predict(Numo::DFloat.cast([input]))[0]
    end

    def save_bundle(x_samples:, y_samples:, path: nil, timestamp: nil)
      raise 'Surrogate must be trained before saving' if @full_model.nil? || @reduced_model.nil?

      timestamp ||= Time.now.strftime('%Y%m%d%H%M%S')
      path ||= "surrogate_rf2_bundle_#{timestamp}.bin"

      bundle = {
        model: @full_model,
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
        training_r2: @full_r2,
        surrogate_type: 'rf2_feature_selection',
        reduced_model: @reduced_model,
        reduced_r2: @reduced_r2,
        selected_feature_indices: @selected_feature_indices,
        selected_feature_labels: @selected_feature_labels,
        mdi_importances: @mdi_importances,
        importance_threshold: @importance_threshold,
        n_selected_features: @selected_feature_indices.length
      }

      File.open(path, 'wb') { |f| f.write(Marshal.dump(bundle)) }
      path
    end

    private

    def model_for(reduced)
      reduced ? @reduced_model : @full_model
    end

    def train_rf(x_samples, y_samples, feature_indices:)
      x_numo = Numo::DFloat.cast(x_samples)
      y_numo = Numo::DFloat.cast(y_samples)

      if feature_indices
        feature_count = feature_indices.length
        @logger.info "Training reduced RF on #{x_samples.length} samples (#{feature_count} features)..."
        x_train = x_numo[true, feature_indices]
        n_estimators = 200
      else
        feature_count = @n_dims
        @logger.info "Training full RF on #{x_samples.length} samples (#{feature_count} features)..."
        x_train = x_numo
        n_estimators = 100
      end

      n_max_features = [Math.sqrt(feature_count).ceil, 1].max
      model = Rumale::Ensemble::RandomForestRegressor.new(
        n_estimators: n_estimators,
        max_depth: nil,
        max_features: n_max_features,
        min_samples_leaf: 2,
        random_seed: 42
      )
      model.fit(x_train, y_numo)

      y_pred = model.predict(x_train)
      ss_res = ((y_numo - y_pred)**2).sum
      ss_tot = ((y_numo - y_numo.mean)**2).sum
      r2 = ss_tot > 0 ? 1.0 - ss_res / ss_tot : 0.0
      importances = model.feature_importances.to_a

      [model, r2, importances]
    end

    def select_top_features(importances, threshold:)
      total = importances.sum
      return (0...importances.length).to_a if total <= 0

      ranked = importances.each_with_index.map { |imp, idx| { idx: idx, imp: imp } }
                          .sort_by { |entry| -entry[:imp] }

      selected = []
      cumulative = 0.0
      ranked.each do |entry|
        selected << entry[:idx]
        cumulative += entry[:imp]
        break if cumulative / total >= threshold
      end

      selected
    end
  end
end
