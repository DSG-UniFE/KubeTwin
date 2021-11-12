# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'

describe KUBETWIN::Simulation do
  # we define unfeasible allocations as allocations that do not have at least
  # one instance for each software component
  UNFEASIBLE_ALLOCATION = [
    { dc_id: 1, vm_size: :medium, vm_num: 1 + rand(50), component_type: 'Web Server' },
    { dc_id: 3, vm_size: :medium, vm_num: 1 + rand(30), component_type: 'App Server' },
    # { dc_id: 5, vm_size: :large,  vm_num: 1 + rand(2),  component_type: 'Financial Transaction Server' },
  ]

  it 'should return for unfeasible allocations' do
    with_reference_config do |conf|
      sim = KUBETWIN::Simulation.new(configuration: conf, evaluator: Object.new)
      _(suppress_output { sim.evaluate_allocation(UNFEASIBLE_ALLOCATION) }).must_equal(SISFC::Simulation::UNFEASIBLE_ALLOCATION_EVALUATION)
    end
  end
end
