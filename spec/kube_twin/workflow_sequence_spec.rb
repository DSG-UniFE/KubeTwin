# frozen_string_literal: true

require 'minitest_helper'

# WorkflowSequence holds three helpers that used to be private instance
# methods on KSimulation itself (get_workflow_components,
# request_component_sequence, request_step_key -- see the event loop's
# ET_WORKFLOW_STEP_COMPLETED / ET_REQUEST_FORWARDING handlers and
# #evaluate_allocation's chain-policy setup for the call sites). None of
# them touch simulation state, so -- like HorizontalPodAutoscaler#decide_scaling
# before them -- they're tested directly here rather than only through a
# full simulation run. Verified by hand against the real files in this
# repo (no gem dependencies needed) before being committed here.
describe KUBETWIN::WorkflowSequence do
  def build_request(component_sequence: nil)
    KUBETWIN::Request.new(rid:                    1,
                           generation_time:        Time.now.to_f,
                           initial_data_center_id: 0,
                           arrival_time:           Time.now.to_f,
                           workflow_type_id:       0,
                           customer_id:            0,
                           component_sequence:     component_sequence)
  end

  describe '.get_workflow_components' do
    it 'flattens a flat component_sequence to just the names' do
      workflow = { component_sequence: [{ name: 'productpage' }, { name: 'reviews' }, { name: 'ratings' }] }
      result = KUBETWIN::WorkflowSequence.get_workflow_components(workflow)
      _(result).must_equal %w[productpage reviews ratings]
    end

    it 'recurses into nested calls depth-first (matches examples/bookinfo-3c-xr-nested-control.conf)' do
      workflow = { component_sequence: [
        { name: 'productpage', calls: [
          { name: 'details' },
          { name: 'reviews', calls: [{ name: 'ratings' }] }
        ] }
      ] }
      result = KUBETWIN::WorkflowSequence.get_workflow_components(workflow)
      _(result).must_equal %w[productpage details reviews ratings]
    end

    it 'recurses into each parallel branch that has its own component_sequence' do
      workflow = { component_sequence: [
        { name: 'productpage' },
        { type: 'parallel', branches: [
          { name: 'reviews', component_sequence: [{ name: 'reviews' }, { name: 'ratings' }] },
          { name: 'details' }
        ] },
        { name: 'checkout' }
      ] }
      result = KUBETWIN::WorkflowSequence.get_workflow_components(workflow)
      # branch 1 has its own component_sequence -> both its steps; branch 2
      # has none -> falls back to a single-element sequence from its name
      _(result).must_equal %w[productpage reviews ratings details checkout]
    end

    it 'falls back to a single-element sequence for a branch with no component_sequence (matches examples/parallel-working-test.conf)' do
      workflow = { component_sequence: [
        { name: 'productpage' },
        { type: 'parallel', branches: [{ name: 'reviews' }, { name: 'details' }], wait_for: 'all' },
        { name: 'ratings' }
      ] }
      result = KUBETWIN::WorkflowSequence.get_workflow_components(workflow)
      _(result).must_equal %w[productpage reviews details ratings]
    end

    it 'combines a parallel branch and a nested call' do
      workflow = { component_sequence: [
        { type: 'parallel', branches: [
          { name: 'a', component_sequence: [{ name: 'a', calls: [{ name: 'a-nested' }] }] }
        ] }
      ] }
      result = KUBETWIN::WorkflowSequence.get_workflow_components(workflow)
      _(result).must_equal %w[a a-nested]
    end

    it 'returns an empty list for an empty component_sequence' do
      _(KUBETWIN::WorkflowSequence.get_workflow_components(component_sequence: [])).must_equal []
    end
  end

  describe '.request_component_sequence' do
    it "returns the request's own component_sequence when it has one" do
      own_sequence = [{ name: 'branch-only-step' }]
      req = build_request(component_sequence: own_sequence)
      workflow = { component_sequence: [{ name: 'productpage' }] }

      result = KUBETWIN::WorkflowSequence.request_component_sequence(req, workflow)
      _(result).must_be_same_as own_sequence
    end

    it "falls back to the workflow's component_sequence when the request has none" do
      workflow_sequence = [{ name: 'productpage' }]
      req = build_request
      workflow = { component_sequence: workflow_sequence }

      result = KUBETWIN::WorkflowSequence.request_component_sequence(req, workflow)
      _(result).must_be_same_as workflow_sequence
    end
  end

  describe '.request_step_key' do
    it 'changes once worked_step advances, for the same component_sequence' do
      req = build_request
      sequence = [{ name: 'a' }, { name: 'b' }, { name: 'c' }]

      key_before = KUBETWIN::WorkflowSequence.request_step_key(req, sequence)
      req.step_completed(1.0) # worked_step: 0 -> 0, next_step: 0 -> 1 (see request_spec.rb)
      req.step_completed(1.0) # worked_step: 0 -> 1, next_step: 1 -> 2
      key_after = KUBETWIN::WorkflowSequence.request_step_key(req, sequence)

      _(key_before[0]).must_equal sequence.object_id
      _(key_before).wont_equal key_after
    end

    it 'gives distinct keys for two content-equal but distinct sequence arrays' do
      req = build_request
      seq_a = [{ name: 'x' }]
      seq_b = [{ name: 'x' }] # equal content, different object -- must not collide

      key_a = KUBETWIN::WorkflowSequence.request_step_key(req, seq_a)
      key_b = KUBETWIN::WorkflowSequence.request_step_key(req, seq_b)
      _(key_a).wont_equal key_b
    end
  end
end
