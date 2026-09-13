# frozen_string_literal: true

require 'minitest_helper'

# HorizontalPodAutoscaler holds the three pieces of ET_HPA_CONTROL logic
# that used to live inline inside KSimulation#evaluate_allocation, pulled
# out one at a time (see ksimulation.rb's comments at each call site for
# how they fit back together): #desired_metric (the target side of the
# metric), #average_processing_metric (the observed side), and
# #decide_scaling (the scale-up/scale-down decision itself, given both).
# All three are genuinely pure -- no KubeScheduler, no Pod, no Service, no
# Container -- so they're tested directly here rather than only through a
# full simulation run.
describe KUBETWIN::HorizontalPodAutoscaler do
  def build_hpa(min_replicas: 2, max_replicas: 10)
    KUBETWIN::HorizontalPodAutoscaler.new('svc', min_replicas, max_replicas, 0.7, 30)
  end

  describe '#decide_scaling' do
    it 'does nothing when the observed metric is within the tolerance range' do
      hpa = build_hpa
      decision = hpa.decide_scaling(5, 1.0, 1.0) # ratio 1.0

      _(decision).must_equal(action: :none, to_scale: 0, target_replicas: 5)
    end

    it 'treats the tolerance range as inclusive at both boundaries (0.90 and 1.10)' do
      hpa = build_hpa

      _(hpa.decide_scaling(5, 0.9, 1.0)[:action]).must_equal :none
      _(hpa.decide_scaling(5, 1.1, 1.0)[:action]).must_equal :none
    end

    it 'scales up when the metric is above tolerance, when there is headroom under max_replicas' do
      hpa = build_hpa(max_replicas: 10)
      decision = hpa.decide_scaling(5, 1.11, 1.0) # ratio 1.11 -> ceil(5 * 1.11) = 6

      _(decision).must_equal(action: :scale_up, to_scale: 1, target_replicas: 6)
    end

    it 'clamps the number of pods created at max_replicas, but NOT the recorded target_replicas' do
      # this documents a real quirk in the original code, not a design
      # choice made during extraction: the caller in ksimulation.rb calls
      # rs.set_replicas(target_replicas) with this *unclamped* value, so a
      # replica_set's recorded replica count can end up above
      # max_replicas even though at most max_replicas pods are ever
      # actually created (to_scale is clamped here).
      hpa = build_hpa(max_replicas: 6)
      decision = hpa.decide_scaling(5, 3.0, 1.0) # ratio 3.0 -> ceil(5 * 3.0) = 15

      _(decision[:action]).must_equal :scale_up
      _(decision[:to_scale]).must_equal 1 # clamped: max_replicas(6) - current_replicas(5)
      _(decision[:target_replicas]).must_equal 15 # NOT clamped
    end

    it 'scales down when the metric is below tolerance and the desired count is above min_replicas' do
      hpa = build_hpa(min_replicas: 2)
      decision = hpa.decide_scaling(5, 0.5, 1.0) # ratio 0.5 -> ceil(5 * 0.5) = 3

      _(decision).must_equal(action: :scale_down, to_scale: 2, target_replicas: 3)
    end

    it 'does NOT scale down when the desired count lands exactly on min_replicas' do
      # desired_replicas > min_replicas is a strict inequality in the
      # original code -- landing exactly on min_replicas is treated the
      # same as being within tolerance (no change), not "scale down to
      # min_replicas".
      hpa = build_hpa(min_replicas: 2)
      decision = hpa.decide_scaling(5, 0.4, 1.0) # ratio 0.4 -> ceil(5 * 0.4) = 2 == min_replicas

      _(decision).must_equal(action: :none, to_scale: 0, target_replicas: 5)
    end

    it 'does NOT scale down (or clamp to min_replicas) when the desired count is below min_replicas either' do
      # a very low ratio that would put desired_replicas under
      # min_replicas doesn't clamp the replica count down to
      # min_replicas -- it just does nothing, same as the boundary case
      # above. Pinning this because it's easy to assume the opposite.
      hpa = build_hpa(min_replicas: 2)
      decision = hpa.decide_scaling(5, 0.1, 1.0) # ratio 0.1 -> ceil(5 * 0.1) = 1 < min_replicas

      _(decision).must_equal(action: :none, to_scale: 0, target_replicas: 5)
    end

    it 'accepts a custom tolerance_range' do
      hpa = build_hpa
      decision = hpa.decide_scaling(5, 1.05, 1.0, tolerance_range: 0.99..1.01)

      _(decision[:action]).must_equal :scale_up
    end
  end

  describe '#desired_metric' do
    it 'is target_processing_percentage times the average of sample_count samples from the RV' do
      hpa = KUBETWIN::HorizontalPodAutoscaler.new('svc', 2, 10, 0.5, 30)
      # a fake RV that alternates 1.0 / 3.0 -- average is always 2.0
      # regardless of how many samples are drawn, as long as it's even
      values = [1.0, 3.0].cycle
      service_time_rv = Object.new
      service_time_rv.define_singleton_method(:sample) { values.next }

      result = hpa.desired_metric(service_time_rv, sample_count: 10)
      _(result).must_equal 1.0 # 0.5 * 2.0
    end

    it 'defaults sample_count to 101 (matches the original 0.upto(100))' do
      hpa = KUBETWIN::HorizontalPodAutoscaler.new('svc', 2, 10, 1.0, 30)
      calls = 0
      service_time_rv = Object.new
      service_time_rv.define_singleton_method(:sample) { calls += 1; 1.0 }

      hpa.desired_metric(service_time_rv)
      _(calls).must_equal 101
    end
  end

  describe '#average_processing_metric' do
    it 'averages per-request processing time across pods, using total pod count as the denominator' do
      hpa = build_hpa
      # pod A: 10 total / 5 served = 2.0 per request; pod B: 9 total / 3 served = 3.0
      pod_metrics = [[5, 10.0], [3, 9.0]]

      result = hpa.average_processing_metric(pod_metrics)
      _(result).must_equal 2.5 # (2.0 + 3.0) / 2 pods
    end

    it 'counts a zero-served pod in the denominator but contributes 0 to the sum (not excluded, not division by zero)' do
      hpa = build_hpa
      # pod A: 10 total / 5 served = 2.0 per request; pod B: never served anything
      pod_metrics = [[5, 10.0], [0, 0.0]]

      result = hpa.average_processing_metric(pod_metrics)
      _(result).must_equal 1.0 # (2.0 + 0) / 2 pods, not 2.0 / 1 pod
    end

    it 'returns NaN for an empty pod_metrics array, matching the original 0 / 0.0 -- callers must guard pods == 0 themselves' do
      hpa = build_hpa
      result = hpa.average_processing_metric([])
      _(result.nan?).must_equal true
    end
  end
end
