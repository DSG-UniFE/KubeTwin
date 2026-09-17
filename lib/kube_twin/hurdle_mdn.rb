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
    # Matches Python training's `sigma = elu(raw) + 1.0 + SIGMA_MIN` (see
    # mdn_service_time_predictor.py). MDN#elu is a linear stand-in
    # (`x + 1.0001`), not a real ELU - harmless when sigma's raw
    # pre-activation is near zero, but for a very negative pre-activation
    # (meaning the network is confident and wants a *small* sigma) it
    # returns a large-magnitude negative number instead of saturating near
    # zero like a real ELU. That negative value gets squared during
    # log-normal -> linear-Gaussian moment matching
    # (get_mixture_params_for_helper's `sigma2 = sigma * sigma`), which can
    # blow a supposedly-tight component up into a std of millions of
    # seconds. Recompute sigma correctly here so hurdle sampling doesn't
    # inherit that bug - scoped to this class alone, MDN itself (and every
    # config that isn't type:"hurdle") is untouched.
    SIGMA_MIN = 1e-4

    def initialize(weights_path:, scaler_path: nil)
      data = JSON.parse(File.read(weights_path))
      @threshold_ms = data['threshold_ms']
      @p_slow_by_level = data['p_slow_by_level'].to_a.map { |k, v| [k.to_i, v.to_f] }.sort.to_h
      @fast = MDN.new(weights_data: data['fast'])
      @slow = MDN.new(weights_data: data['slow'])
    end

    def real_elu(x)
      x.positive? ? x : (Math.exp(x) - 1.0)
    end

    # Linear-space [weight, mean_s, std_s, ...] for one submodel, with sigma
    # recomputed via a real ELU instead of MDN's linear-shift approximation.
    def corrected_mixture_params(mdn, rps)
      params = mdn.get_mixture_params_sec(rps) # { pi:, mu_log: (seconds), sigma_log: (buggy-elu, scaled) }
      log_pt_std = mdn.scaler['log_pt_std'].abs

      params[:pi].each_with_index.map do |w, i|
        mu_log = params[:mu_log][i]
        # Undo MDN#elu's `x + 1.0001` and log_pt_std scaling to recover the
        # network's raw sigma-head pre-activation, then apply a real ELU.
        buggy_sigma_unscaled = params[:sigma_log][i] / log_pt_std
        raw_preactivation = buggy_sigma_unscaled - 1.0001
        sigma_unscaled = real_elu(raw_preactivation) + 1.0 + SIGMA_MIN
        sigma_log = sigma_unscaled * log_pt_std

        sigma2 = sigma_log * sigma_log
        mean_lin = Math.exp(mu_log + sigma2 / 2.0)
        var_lin = (Math.exp(sigma2) - 1.0) * Math.exp((2.0 * mu_log) + sigma2)
        [w, mean_lin, Math.sqrt(var_lin)]
      end.flatten
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

      scaled_fast = corrected_mixture_params(@fast, rps).each_slice(3).flat_map do |w, m, s|
        [w * (1.0 - p_slow), m, s]
      end
      scaled_slow = corrected_mixture_params(@slow, rps).each_slice(3).flat_map do |w, m, s|
        [w * p_slow, m, s]
      end

      scaled_fast + scaled_slow
    end
  end
end
