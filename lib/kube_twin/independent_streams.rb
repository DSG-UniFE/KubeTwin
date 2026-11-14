# frozen_string_literal: true

require "erv"

module KUBETWIN
  # Builds random variables that each draw from their own random stream.
  #
  # A configured distribution carries at most one seed, and ERV falls back
  # to a fixed default seed without one: every pod built from the same
  # configuration, and every MDN distribution, used to draw the same
  # sequence of values. Copies built here get fresh seeds from a seed
  # generator instead, so their draws are independent of one another and
  # still reproducible.
  module IndependentStreams
    SEED_RANGE = 2**31

    module_function

    # A copy of the distribution described by `conf` (an ERV
    # RandomVariable configuration: {distribution:, args:}), seeded from
    # `seeds` (a Random). Only #sample (and #mean, #variance) are
    # guaranteed on the result.
    def distribution(conf, seeds)
      if conf[:distribution].to_s == "mixture"
        # Build the mixture directly: ERV::RandomVariable doesn't pass a seed
        # to MixtureDistribution, whose component selector would otherwise
        # always use ERV's default seed.
        components = conf[:args].map { |component| with_seed(component, seeds) }
        ERV::MixtureDistribution.new(components, seed: seeds.rand(SEED_RANGE))
      else
        ERV::RandomVariable.new(with_seed(conf, seeds))
      end
    end

    def with_seed(conf, seeds)
      conf.merge(args: (conf[:args] || {}).merge(seed: seeds.rand(SEED_RANGE)))
    end
  end
end
