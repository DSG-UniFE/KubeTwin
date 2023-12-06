# frozen_string_literal: true

require_relative './pod'

module KUBETWIN

  class Node

    # :type [:mec, cloud] depends on the cluster 
    attr_accessor :ready, :eviction_count
    attr_reader :resources_cpu, :resources_memory, :requested_resources, :node_id, 
     :heartbeat_period, :eviction_threshold, :pods, :pod_id_list, :cluster_id, :type
    # cluster_id should not be here
    # this is a programming error that i introduce to speed-up
    # the development process


    # here define the number of resources
    # we could use the CPU frequency or something else?
    # we defined the resources in containers using th mCPU
    def initialize(node_id, resources_cpu, resources_memory, heartbeat_period, eviction_threshold, cluster_id, type)
      @node_id = node_id
      @resources_cpu = resources_cpu
      @resources_memory = resources_memory
      @requested_resources = {cpu: 0.to_f, memory: 0.to_f}
      @ready = false #initally the node is not ready to accept pods
      @heartbeat_period = heartbeat_period
      @eviction_count = 0
      @eviction_threshold = eviction_threshold
      @cluster_id = cluster_id
      @pods = {}
      @pod_id_list = []
      @type = type
    end

    def startup_node
      @ready = true # the node is ready to accept pods
    end

    def as_json
      {
        "node_id": @node_id,
        "resources_cpu": @resources_cpu,
        "resources_memory": @resources_memory,
        "cluster_id": @cluster_id,
        "pods": @pods,
        "pod_id_list": @pod_id_list,
      }
    end

    def assign_resources(pod, resources_cpu, resources_memory)
      raise 'Node unavailable to accept pods' if @ready == false
      raise 'Unfeasible resource assignement!' if (@requested_resources[:cpu] + resources_cpu > @resources_cpu) && (@requested_resources[:memory] + resources_memory > @resources_memory)
      @pods[pod.pod_id] = pod
      @pod_id_list << pod.pod_id
      @requested_resources[:cpu] += resources_cpu
      @requested_resources[:memory] += resources_memory
    end

    def retrieve_pod(pod_id)
      @pods[pod_id]
    end

    def remove_resources(pod, resources_cpu, resources_memory)
      raise "Pod not assigned to this node" unless @pod_id_list.include? pod.pod_id
      # free resources
      @requested_resources[:cpu] -= resources_cpu
      @requested_resources[:memory] -= resources_memory

      # remove pod from the list of associated pods 
      @pods.delete(pod.pod_id)
      @pod_id_list.delete(pod.pod_id)
    end

    def available_resources_cpu
      @resources_cpu - @requested_resources[:cpu]
    end

    def available_resources_memory
      @resources_memory - @requested_resources[:memory]
    end

  end
end
