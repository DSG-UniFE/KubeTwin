# frozen_string_literal: true

require 'erv'

module KUBETWIN
  class LatencyManager
    def initialize(latency_models, seed: nil)
      # create rng for reproducible seeding
      rng = seed ? Random.new(seed) : Random.new

      # here we build a (strictly upper triangular) matrix of random variables
      # that represent the communication latency models between the different
      # locations
      @latency_models_matrix = latency_models.map do |lms_conf|
        lms_conf.map do |orig_rv_conf|
          # rv_conf = orig_rv_conf.dup
          # rv_conf[:args] = orig_rv_conf[:args].merge(seed: rng.rand(100_000_000))
          ERV::RandomVariable.new(orig_rv_conf)
        end
      end

      # should we turn @latency_models_matrix from a (strictly upper)
      # triangular to a full matrix, for convenience? probably not. it would
      # require more memory and: 1) ruby is ***very*** memory hungry already,
      # 2) ruby's performance is very sensitive to memory usage.

      # precalculate average latencies
      @average_latency_matrix = @latency_models_matrix.map do |lms|
        lms.map{|x| x.mean }
      end

      # latency in the same location is implemented as a truncated gaussian
      # with mean = 20ms, sd = 5ms, and a = 2ms
      @same_location_latency = ERV::RandomVariable.new(distribution: :gaussian, args: { mean: 20E-3, sd: 5E-3, seed: rng.rand(100_000_000) })
    end

    def sample_latency_between(loc1, loc2)
      if loc1 == loc2
        # rejection sampling to implement (crudely) PDF truncation
        while (lat = @same_location_latency.next) < 2E-3; end
        lat
      else
        l1, l2 = loc1 < loc2 ? [ loc1, loc2 ] : [ loc2, loc1 ]

        # since we use a compact representation for @latency_models_matrix, the
        # indexes become l1 and (l2-l1-1)
        # rejection sampling to implement (crudely) PDF truncation to positive numbers
        while (lat = @latency_models_matrix[l1][l2-l1-1].next) <= 0.0; end
        lat / 1000.0 # conversion from milliseconds to seconds
      end
    end

    def average_latency_between(loc1, loc2)
      # the results returned by this method are not entirely accurate, because
      # rejection sampling changes the shape of the PDF. see, e.g.,
      # https://stackoverflow.com/questions/47933019/how-to-properly-sample-truncated-distributions
      # still, it is an acceptable approximation
      if loc1 == loc2
        @same_location_latency.mean
      else
        l1, l2 = loc1 < loc2 ? [ loc1, loc2 ] : [ loc2, loc1 ]

        # since we use a compact representation for @average_latency_between, the
        # indexes become l1 and (l2-l1-1)
        mean = @average_latency_between[l1][l2-l1-1]
        mean / 1000.0 # conversion from milliseconds to seconds
      end
    end
  end
end
