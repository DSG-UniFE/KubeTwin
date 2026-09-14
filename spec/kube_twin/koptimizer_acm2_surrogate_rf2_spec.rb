# frozen_string_literal: true

require 'minitest_helper'

# KOptimizerACM2SurrogateRF2's encode_replicas_set / decode_cluster_mapping /
# build_feature_labels / generate_nearby_candidates all delegate to
# KUBETWIN::VectorCodec (see vector_codec_spec.rb for the exhaustive
# behavior coverage; this spec only checks the wiring). The latter two are
# private, so they're exercised via #send, same as elsewhere in this
# codebase when a private pure method is tested directly. Built via
# .allocate with just the ivars these methods need, rather than through
# #initialize, which loads a real simulation Configuration and writes a log
# file.
describe KUBETWIN::KOptimizerACM2SurrogateRF2 do
  def build_optimizer(rss: {}, n_ms: 2, max_replicas: 10, ms_names: %w[a b], constraints: nil, sampling_rng: nil)
    optimizer = KUBETWIN::KOptimizerACM2SurrogateRF2.allocate
    optimizer.instance_variable_set(:@rss, rss)
    optimizer.instance_variable_set(:@n_ms, n_ms)
    optimizer.instance_variable_set(:@max_replicas, max_replicas)
    optimizer.instance_variable_set(:@ms_names, ms_names)
    optimizer.instance_variable_set(:@constraints, constraints || { min: [1, 1], max: [10, 10] })
    optimizer.instance_variable_set(:@sampling_rng, sampling_rng || Random.new(1))
    optimizer
  end

  it 'delegates encode_replicas_set to KUBETWIN::VectorCodec using @rss and @n_ms' do
    optimizer = build_optimizer(
      rss: { a: { selector: 'a', replicas: 1 }, b: { selector: 'b', replicas: 1 } },
      n_ms: 2
    )

    rss, = optimizer.encode_replicas_set([3, 7])

    _(rss[:a][:replicas]).must_equal 3
    _(rss[:b][:replicas]).must_equal 7
  end

  it 'delegates decode_cluster_mapping to KUBETWIN::VectorCodec using @n_ms and @max_replicas' do
    optimizer = build_optimizer(n_ms: 2, max_replicas: 3)
    vector = [2, 1] + [10, 11, 12] + [20, 21, 22]

    mapping = optimizer.decode_cluster_mapping(vector)

    _(mapping).must_equal [10, 11, 20]
  end

  it 'delegates the private build_feature_labels to KUBETWIN::VectorCodec using @ms_names and @max_replicas' do
    optimizer = build_optimizer(ms_names: %w[svcA svcB], max_replicas: 2)

    labels = optimizer.send(:build_feature_labels)

    _(labels).must_equal %w[
      replicas_svcA replicas_svcB
      cluster_svcA_r0 cluster_svcA_r1
      cluster_svcB_r0 cluster_svcB_r1
    ]
  end

  it 'delegates the private generate_nearby_candidates to KUBETWIN::VectorCodec using @constraints and @sampling_rng' do
    optimizer = build_optimizer(constraints: { min: [1, 1], max: [10, 10] }, sampling_rng: Random.new(42))

    candidates = optimizer.send(:generate_nearby_candidates, [5, 5], 4)

    _(candidates.length).must_equal 4
    candidates.each do |vec|
      _(vec[0]).must_be :>=, 1
      _(vec[0]).must_be :<=, 10
    end
  end
end
