# frozen_string_literal: true

module KUBETWIN
  # Pure predicates for the two "is this request entering/exiting a
  # service chain" checks inline in KSimulation's ET_WORKFLOW_STEP_COMPLETED
  # handler (a service chain here is a policy's ordered list of component
  # names -- see ksimulation.rb's chain-policy setup, service_chain_max_latency_ms
  # -- represented the same way a workflow is: { component_sequence: [{name:},...] }).
  # Neither predicate touches simulation state; they're unit-tested directly
  # here (spec/kube_twin/chain_tracker_spec.rb) rather than only through a
  # full simulation run.
  module ChainTracker
    # True when req just completed the chain's first component, at the top
    # level (not inside a parallel branch or nested call -- chain tracking
    # only applies to a request's own top-level walk through its workflow,
    # matching the original inline check).
    def self.entering_chain?(req, chain, current_component_name)
      applicable?(req, chain, current_component_name) &&
        chain[:component_sequence].first[:name] == current_component_name
    end

    # True when req just completed the chain's last component, at the top
    # level. Deliberately independent of entering_chain? (not an elsif in
    # the original code either) -- a single-component chain can be both
    # entered and exited by the same step, in the same event.
    def self.exiting_chain?(req, chain, current_component_name)
      applicable?(req, chain, current_component_name) &&
        chain[:component_sequence].last[:name] == current_component_name
    end

    def self.applicable?(req, chain, current_component_name)
      req.parent_request.nil? && !chain.nil? && !current_component_name.nil?
    end
    private_class_method :applicable?
  end
end
