# frozen_string_literal: true

require "minitest_helper"

# KOptimizer#encode_replicas_set takes rss/n_ms as explicit parameters
# rather than reading them off ivars, so it can be called directly on an
# uninitialized instance (.allocate) without going through #initialize --
# which loads a real simulation Configuration and writes a log file, so is
# exercised through the bin/ scripts and full-run examples rather than unit
# tests here. The method itself now just delegates to
# KUBETWIN::VectorCodec.encode_replicas_set (see vector_codec_spec.rb for
# the exhaustive behavior coverage); this spec only checks the wiring.
describe KUBETWIN::KOptimizer do
  it "delegates encode_replicas_set to KUBETWIN::VectorCodec with (rss, n_ms, x) in the right order" do
    optimizer = KUBETWIN::KOptimizer.allocate
    rss = {a: {selector: "a", replicas: 1}, b: {selector: "b", replicas: 1}}

    result_rss, result_map = optimizer.encode_replicas_set([4, 6], 2, rss)

    _(result_rss[:a][:replicas]).must_equal 4
    _(result_rss[:b][:replicas]).must_equal 6
    _(result_map).must_equal(a: 4, b: 6)
    # original rss untouched (VectorCodec deep-copies)
    _(rss[:a][:replicas]).must_equal 1
  end
end
