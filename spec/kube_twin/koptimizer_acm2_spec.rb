# frozen_string_literal: true

require 'minitest_helper'

# KOptimizerACM2#encode_replicas_set / #decode_cluster_mapping delegate to
# KUBETWIN::VectorCodec, reading @rss/@n_ms/@max_replicas off the instance
# (see vector_codec_spec.rb for the exhaustive behavior coverage of the
# underlying logic; this spec only checks the wiring). Built via .allocate
# with just the ivars these two methods need, rather than through
# #initialize, which loads a real simulation Configuration and writes a log
# file.
describe KUBETWIN::KOptimizerACM2 do
  def build_optimizer(rss:, n_ms:, max_replicas: 10)
    optimizer = KUBETWIN::KOptimizerACM2.allocate
    optimizer.instance_variable_set(:@rss, rss)
    optimizer.instance_variable_set(:@n_ms, n_ms)
    optimizer.instance_variable_set(:@max_replicas, max_replicas)
    optimizer
  end

  it 'delegates encode_replicas_set to KUBETWIN::VectorCodec using @rss and @n_ms' do
    optimizer = build_optimizer(
      rss: { a: { selector: 'a', replicas: 1 }, b: { selector: 'b', replicas: 1 } },
      n_ms: 2
    )

    rss, replicas_per_ms = optimizer.encode_replicas_set([3, 7])

    _(rss[:a][:replicas]).must_equal 3
    _(rss[:b][:replicas]).must_equal 7
    _(replicas_per_ms).must_equal(a: 3, b: 7)
  end

  it 'delegates decode_cluster_mapping to KUBETWIN::VectorCodec using @n_ms and @max_replicas' do
    optimizer = build_optimizer(rss: {}, n_ms: 2, max_replicas: 3)
    vector = [2, 1] + [10, 11, 12] + [20, 21, 22]

    mapping = optimizer.decode_cluster_mapping(vector)

    _(mapping).must_equal [10, 11, 20]
  end
end
