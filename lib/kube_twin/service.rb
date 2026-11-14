# frozen_string_literal: true

module KUBETWIN
  class Service
    # removing :targetPort for now
    # we are not dealing with TCP/IP here...
    # consider it for future work
    attr_accessor :load_balancing

    attr_reader :service_name,
      :selector,
      :pods,
      :cluster_weights

    # , :targetPort

    SEED = 45_678

    # @param random [Random, nil] the generator :random load balancing
    #   draws from; nil means Ruby's global generator.
    def initialize(service_name, selector, load_balancing = :random, random: nil)
      @service_name = service_name
      @selector = selector
      @random = random
      @pods = {}
      # round robin pod selector
      @rri = 0
      @load_balancing = load_balancing
      # srand(SEED)
    end

    # assign a pod to a service
    # label is part of the pod's description
    def assignPod(pod)
      pod_label = pod.label
      @pods[pod_label] ||= []
      raise "Error! Pod is already present!" if @pods[pod_label].include? pod

      @pods_by_cluster = nil
      @pods[pod.label] << pod if @selector == pod.label
    end

    # Routes requests among clusters in proportion to `weights` (cluster id
    # => non-negative number), then to a random pod within the chosen
    # cluster. Clusters without a weight get none. If no cluster with a
    # positive weight has pods, requests go to a random pod, as without
    # weights. nil (or {}) restores the configured load balancing.
    def cluster_weights=(weights)
      @cluster_weights = (weights.nil? || weights.empty?) ? nil : weights.dup.freeze
    end

    def get_pod(label)
      return get_weighted_pod(label) if @cluster_weights

      if @load_balancing == :random
        pod = get_random_pod(label, random: @random)
      elsif (pod = get_pod_rr(label))
        # this is for round robin
      end
      pod
    end

    # who calls this method?
    def get_random_pod(label, random: nil)
      return unless @pods.key? label

      if random
        @pods[label].sample(random: random)
      else
        @pods[label].sample
      end
    end

    def get_pod_rr(label)
      return unless @pods.key? label

      index = @rri
      # update rri
      @rri = (@pods.length > 0) ? (@rri + 1) % @pods[label].length : 0
      @pods[label][index]
    end

    def delete_pod(label, pod)
      @rri = 0
      @pods_by_cluster = nil
      @pods[label].delete pod
    end

    private

    def get_weighted_pod(label)
      pods = @pods[label]
      return if pods.nil? || pods.empty?

      @pods_by_cluster ||= pods.group_by { |pod| pod.node.cluster_id }
      clusters = @pods_by_cluster.keys.select { |c| @cluster_weights.fetch(c, 0).positive? }
      return get_random_pod(label, random: @random) if clusters.empty?

      draw = (@random ? @random.rand : rand) * clusters.sum { |c| @cluster_weights[c] }
      cluster = clusters.find { |c| (draw -= @cluster_weights[c]) < 0 } || clusters.last
      candidates = @pods_by_cluster[cluster]
      @random ? candidates.sample(random: @random) : candidates.sample
    end
  end
end
