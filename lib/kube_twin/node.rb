# frozen_string_literal: true

require_relative './pod'

module KUBETWIN

  class Node

    # :type [:mec, cloud] depends on the cluster 
    attr_reader :resources, :requested_resources, :node_id, 
     :pod_id_list, :cluster_id, :type
    # cluster_id should not be here
    # this is a programming error that i introduce to speed-up
    # the development process


    # here define the number of resources
    # we could use the CPU frequency or something else?
    # we defined the resources in containers using th mCPU
    def initialize(node_id, resources, cluster_id, type)
      @node_id = node_id
      @resources = resources
      @requested_resources = 0.to_f
      @cluster_id = cluster_id
      @pod_id_list = []
      @type = type
    end

    def assign_resources(pod, resources)
      raise 'Unfeasible resource assignement!' if @requested_resources + resources > @resources
      @pod_id_list << pod.pod_id
      @requested_resources += resources
    end

    def remove_resources(pod, resources)
      raise "Pod not assigned to this node" unless @pod_id_list.include? pod.pod_id
      # free resources
      @requested_resources -= resources
      # remove pod from the list of associated pods 
      @pod_id_list.delete(pod.pod_id)
    end

    def available_resources
      @resources - @requested_resources
    end

  end
end
