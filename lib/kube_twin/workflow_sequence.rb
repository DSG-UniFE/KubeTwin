# frozen_string_literal: true

module KUBETWIN
  # Pure helpers for working with a workflow's component sequence --
  # extracted out of KSimulation, which used to define these three methods
  # inline (see the event loop's ET_WORKFLOW_STEP_COMPLETED /
  # ET_REQUEST_FORWARDING handlers and #evaluate_allocation's chain-policy
  # setup for the call sites). None of them touch simulation state (no
  # @cluster_repository, no @current_time, nothing); they only look at the
  # workflow/request hashes and objects passed in, so they're unit-tested
  # directly here (spec/kube_twin/workflow_sequence_spec.rb) instead of
  # only through a full simulation run.
  module WorkflowSequence
    # Flattens a workflow's component_sequence into a plain list of
    # component names, depth-first, recursing into:
    #   - parallel steps (type: "parallel"): each branch's own
    #     component_sequence, or, when a branch has none, a single-element
    #     sequence built from the branch's own name (this is the same
    #     fallback #clone_for_parallel_branch relies on for a branch with
    #     no nested steps of its own)
    #   - nested calls (a step's :calls key): recursively flattened the
    #     same way
    #   workflow is any Hash with a :component_sequence key -- the top
    #   level workflow_type entry, or (recursively) a synthetic
    #   { component_sequence: [...] } for a parallel branch or a step's
    #   :calls.
    def self.get_workflow_components(workflow)
      components = []
      workflow[:component_sequence].each do |cs|
        if cs[:type] == 'parallel'
          cs[:branches].each do |branch|
            branch_sequence = branch[:component_sequence] || [{ name: branch[:name] }]
            components.concat(get_workflow_components(component_sequence: branch_sequence))
          end
        else
          components << cs[:name]
          components.concat(get_workflow_components(component_sequence: cs[:calls])) if cs[:calls]
        end
      end
      components
    end

    # A request may be running its own private component_sequence (set by
    # #clone_for_parallel_branch / #clone_for_nested_call when it branches
    # off the main workflow); when it isn't, it's still walking the parent
    # workflow's own sequence.
    def self.request_component_sequence(req, workflow)
      req.component_sequence || workflow[:component_sequence]
    end

    # A cache/dedup key for "this request's current step within this
    # particular component_sequence" -- component_sequence.object_id
    # (rather than its content) is deliberate: two requests can be walking
    # equal-looking but distinct sequence arrays (e.g. two parallel
    # branches with the same shape) and must not collide.
    def self.request_step_key(req, component_sequence)
      [component_sequence.object_id, req.worked_step]
    end
  end
end
