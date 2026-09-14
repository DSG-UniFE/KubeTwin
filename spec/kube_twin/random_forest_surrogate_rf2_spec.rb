# frozen_string_literal: true

require "minitest_helper"

# RandomForestSurrogateRF2 wraps Rumale's RandomForestRegressor into a
# two-phase (full-model -> feature-selection -> reduced-model) surrogate.
# #select_top_features is pure Ruby (sorting/summing floats, no ML
# dependency at all) and is tested directly. #fit/#predict are exercised
# through a real, fast Rumale fit on tiny synthetic data -- this is cheap
# enough (no fixture files needed, unlike MDN's Torch weights) to test for
# real rather than only through mocks.
describe KUBETWIN::RandomForestSurrogateRF2 do
  describe "#select_top_features (private)" do
    it "selects features in decreasing importance order until reaching the threshold fraction of total importance" do
      surrogate = KUBETWIN::RandomForestSurrogateRF2.allocate
      importances = [0.5, 0.3, 0.15, 0.05] # sums to 1.0

      selected = surrogate.send(:select_top_features, importances, threshold: 0.8)

      # 0.5 -> cumulative 0.5 (50%, below threshold); + 0.3 -> cumulative 0.8 (80%, meets it) -> stop
      _(selected).must_equal [0, 1]
    end

    it "returns every index when total importance is zero (nothing to rank by)" do
      surrogate = KUBETWIN::RandomForestSurrogateRF2.allocate

      selected = surrogate.send(:select_top_features, [0.0, 0.0, 0.0], threshold: 0.8)

      _(selected).must_equal [0, 1, 2]
    end

    it "selects every feature when the threshold requires 100% of importance" do
      surrogate = KUBETWIN::RandomForestSurrogateRF2.allocate
      importances = [0.4, 0.35, 0.25]

      selected = surrogate.send(:select_top_features, importances, threshold: 1.0)

      _(selected).must_equal [0, 1, 2]
    end

    it "ranks by importance regardless of index order, keeping the sort stable among ties" do
      surrogate = KUBETWIN::RandomForestSurrogateRF2.allocate
      importances = [0.1, 0.4, 0.4, 0.1]

      selected = surrogate.send(:select_top_features, importances, threshold: 0.5)

      # sorted descending by importance: idx1 (0.4), idx2 (0.4, tie broken by original order), ...
      # cumulative after idx1 = 0.4 (< 0.5); after idx2 = 0.8 (>= 0.5) -> stop
      _(selected).must_equal [1, 2]
    end
  end

  describe "#fit and #predict" do
    it "trains full and reduced random forests that predict close to a known-linear target" do
      surrogate = KUBETWIN::RandomForestSurrogateRF2.new(
        feature_labels: %w[f0 f1 f2],
        ms_names: %w[svcA],
        cluster_names: %w[c0],
        n_ms: 1,
        n_clusters: 1,
        max_replicas: 3,
        logger: Logger.new(File::NULL)
      )

      # y depends only on f0 (f1/f2 are irrelevant noise features), so a
      # trained RF should both fit well and rank f0 as most important.
      rng = Random.new(123)
      x_samples = Array.new(40) { [rng.rand(0..10), rng.rand(0..10), rng.rand(0..10)] }
      y_samples = x_samples.map { |row| row[0] * 2.0 }

      surrogate.fit(x_samples, y_samples, importance_threshold: 0.5)

      _(surrogate.full_model).wont_be_nil
      _(surrogate.reduced_model).wont_be_nil
      _(surrogate.full_r2).must_be :>, 0.5
      _(surrogate.selected_feature_indices).must_include 0

      prediction = surrogate.predict(x_samples.first, reduced: true)
      _(prediction).must_be_close_to y_samples.first, 4.0
    end

    it "raises if predict is called before fit" do
      surrogate = KUBETWIN::RandomForestSurrogateRF2.new(
        feature_labels: %w[f0], ms_names: %w[svcA], cluster_names: %w[c0],
        n_ms: 1, n_clusters: 1, max_replicas: 3, logger: Logger.new(File::NULL)
      )

      assert_raises(RuntimeError) { surrogate.predict([1]) }
    end
  end
end
