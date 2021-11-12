# frozen_string_literal: true

require_relative './pod'

module KUBETWIN

  class Node

    attr_reader :resources, :requested_resources, :node_id
    # here define the number of resources
    # we could use the CPU frequency or something else?
    # we defined the resources in containers using th mCPU
    def initialize(node_id, resource)
      @node_id = node_id
      @resources = resource
      @requested_resources = 0.to_f
      @pod_id_list = []
    end

    def assign_resources(pod, resources)
      raise 'Unfeasible resource assignement!'  if @requested_resources + resources > @resources
      @pod_id_list << pod.podId
      @requested_resources += resources
    end

    def remove_resources(pod, resources)
      raise "Pod not assigned to this node" unless @pod_id_list.include? pod.podId
      # free resources
      @requested_resources -= resources
      # remove pod from the list of associated pods 
      @pod_id_list.delete(pod.podId)
    end

  end
end
