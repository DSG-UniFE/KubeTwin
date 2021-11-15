# frozen_string_literal: true

require './pod'

module KUBETWIN
  class Service

    # removing :targetPort for now
    # we are not dealing with TCP/IP here...
    # consider it for future work
    attr_reader :serviceName, :selector #, :targetPort

    def initialize(serviceName, selector)
      @serviceName = serviceName
      @selector = selector
      @pods = {}
    end

    # assign a pod to a service
    # label is part of the pod's description
    def assignPod(pod)
      @pods[pod.label] ||= []
      raise 'Error! Pod is already present!' if @pods[label].include? pod

      # check
      @pods[pod.label] << pod if @selector == pod.label
    end

    # who calls this method?
    def get_random_pod(label, random: nil)
      if @pods.key? label
        if random
          @pods[label].sample(random: random)
        else
          @pods[label].sample
        end
      end
    end
  end
end
