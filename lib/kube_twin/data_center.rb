# frozen_string_literal: true

require 'forwardable'

module KUBETWIN

  class DataCenter
    extend Forwardable

    def_delegator :@vms, :has_key?, :has_vms_of_type?

    attr_reader :dcid, :location_id

    def initialize(id:, location_id:, name:, type:, **opts)
      @dcid          = id
      @location_id   = location_id
      @vms           = {}
      @vm_type_count = {}
      @name          = name
      @type          = type
      raise ArgumentError, "Unsupported type!" unless [ :private, :public ].include?(@type)
      @availability_check_proc = opts[:maximum_vm_capacity]
    end

    # returns false in case no more VMs can be allocated
    def add_vm(vm, component_name)
      @vms[component_name] ||= []
      @vm_type_count[vm.size] ||= 0

      raise 'Error! VM is already present!' if @vms[component_name].include? vm

      # defer availablility check to user specified procedure
      if @availability_check_proc
        return false unless @availability_check_proc.call(@vm_type_count)
      end

      # allocate VM
      @vms[component_name] << vm
      @vm_type_count[vm.size] += 1
    end

    def remove_vm(vm, component_name)
      if @vms.has_key? component_name and @vms[component_name].include? vm
        raise 'Error! Inconsistent number of VMs!' unless @vm_type_count[vm.size] >= 1
        @vm_type_count[vm.size] += 1
        @vms.delete(vm)
      end
    end

    # returns nil in case no VM for component component_name is running
    def get_random_vm(component_name, random: nil)
      if @vms.has_key? component_name
        if random
          @vms[component_name].sample(random: random)
        else
          @vms[component_name].sample
        end
      end
    end

    def to_s
      "Data center #{@dcid}, with VMs:" +
        @vms.inject("") {|s,(k,v)| s += " (#{k}: #{v.size})" }
    end

    def private?
      @type == :private
    end

    def public?
      @type == :public
    end

  end

end
