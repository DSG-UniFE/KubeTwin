# frozen_string_literal: true

require_relative './mdn_sampler'
require 'json'

module KUBETWIN
  # Alternative to MDN for a service whose distribution isn't multi-modal:
  # a single log-normal per RPS level, fit by direct MLE (mean/std of log
  # processing time) instead of a neural network, linearly interpolated
  # between the trained levels at simulation time. Same output contract as
  # MDN/HurdleMDN (#build_sampler returns an MDNSampler) - a single
  # log-normal is just a one-component "mixture" (pi = [1.0]), so no new
  # sampling code is needed, only parameter lookup.
  class LogNormalMDN
    def initialize(weights_path:, scaler_path: nil)
      data = JSON.parse(File.read(weights_path))
      @levels = data['levels'].to_a.map { |k, v| [k.to_i, v] }.sort.to_h
    end

    def interp(rps)
      levels = @levels.keys
      return @levels[levels.first] if rps <= levels.first
      return @levels[levels.last] if rps >= levels.last

      levels.each_cons(2) do |lo, hi|
        next unless rps >= lo && rps <= hi

        t = (rps - lo).to_f / (hi - lo)
        mu = (@levels[lo]['mu_log'] * (1 - t)) + (@levels[hi]['mu_log'] * t)
        sigma = (@levels[lo]['sigma_log'] * (1 - t)) + (@levels[hi]['sigma_log'] * t)
        return { 'mu_log' => mu, 'sigma_log' => sigma }
      end
      @levels[levels.last]
    end

    def build_sampler(rps)
      params = interp(rps)
      MDNSampler.new(pi: [1.0], mu_log: [params['mu_log']], sigma_log: [params['sigma_log']])
    end
  end
end
