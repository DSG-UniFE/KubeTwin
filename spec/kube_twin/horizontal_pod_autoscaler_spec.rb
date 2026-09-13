# frozen_string_literal: true

require 'minitest_helper'

# HorizontalPodAutoscaler#decide_scaling holds the scale-up/scale-down
# decision that used to live inline inside KSimulation#evaluate_allocation's
# ET_HPA_CONTROL branch (see ksimulation.rb's comment at that call site for
# how the two pieces now fit together). Unlike most of KSimulation, this is
# genuinely pure -- no KubeScheduler, no Pod, no Service -- so it's tested
# directly here rather than through a full simulation run.
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
end
