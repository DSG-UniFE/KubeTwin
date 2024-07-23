# frozen_string_literal: true

require_relative './pod'
require_relative './logger'
require 'securerandom'

module KUBETWIN
  class Service

    # removing :targetPort for now
    # we are not dealing with TCP/IP here...
    # consider it for future work
    attr_accessor :load_balancing

    attr_reader :serviceName,
                :selector,
                :pods 
                #, :targetPort

    SEED = 12345

    def initialize(serviceName, selector, load_balancing=:random)
      @serviceName = serviceName
      @selector = selector
      @pods = {}
      @pods_probability = {}
      @cumulative_probability = nil
      # round robin pod selector
      @rri = 0
      @load_balancing = load_balancing
      @logger = KUBETWIN::Logging.logger
      srand(SEED)
    end

    # assign a pod to a service
    # label is part of the pod's description
    def assignPod(pod)
      pod_label = pod.label
      @pods[pod_label] ||= []
      raise 'Error! Pod is already present!' if @pods[pod_label].include? pod
      @pods[pod.label] << pod if @selector == pod.label
      @pods[pod_label].each_with_index do |p, i|
        @pods_probability[p] = 1.0 / (@pods[pod_label].length - i)
      end
    end

    def get_pod(label)
     #if rand < 0.26
     if @load_balancing == :random
       pod = get_random_pod(label)
     else
       # this is for round robin
       pod = get_pod_rr(label)
     end
     return pod
    end

    # who calls this method?
    def get_random_pod(label, random: nil)
      if @pods.key? label
        if random
          @pods[label].sample(random)
        else
          rnumber = SecureRandom.rand 
          @pods_probability.each do |p, prob|
            #@logger.info "rnumber: #{rnumber} prob: #{prob}"
            return p if rnumber < prob
            rnumber = SecureRandom.rand 
          end
          #@pods[label].sample
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