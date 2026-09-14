# frozen_string_literal: true

require 'minitest_helper'

# KOptimizerACM#encode_replicas_set used to mutate its `rss` argument in
# place instead of deep-copying it -- an apparent copy-paste drift from
# koptimizer.rb (every other KOptimizer* class deep-copies). It now
# delegates to KUBETWIN::VectorCodec.encode_replicas_set, same as the rest
# of the family, which fixes that. This spec locks the fix in as a
# regression test.
describe KUBETWIN::KOptimizerACM do
  it 'delegates encode_replicas_set to KUBETWIN::VectorCodec and does not mutate its rss argument' do
    optimizer = KUBETWIN::KOptimizerACM.allocate
    rss = { a: { selector: 'a', replicas: 1 }, b: { selector: 'b', replicas: 1 } }

    result_rss, result_map = optimizer.encode_replicas_set([4, 6], 2, rss)

    _(result_rss[:a][:replicas]).must_equal 4
    _(result_rss[:b][:replicas]).must_equal 6
    _(result_map).must_equal(a: 4, b: 6)
    # regression check: the caller's rss must be left untouched
    _(rss[:a][:replicas]).must_equal 1
    _(rss[:b][:replicas]).must_equal 1
  end
end
