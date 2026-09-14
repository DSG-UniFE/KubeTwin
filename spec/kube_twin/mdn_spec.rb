# frozen_string_literal: true

require 'minitest_helper'

# MDN's forward()/sample_batch()/get_mixture_params() all need a real Torch
# weights fixture to exercise (matching the hardcoded 1 -> 128 -> 128 -> 128
# -> 5 architecture), and forward()/sample_batch() are RNG-sampled on top of
# that, so their outputs aren't even deterministic -- untested here, and
# flagged on the roadmap as needing a real fixture, which is a separate,
# bigger effort. .normalize_rps and .log_normal_mixture_to_linear are the
# pure-math pieces extracted out precisely so they can be tested without any
# of that: no Torch, no instance state, no RNG. See mdn.rb for the full doc
# comments on both.
describe KUBETWIN::MDN do
  describe '.normalize_rps' do
    it 'linearly maps rps into [0, 1] against the scaler min/max' do
      scaler = { 'rps_min' => 10.0, 'rps_max' => 90.0 }

      _(KUBETWIN::MDN.normalize_rps(10, scaler)).must_equal 0.0
      _(KUBETWIN::MDN.normalize_rps(90, scaler)).must_equal 1.0
      _(KUBETWIN::MDN.normalize_rps(50, scaler)).must_equal 0.5
    end

    it 'extrapolates outside [rps_min, rps_max] rather than clamping' do
      scaler = { 'rps_min' => 10.0, 'rps_max' => 90.0 }

      _(KUBETWIN::MDN.normalize_rps(0, scaler)).must_equal(-0.125)
      _(KUBETWIN::MDN.normalize_rps(100, scaler)).must_equal 1.125
    end

    it 'returns 0.0 for a degenerate scaler where rps_max - rps_min < 1e-8' do
      scaler = { 'rps_min' => 5.0, 'rps_max' => 5.0 }

      _(KUBETWIN::MDN.normalize_rps(42, scaler)).must_equal 0.0
    end
  end

  describe '.log_normal_mixture_to_linear' do
    it 'converts a degenerate (sigma=0) component to its exact mean with zero std' do
      # log-normal with mu=0, sigma=0 is a point mass at exp(0) = 1
      result = KUBETWIN::MDN.log_normal_mixture_to_linear([1.0], [0.0], [0.0])

      _(result).must_equal [1.0, 1.0, 0.0]
    end

    it 'flattens multiple components into [pi0, mean0, std0, pi1, mean1, std1, ...] in order' do
      result = KUBETWIN::MDN.log_normal_mixture_to_linear([0.6, 0.4], [0.0, 0.0], [0.0, 0.0])

      _(result).must_equal [0.6, 1.0, 0.0, 0.4, 1.0, 0.0]
    end

    it 'computes the standard log-normal mean and variance formulas for a non-degenerate component' do
      pi = [1.0]
      mu = [0.0]
      sigma = [1.0]

      result = KUBETWIN::MDN.log_normal_mixture_to_linear(pi, mu, sigma)

      expected_mean = Math.exp(0.0 + (1.0 / 2.0)) # exp(mu + sigma^2/2)
      expected_var = (Math.exp(1.0) - 1.0) * Math.exp(1.0) # (exp(sigma^2)-1) * exp(2*mu + sigma^2)
      expected_std = Math.sqrt(expected_var)

      _(result[0]).must_equal 1.0
      _(result[1]).must_be_close_to expected_mean
      _(result[2]).must_be_close_to expected_std
    end
  end
end
