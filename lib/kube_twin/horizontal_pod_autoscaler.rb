# frozen_string_literal: true

#require_relative './pod'

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

    
  end
end
