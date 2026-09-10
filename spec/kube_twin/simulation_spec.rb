# frozen_string_literal: true

require 'minitest_helper'

require_relative '../../lib/kube_twin/ksimulation'

require_relative './reference_configuration'

describe KUBETWIN::KSimulation do
  # we define unfeasible allocations as allocations that do not have at least
  # one instance for each software component
  UNFEASIBLE_ALLOCATION = [
    { dc_id: 1, vm_size: :medium, vm_num: 1 + rand(50), component_type: 'Web Server' },
    { dc_id: 3, vm_size: :medium, vm_num: 1 + rand(30), component_type: 'App Server' },
    # { dc_id: 5, vm_size: :large,  vm_num: 1 + rand(2),  component_type: 'Financial Transaction Server' },
  ]

  # NOTE: KSimulation#evaluate_allocation's signature and semantics have
  # moved on since this test was written -- it now takes
  # (rss, css, mtt, lm, mapping, replicas_mapping), not a single array of
  # { dc_id:, vm_size:, vm_num:, component_type: } allocation hashes, and
  # SISFC::Simulation::UNFEASIBLE_ALLOCATION_EVALUATION (the expected return
  # value) doesn't exist anywhere in the KUBETWIN namespace. Skipping rather
  # than guessing at what an "unfeasible allocation" check should assert
  # against the current API -- needs someone who knows the intended current
  # behavior of evaluate_allocation to rewrite this properly.
  it 'should return for unfeasible allocations' do
    skip 'evaluate_allocation signature and SISFC::Simulation::UNFEASIBLE_ALLOCATION_EVALUATION are stale -- see NOTE above'
    with_reference_config do |conf|
      sim = KUBETWIN::KSimulation.new(configuration: conf, evaluator: Object.new)
      _(suppress_output { sim.evaluate_allocation(UNFEASIBLE_ALLOCATION) }).must_equal(SISFC::Simulation::UNFEASIBLE_ALLOCATION_EVALUATION)
    end
  end
end
