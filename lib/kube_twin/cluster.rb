# frozen_string_literal: true

require 'forwardable'

module KUBETWIN

  class Cluster
    extend Forwardable

    def_delegator :@vms, :has_key?, :has_vms_of_type?

    attr_reader :cluster_id, :location_id, :node_number, 
                :nodes, :name, :node_resources, :type,
                :hourly_cost

    # type is mec or cloud, something similar to what we implemented
    # in Phileas
    def initialize(id:, hourly_cost:, location_id:, name:, type:,
                   node_number:, node_resources:, **opts)
      @cluster_id    = id
      @location_id   = location_id
      @nodes           = {}
      @name          = name
      @type          = type
      @node_number   = node_number
      @node_resources = node_resources
      @hourly_cost   = hourly_cost
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

    def remove_vm(node)
        raise 'Error! Node not allocated in this cluster' unless @nodes.include? node.node_id
        @vm_type_count[vm.size] += 1
        @vms.delete(vm)
    end

    def edge?
      @type == :mec
    end

    def cloud?
      @type == :cloud
    end
  end

end
