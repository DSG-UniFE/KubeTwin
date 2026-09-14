# frozen_string_literal: true

require "minitest_helper"

# ChainTracker holds the two "is this request entering/exiting a service
# chain" predicates that used to be inline conditions in KSimulation's
# ET_WORKFLOW_STEP_COMPLETED handler. Neither touches simulation state, so
# -- like WorkflowSequence and RequestForwarder before it -- they're tested
# directly here rather than only through a full simulation run.
describe KUBETWIN::ChainTracker do
  def build_request(parent_request: nil)
    KUBETWIN::Request.new(rid:                    1,
      generation_time:        Time.now.to_f,
      initial_data_center_id: 0,
      arrival_time:           Time.now.to_f,
      workflow_type_id:       0,
      customer_id:            0,
      parent_request:         parent_request)
  end

  let(:chain) { {component_sequence: [{name: "productpage"}, {name: "reviews"}, {name: "ratings"}]} }

  describe ".entering_chain?" do
    it "is true when the current component is the chain's first, for a top-level request" do
      req = build_request
      _(KUBETWIN::ChainTracker.entering_chain?(req, chain, "productpage")).must_equal true
    end

    it "is false for a component other than the chain's first" do
      req = build_request
      _(KUBETWIN::ChainTracker.entering_chain?(req, chain, "reviews")).must_equal false
    end

    it "is false when chain is nil (no service-chain policy for this workflow)" do
      req = build_request
      _(KUBETWIN::ChainTracker.entering_chain?(req, nil, "productpage")).must_equal false
    end

    it "is false when current_component_name is nil (a parallel container step)" do
      req = build_request
      _(KUBETWIN::ChainTracker.entering_chain?(req, chain, nil)).must_equal false
    end

    it "is false for a nested-call or parallel-branch request (it has a parent_request)" do
      parent = build_request
      child = build_request(parent_request: parent)
      _(KUBETWIN::ChainTracker.entering_chain?(child, chain, "productpage")).must_equal false
    end
  end

  describe ".exiting_chain?" do
    it "is true when the current component is the chain's last, for a top-level request" do
      req = build_request
      _(KUBETWIN::ChainTracker.exiting_chain?(req, chain, "ratings")).must_equal true
    end

    it "is false for a component other than the chain's last" do
      req = build_request
      _(KUBETWIN::ChainTracker.exiting_chain?(req, chain, "reviews")).must_equal false
    end

    it "is false when chain is nil" do
      req = build_request
      _(KUBETWIN::ChainTracker.exiting_chain?(req, nil, "ratings")).must_equal false
    end

    it "is false for a nested-call or parallel-branch request (it has a parent_request)" do
      parent = build_request
      child = build_request(parent_request: parent)
      _(KUBETWIN::ChainTracker.exiting_chain?(child, chain, "ratings")).must_equal false
    end
  end

  describe "a single-component chain" do
    it "is entered and exited by the same step, in the same event (not mutually exclusive -- matches the original two independent ifs)" do
      req = build_request
      one_step_chain = {component_sequence: [{name: "solo"}]}
      _(KUBETWIN::ChainTracker.entering_chain?(req, one_step_chain, "solo")).must_equal true
      _(KUBETWIN::ChainTracker.exiting_chain?(req, one_step_chain, "solo")).must_equal true
    end
  end
end
