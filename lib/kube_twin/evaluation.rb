# frozen_string_literal: true

require_relative './logger'

module KUBETWIN
  class Evaluator

    include Logging

    def initialize(conf)
      @vm_hourly_cost = conf.evaluation[:vm_hourly_cost]
      raise ArgumentError, 'No VM hourly costs provided!' unless @vm_hourly_cost

      @fixed_hourly_cost = conf.evaluation[:fixed_hourly_cost] || {}

      @penalties_func = conf.evaluation[:penalties]
    end

    def evaluate_business_impact(all_kpis, per_workflow_and_customer_kpis,
                                 vm_allocation)
      # evaluate variable hourly costs related to VM allocation
      cost = vm_allocation.inject(0.0) do |s,x|
        hc = @vm_hourly_cost.find{|i| i[:data_center] == x[:dc_id] and i[:vm_type] == x[:vm_size] }
        raise "Cannot find hourly cost for data center #{x[:dc_id]} and VM size #{x[:vm_size]}!" unless hc
        s += x[:vm_num] * hc[:cost]
      end

      # evaluate fixed hourly costs (for private Cloud data centers)
      @fixed_hourly_cost.values.each do |fixed_cost|
        cost += fixed_cost
      end

      # calculate daily cost
      cost *= 24.0

      # consider SLO violation penalties
      penalties = (@penalties_func.nil? ? {} : (@penalties_func.call(all_kpis, per_workflow_and_customer_kpis) || {}))

      { it_cost: cost }.merge!(penalties)
    end
  end
end

