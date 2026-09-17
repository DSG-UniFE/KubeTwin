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
  # scaled by p_slow) - so build_sampler below matches MDN's own output
  # contract exactly (an object with #sample), and
  # KSimulation#retrieve_mdn_model / Container's sampling path need no
  # changes to support it.
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

    # Same output contract as MDN#build_sampler: an object with #sample,
    # built by concatenating the fast and slow submodels' own log-space
    # components with their pi arrays rescaled by (1 - p_slow) / p_slow.
    def build_sampler(rps)
      p_slow = interp_p_slow(rps)
      fast = @fast.get_mixture_params_sec(rps)
      slow = @slow.get_mixture_params_sec(rps)

      pi = fast[:pi].map { |w| w * (1.0 - p_slow) } + slow[:pi].map { |w| w * p_slow }
      mu_log = fast[:mu_log] + slow[:mu_log]
      sigma_log = fast[:sigma_log] + slow[:sigma_log]

      MDNSampler.new(pi: pi, mu_log: mu_log, sigma_log: sigma_log)
    end
  end
end
