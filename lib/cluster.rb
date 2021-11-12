# frozen_string_literal: true

require 'forwardable'

module KUBETWIN

  class Cluster
    extend Forwardable

    def_delegator :@vms, :has_key?, :has_vms_of_type?

    attr_reader :dcid, :location_id

    # type is mec or cloud, something similar to what we implemented
    # in Phileas
    def initialize(id:, location_id:, name:, type:, **opts)
      @cluster_id    = id
      @location_id   = location_id
      @nodes           = {}
      @name          = name
      @type          = type
      raise ArgumentError, "Unsupported cluster's type!" unless [ :mec, :cloud ].include?(@type)
    end

    # returns false in case no more nodes can be allocated
    # node can run multiples pods... so the node's identifier
    # should be its id or something similar
    # we could change this during development
    def add_node(node)
      @nodes[component_name] ||= []
      @vm_type_count[vm.size] ||= 0

      # raise exception if assignement is wrong
      raise 'Error! Node is already present!' if @nodes.include? node.node_id

      # allocate register node into cluster
      @nodes[node.node_id] << node
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
