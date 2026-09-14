# frozen_string_literal: true

require 'minitest_helper'

# KUBETWIN::VectorCodec holds the vector-encoding/decoding logic shared by
# the whole KOptimizer* family (koptimizer.rb, koptimizer_acm.rb,
# koptimizer_acm2.rb, koptimizer_acm2_surrogate.rb,
# koptimizer_acm2_surrogate_rf2.rb, koptimizer_multiobjective.rb) -- see
# that module's doc comment for why it exists. Every method here is a pure
# function (no simulation, no I/O), so it's tested directly rather than
# only indirectly through six near-identical optimizer classes. Each
# optimizer class's own wiring (that it passes its own ivars through
# correctly) is covered by that class's own spec file.
describe KUBETWIN::VectorCodec do
  describe '.encode_replicas_set' do
    def rss_fixture
      {
        productpage: { selector: 'productpage', replicas: 1 },
        reviews: { selector: 'reviews', replicas: 1 }
      }
    end

    it 'applies the first n_ms elements of x as replica counts, in key order' do
      rss, replicas_per_ms = KUBETWIN::VectorCodec.encode_replicas_set(rss_fixture, 2, [3, 5])

      _(rss[:productpage][:replicas]).must_equal 3
      _(rss[:reviews][:replicas]).must_equal 5
      _(replicas_per_ms).must_equal(productpage: 3, reviews: 5)
    end

    it 'ignores any elements of x beyond n_ms' do
      rss, = KUBETWIN::VectorCodec.encode_replicas_set(rss_fixture, 2, [3, 5, 99, 99])

      _(rss[:productpage][:replicas]).must_equal 3
      _(rss[:reviews][:replicas]).must_equal 5
    end

    it 'does not mutate the rss hash (or its nested value hashes) passed in' do
      original = rss_fixture
      snapshot = Marshal.load(Marshal.dump(original))

      KUBETWIN::VectorCodec.encode_replicas_set(original, 2, [7, 9])

      _(original).must_equal snapshot
    end

    it 'returns a deep copy, so mutating the result does not affect the input' do
      original = rss_fixture
      rss, = KUBETWIN::VectorCodec.encode_replicas_set(original, 2, [3, 5])

      rss[:productpage][:replicas] = 999

      _(original[:productpage][:replicas]).must_equal 1
    end
  end

  describe '.decode_cluster_mapping' do
    it 'reads only the first replica_count[i] cluster assignments per microservice, ignoring padding' do
      # n_ms=2, max_replicas=3: ms0 has 2 replicas, ms1 has 1
      vector = [2, 1] + [10, 11, 12] + [20, 21, 22]

      mapping = KUBETWIN::VectorCodec.decode_cluster_mapping(vector, 2, 3)

      _(mapping).must_equal [10, 11, 20]
    end

    it 'contributes nothing for a microservice with zero replicas' do
      vector = [0, 2] + [10, 11, 12] + [20, 21, 22]

      mapping = KUBETWIN::VectorCodec.decode_cluster_mapping(vector, 2, 3)

      _(mapping).must_equal [20, 21]
    end

    it 'returns an empty mapping when every microservice has zero replicas' do
      vector = [0, 0] + [10, 11, 12] + [20, 21, 22]

      mapping = KUBETWIN::VectorCodec.decode_cluster_mapping(vector, 2, 3)

      _(mapping).must_equal []
    end
  end

  describe '.build_feature_labels' do
    it 'builds one replica-count label per microservice, followed by max_replicas cluster labels each' do
      labels = KUBETWIN::VectorCodec.build_feature_labels(%w[productpage reviews], 2)

      _(labels).must_equal %w[
        replicas_productpage replicas_reviews
        cluster_productpage_r0 cluster_productpage_r1
        cluster_reviews_r0 cluster_reviews_r1
      ]
    end
  end

  describe '.generate_nearby_candidates' do
    it 'generates the requested number of candidates' do
      rng = Random.new(42)
      candidates = KUBETWIN::VectorCodec.generate_nearby_candidates([5, 5], 4, [1, 1], [10, 10], rng)

      _(candidates.length).must_equal 4
    end

    it 'clamps every perturbed value within [mins[i], maxs[i]], even at the extreme +/-2 delta' do
      always_max_delta = Object.new
      def always_max_delta.rand(_range) = 2

      candidates = KUBETWIN::VectorCodec.generate_nearby_candidates([1, 10], 1, [1, 1], [10, 10], always_max_delta)
      _(candidates).must_equal [[3, 10]] # 1+2=3 (in range); 10+2=12 clamped down to 10

      always_min_delta = Object.new
      def always_min_delta.rand(_range) = -2

      candidates = KUBETWIN::VectorCodec.generate_nearby_candidates([1, 10], 1, [1, 1], [10, 10], always_min_delta)
      _(candidates).must_equal [[1, 8]] # 1-2=-1 clamped up to 1; 10-2=8 (in range)
    end

    it 'is deterministic given the same rng seed' do
      a = KUBETWIN::VectorCodec.generate_nearby_candidates([5, 5], 3, [1, 1], [10, 10], Random.new(7))
      b = KUBETWIN::VectorCodec.generate_nearby_candidates([5, 5], 3, [1, 1], [10, 10], Random.new(7))

      _(a).must_equal b
    end
  end
end
