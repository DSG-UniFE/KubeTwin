# frozen_string_literal: true

require "minitest_helper"
require "ice_nine"

describe KUBETWIN::IndependentStreams do
  # A configuration as a .conf file writes it: one fixed seed, deep-frozen.
  let(:gaussian) do
    IceNine.deep_freeze({distribution: :gaussian, args: {mean: 0.02, sd: 0.005, seed: 12_345}})
  end
  let(:mixture) do
    IceNine.deep_freeze({distribution: :mixture, args: [
      {distribution: :gaussian, weight: 0.5, args: {mean: 0.01, sd: 0.001, seed: 12_345}},
      {distribution: :gaussian, weight: 0.5, args: {mean: 0.05, sd: 0.001, seed: 12_345}}
    ]})
  end

  def draws(distribution, count = 20)
    Array.new(count) { distribution.sample }
  end

  it "gives copies of one configuration different streams" do
    seeds = Random.new(1)
    first = draws(KUBETWIN::IndependentStreams.distribution(gaussian, seeds))
    second = draws(KUBETWIN::IndependentStreams.distribution(gaussian, seeds))

    _(first).wont_equal second
    # Without it, both copies would replay the configured seed's sequence.
    _(draws(ERV::RandomVariable.new(gaussian))).must_equal draws(ERV::RandomVariable.new(gaussian))
  end

  it "is reproducible from the seed generator's seed" do
    run = -> { draws(KUBETWIN::IndependentStreams.distribution(gaussian, Random.new(9))) }

    _(run.call).must_equal run.call
  end

  it "seeds a mixture's component selector as well as its components" do
    seeds = Random.new(3)
    # Which component each draw came from: below or above 0.03.
    picks = Array.new(2) { draws(KUBETWIN::IndependentStreams.distribution(mixture, seeds), 40).map { |x| x > 0.03 } }

    _(picks.first).wont_equal picks.last
    _(picks.flatten.uniq.size).must_equal 2
  end

  it "leaves the frozen configuration untouched" do
    KUBETWIN::IndependentStreams.distribution(mixture, Random.new(5))

    _(mixture[:args].first[:args][:seed]).must_equal 12_345
  end
end
