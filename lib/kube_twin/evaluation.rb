# frozen_string_literal: true

require_relative './logger'

module KUBETWIN
  class Evaluator

    include Logging

    def initialize(conf)
      @cluster_hourly_cost = conf.evaluation[:cluster_hourly_cost]
      raise ArgumentError, 'No VM hourly costs provided!' unless @cluster_hourly_cost

      @fixed_hourly_cost = conf.evaluation[:fixed_hourly_cost] || {}

      @penalties_func = conf.evaluation[:penalties]
    end

    def evaluate_fixed_costs_cpu(vm_allocation)
      cost_cpu = vm_allocation.inject(0.0) do |s,x|
          hc = @cluster_hourly_cost.find{|i| i[:cluster] == x[:cluster_id] }
          raise "Cannot find cpu hourly cost for cluster #{x[:cluster_id]}!" unless hc
          s += hc[:fixed_cpu_hourly_cost]
      end
    end

    def evaluate_fixed_costs_memory(vm_allocation)  
      cost_memory = vm_allocation.inject(0.0) do |s,x|
          hc = @cluster_hourly_cost.find{|i| i[:cluster] == x[:cluster_id]}
          raise "Cannot find memory hourly cost for cluster #{x[:cluster_id]}!" unless hc
          s += hc[:fixed_memory_hourly_cost]
      end
    end
  end

end
