# frozen_string_literal: true

require 'forwardable'

module KUBETWIN

  class Cluster
    extend Forwardable

    def_delegator :@vms, :has_key?, :has_vms_of_type?

    attr_reader :cluster_id, :location_id, :node_number, 
                :nodes, :name, :node_resources_cpu, :node_resources_memory, :type,
                :fixed_hourly_cost_cpu, :fixed_hourly_cost_memory

    # type is mec or cloud, something similar to what we implemented
    # in Phileas
    def initialize(id:, fixed_hourly_cost_cpu:, fixed_hourly_cost_memory:, location_id:, name:, type:,
                   node_number:, node_resources_cpu:, node_resources_memory:, **opts)
      @cluster_id    = id
      @location_id   = location_id
      @nodes         = {}
      @name          = name
      @type          = type
      @node_number   = node_number
      @node_resources_cpu = node_resources_cpu
      @node_resources_memory = node_resources_memory
      @fixed_hourly_cost_cpu   = fixed_hourly_cost_cpu
      @fixed_hourly_cost_memory = fixed_hourly_cost_memory
      raise ArgumentError, "Unsupported cluster's type!" unless [ :mec, :cloud ].include?(@type)
    end

    # returns false in case no more nodes can be allocated
    # node can run multiples pods... so the node's identifier
    # should be its id or something similar
    # we could change this during development
    def add_node(node)
      # @nodes[component_name] ||= []
      # here we should implement something similar
      # @vm_type_count[vm.size] ||= 0

      # raise exception if assignement is wrong
      raise 'Error! Node is already present!' if @nodes.include? node.node_id
      # do we need to use the following?
      # register node into cluster
      @nodes[node.node_id] = node
    end

    def remove_node(node)
        raise 'Error! Node not allocated in this cluster' unless @nodes.include? node.node_id
        @nodes.delete(node.node_id)
    end

    def edge?
      @type == :mec
    end

    def cloud?
      @type == :cloud
    end
  end

end
