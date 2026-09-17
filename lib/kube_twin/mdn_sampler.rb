# frozen_string_literal: true

module KUBETWIN
  # Samples directly in log-space from a Gaussian-mixture MDN's own
  # parameters (pi, mu_log, sigma_log - log-seconds), instead of moment-
  # matching each component into an equivalent linear-space Gaussian and
  # handing it to ERV::RandomVariable. A log-normal sample can't go
  # negative, so there's nothing to clip - the old linear-moment-matched
  # path clipped negative draws to a 1e-6s floor, which for a
  # wide-in-linear-space component silently redirected a large chunk of
  # its probability mass to "effectively zero" instead of its true shape.
  #
  # Built once per distinct RPS value (same caching KSimulation#retrieve_mdn_model
  # already did) and then sampled many times per request - cost per sample here
  # is a handful of Float ops, no Torch calls, comparable to or cheaper than the
  # generic ERV::RandomVariable mixture it replaces.
  class MDNSampler
    def initialize(pi:, mu_log:, sigma_log:)
      @pi = pi
      @mu_log = mu_log
      @sigma_log = sigma_log
    end

    def sample
      k = sample_component
      z = box_muller
      value = Math.exp(@mu_log[k] + (@sigma_log[k] * z))
      [1e-6, value].max
    end

    private

    def sample_component
      r = rand
      cum = 0.0
      @pi.each_with_index do |w, i|
        cum += w
        return i if r <= cum
      end
      @pi.length - 1 # floating-point rounding fallback: weights summed just under r
    end

    def box_muller
      u1 = [rand, 1e-12].max # guard against log(0) => -Infinity
      u2 = rand
      Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    end
  end
end
