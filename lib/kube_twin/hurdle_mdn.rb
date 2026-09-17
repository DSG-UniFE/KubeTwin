# frozen_string_literal: true

require_relative './mdn'
require 'json'

module KUBETWIN
  # Two-stage ("hurdle") service-time model: an empirical, RPS-interpolated
  # probability of the "slow" path gates between two independently trained
  # MDN submodels (fast/normal path, slow/tail path), instead of asking one
  # free mixture to discover and weight a rare mode via gradient descent.
  #
  # Mathematically a hurdle model is just a single Gaussian mixture whose
  # components are the fast submodel's components (weight scaled by
  # 1 - p_slow) concatenated with the slow submodel's components (weight
  # scaled by p_slow) - so get_mixture_params_for_helper below matches MDN's
  # own output contract exactly, and KSimulation#retrieve_mdn_model /
  # Container's sampling path need no changes to support it.
  class HurdleMDN
    def initialize(weights_path:, scaler_path: nil)
      data = JSON.parse(File.read(weights_path))
      @threshold_ms = data['threshold_ms']
      @p_slow_by_level = data['p_slow_by_level'].to_a.map { |k, v| [k.to_i, v.to_f] }.sort.to_h
      @fast = MDN.new(weights_data: data['fast'])
      @slow = MDN.new(weights_data: data['slow'])
    end

    def interp_p_slow(rps)
      levels = @p_slow_by_level.keys
      return @p_slow_by_level[levels.first] if rps <= levels.first
      return @p_slow_by_level[levels.last] if rps >= levels.last

      levels.each_cons(2) do |lo, hi|
        next unless rps >= lo && rps <= hi

        t = (rps - lo).to_f / (hi - lo)
        return @p_slow_by_level[lo] * (1 - t) + @p_slow_by_level[hi] * t
      end
      @p_slow_by_level[levels.last]
    end

    # Same output contract as MDN#get_mixture_params_for_helper: flat
    # [w0, mean0_s, std0, w1, mean1_s, std1, ...] in linear seconds, ready
    # for GaussianMixtureHelper.RawParametersToMixtureArgsFixedWeights.
    def get_mixture_params_for_helper(rps)
      p_slow = interp_p_slow(rps)

      scaled_fast = @fast.get_mixture_params_for_helper(rps).each_slice(3).flat_map do |w, m, s|
        [w * (1.0 - p_slow), m, s]
      end
      scaled_slow = @slow.get_mixture_params_for_helper(rps).each_slice(3).flat_map do |w, m, s|
        [w * p_slow, m, s]
      end

      scaled_fast + scaled_slow
    end
  end
end
