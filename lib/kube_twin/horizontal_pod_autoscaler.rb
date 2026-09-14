# frozen_string_literal: true

module KUBETWIN
  # just a simple class to model of an horizontal_pod_autoscaler
  # name corresponds to selector / label
  # the pod name

  class HorizontalPodAutoscaler
    attr_reader :name,
      :min_replicas,
      :max_replicas,
      :target_processing_percentage,
      :period_seconds

    # name and selector have the same value here
    def initialize(name, minReplicas, maxReplicas,
      target_processing_percentage,
      periodSeconds)
      @name = name
      @min_replicas = minReplicas
      @max_replicas = maxReplicas
      @target_processing_percentage = target_processing_percentage
      @period_seconds = periodSeconds
    end

    # The Kubernetes-HPA-inspired scale-up/scale-down decision, extracted
    # out of KSimulation#evaluate_allocation's ET_HPA_CONTROL branch (see
    # https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/).
    # This is deliberately just the *decision*: given how many replicas
    # exist now and the observed vs. desired value of the scaled metric,
    # what should the replica count become. Actually creating/destroying
    # pods needs KubeScheduler, Pod, and Service, so that mechanical part
    # stays in KSimulation; this method has no dependency on any of it and
    # is unit-tested directly (spec/kube_twin/horizontal_pod_autoscaler_spec.rb).
    #
    # Returns a Hash:
    #   { action: :none, to_scale: 0, target_replicas: current_replicas }
    #   { action: :scale_up,   to_scale: <pods to add>,    target_replicas: <desired, UNCLAMPED> }
    #   { action: :scale_down, to_scale: <pods to remove>, target_replicas: <current_replicas - to_scale> }
    #
    # Two quirks are preserved exactly as they were in the original inline
    # code, rather than being fixed here (a refactor should not silently
    # change behavior -- see the caller in ksimulation.rb for how each is
    # handled):
    #   1. On scale_up, to_scale (how many pods actually get created) is
    #      clamped at max_replicas, but target_replicas is the *unclamped*
    #      desired replica count -- so the replica_set's recorded replica
    #      count can end up above max_replicas even though no more than
    #      max_replicas pods are ever actually created.
    #   2. On scale_down, nothing here (or in the original code) updates
    #      the replica_set's recorded replica count at all -- only the
    #      caller's bookkeeping of *actual* pods changes.
    #   3. Scaling down only happens if the desired replica count is
    #      strictly greater than min_replicas (not >=) -- landing exactly
    #      on min_replicas leaves the replica count untouched, same as
    #      being within the tolerance range.
    def decide_scaling(current_replicas, current_metric, desired_metric, tolerance_range: 0.90..1.10)
      scaling_ratio = current_metric / desired_metric

      return {action: :none, to_scale: 0, target_replicas: current_replicas} if tolerance_range === scaling_ratio

      desired_replicas = (current_replicas * scaling_ratio).ceil

      if desired_replicas > current_replicas
        to_scale = (desired_replicas <= max_replicas) ? (desired_replicas - current_replicas) : (max_replicas - current_replicas)
        {action: :scale_up, to_scale: to_scale, target_replicas: desired_replicas}
      else
        to_scale = (desired_replicas > min_replicas) ? (current_replicas - desired_replicas).abs : 0
        if to_scale.zero?
          {action: :none, to_scale: 0, target_replicas: current_replicas}
        else
          {action: :scale_down, to_scale: to_scale, target_replicas: current_replicas - to_scale}
        end
      end
    end

    # The *desired* (target) side of the HPA metric -- extracted out of
    # the same ET_HPA_CONTROL branch as #decide_scaling, one level
    # earlier. service_time_rv only needs to respond to #sample (any
    # ERV::RandomVariable, or a fake in tests); this method never touches
    # Pod or Container itself -- KSimulation still does the (impure, one
    # random pod's) `s.pods[s.selector].sample.container.service_time`
    # lookup and hands the resulting RV in here.
    #
    # sample_count: 101 matches the original inline code's `0.upto(100)`
    # (that's 101 samples, not 100) -- a crude rejection-sampling-free
    # truncation of the RV's PDF by averaging, preserved verbatim rather
    # than "fixed" to a rounder number.
    def desired_metric(service_time_rv, sample_count: 101)
      samples = Array.new(sample_count) { service_time_rv.sample }
      average_service_time = samples.sum / samples.length.to_f
      target_processing_percentage * average_service_time
    end

    # The *observed/current* side of the HPA metric -- the other half of
    # the same branch. pod_metrics is a plain array of
    # [served_request, total_queue_processing_time] pairs, one per pod
    # currently backing this HPA's scale target (including pods that
    # haven't served anything yet) -- not Pod/Container objects -- so
    # this has no dependency on KSimulation, Pod, or Container either.
    # Resetting each container's metrics (Container#reset_metrics) is a
    # mutation and stays in KSimulation, which reads served_request/
    # total_queue_processing_time before resetting and passes the
    # snapshot in here (see the ET_HPA_CONTROL branch).
    #
    # Preserves two quirks from the original inline loop exactly:
    #   1. A pod with served_request == 0 contributes 0 to the running
    #      sum (avoiding a division by zero) but is still counted in the
    #      denominator -- so a scale target with many freshly-created,
    #      not-yet-serving pods reports a LOWER current_metric than the
    #      busy pods' own average would suggest, not an error and not
    #      excluded from the count.
    #   2. An empty pod_metrics array divides 0 by 0.0, i.e. returns NaN,
    #      same as the original code -- the caller has always checked
    #      pods == 0 and skipped the rest of the control cycle (so a NaN
    #      current_metric is computed but never actually used); that
    #      guard is the caller's responsibility, not this method's.
    def average_processing_metric(pod_metrics)
      sum = pod_metrics.sum do |served_request, total_queue_processing_time|
        served_request.zero? ? 0.0 : total_queue_processing_time / served_request
      end
      sum / pod_metrics.length.to_f
    end
  end
end
