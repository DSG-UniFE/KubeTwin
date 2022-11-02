# frozen_string_literal: true

require_relative './pod'

module KUBETWIN
  class Service

    SEED = 12345

    # removing :targetPort for now
    # we are not dealing with TCP/IP here...
    # consider it for future work
    attr_accessor :load_balancing

    attr_reader :serviceName,
                :selector,
                :pods 
                #, :targetPort

    def initialize(serviceName, selector, load_balancing=:load_balancing)
      @serviceName = serviceName
      @selector = selector
      @pods = {}
      # round robin pod selector
      @rri = 0
      @load_balancing = load_balancing
      @random = Random.new(SEED)
    end

    # assign a pod to a service
    # label is part of the pod's description
    def assignPod(pod)
      pod_label = pod.label
      @pods[pod_label] ||= []
      raise 'Error! Pod is already present!' if @pods[pod_label].include? pod
      @pods[pod.label] << pod if @selector == pod.label
    end

    def get_pod(label)
      return get_random_pod(label, random: @random)
     if @load_balancing == :random
       pod = get_random_pod(label)
     elsif 
       # this is for round robin
       pod = get_pod_rr(label)
     end
     return pod
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

    def get_pod_rr(label)
      if @pods.key? label
        index = @rri
        # update rri
        @rri = @pods.length > 0 ? (@rri + 1) % @pods[label].length : 0
        @pods[label][index]
      end
    end

    def delete_pod(label, pod)
      @rri = 0
      @pods[label].delete pod
    end

  end
end