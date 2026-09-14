# frozen_string_literal: true

require "minitest_helper"

require "tempfile"

require_relative "reference_configuration"

# A characterization/smoke test for KSimulation#evaluate_allocation -- the
# ~1200-line event-loop method this spec file's sibling (ksimulation_spec.rb)
# deliberately stays away from. Before that method gets split apart, we want
# *something* that fails loudly if a refactor changes its behavior.
#
# This can't pin exact output numbers the way a normal characterization test
# would, for two reasons found while writing it:
#
#   1. evaluate_allocation's local `stats`/`per_component_stats`/etc. never
#      escape the method -- KSimulation only exposes `cluster_repository`
#      and `start_time` via attr_reader -- so there's very little to assert
#      on beyond the return value and the final state of the clusters/nodes.
#   2. Determinism isn't guaranteed even with seeds set: `seeds` only covers
#      communication_latencies and next_component_selection, but other
#      randomness (e.g. KubeScheduler's node scoring given ties, `.sample`
#      calls in the HPA branch, service-time distributions) uses the global
#      unseeded PRNG. The reference config doesn't configure an HPA or MDN
#      model, which avoids those specific paths, but that's not a
#      from-first-principles guarantee of full determinism.
#
# So this asserts invariants rather than exact values: the run completes
# without raising, returns a Float (evaluate_allocation returns
# -weighted_sum), and actually deploys pods onto nodes. If a future
# refactor breaks the event loop outright -- an exception, nothing gets
# scheduled, etc. -- this catches it; it will NOT catch a refactor that
# subtly changes the allocation's numbers.
#
# reference_configuration.rb (REFERENCE_CONFIGURATION, shared by several
# other specs) was never actually a *runnable* simulation config on its
# own -- it has no `services` or `replica_sets` block, and its default
# `request_generation` points at a generator.R script that doesn't exist
# next to the tempfile with_reference_config writes it to (see
# generator_spec.rb, which sidesteps this the same way, by overriding
# request_generation with a `cat`-of-a-tempfile command instead of relying
# on the default). Rather than changing the shared fixture (other specs
# don't need any of this and it'd widen the blast radius of this change),
# this test supplies its own services/replica_sets/request_generation via
# with_reference_config's opts, matching the shape any real examples/*.conf
# uses (see examples/example-hpa.conf's services/replica_sets blocks).
#
# NOTE: this is the first spec in the suite to actually call
# evaluate_allocation (simulation_spec.rb's only test that did is
# `skip`-ped). That method unconditionally writes final_allocation.txt and
# final_allocation.json into the process's working directory as a side
# effect -- running this spec will create those files there. Flagged
# separately -- not fixed here, same "run artifacts alongside source"
# territory already being discussed on its own.
#
# Also NOTE: this hasn't been run against the real gem set (torch-rb, which
# ksimulation.rb requires unconditionally, isn't available in the sandbox
# this was written in) -- please run it for real and let me know what you
# see, especially the deployed_pods count and whether the run is in fact
# deterministic across repeated runs.
describe KUBETWIN::KSimulation do
  describe "#evaluate_allocation" do
    # NOTE: these were originally plain ALL_CAPS constants (REQUEST_GENERATION_DATA,
    # SERVICES, REPLICA_SETS) assigned directly inside this describe block.
    # That broke generator_spec.rb: minitest's `describe` builds each block's
    # class via Class.new { ... }.class_eval(&block), and constant
    # assignment inside a block resolves against the *lexical* scope where
    # the block was written, not the class being eval'd -- so a bare
    # `REQUEST_GENERATION_DATA = ...` here landed as the same top-level
    # ::REQUEST_GENERATION_DATA that generator_spec.rb also defines.
    # Whichever spec file loaded second silently won, reassigning it out
    # from under the other -- which is exactly what made
    # generator_spec.rb's expected/actual generation_time mismatch (not an
    # off-by-one: two different Time.now calls, from two different spec
    # files, colliding on one name). `let` doesn't have this problem --
    # it defines a real per-describe-class method -- so it's used here
    # instead, even for data that isn't accessed as memoized instance state.
    let(:request_generation_data) do
      # one request, workflow type 1 (Web Server -> App Server ->
      # Financial Transaction Server, the full chain from
      # WORKFLOW_TYPES_CHARACTERIZATION), for customer 1.
      <<-END
        Generation Time,Workflow Type ID,Customer ID
        #{Time.now.to_f},1,1
      END
    end

    let(:services) do
      {
        "Web Server" => {serviceName: "WebServerSvc", selector: "Web Server"},
        "App Server" => {serviceName: "AppServerSvc", selector: "App Server"},
        "Financial Transaction Server" => {
          serviceName: "FinancialTransactionServerSvc",
          selector: "Financial Transaction Server"
        }
      }
    end

    let(:replica_sets) do
      {
        "web" => {name: "web_rs", selector: "Web Server", replicas: 2},
        "app" => {name: "app_rs", selector: "App Server", replicas: 2},
        "fin" => {name: "fin_rs", selector: "Financial Transaction Server", replicas: 1}
      }
    end

    it "runs the reference configuration to completion and deploys pods" do
      tf = Tempfile.new("ksimulation_evaluate_allocation_spec")
      tf.write(request_generation_data)
      tf.close

      with_reference_config(seeds: {communication_latencies: 42, next_component_selection: 7},
        services: services,
        replica_sets: replica_sets,
        request_generation: {command: "cat #{tf.path}"}) do |conf|
        sim = KUBETWIN::KSimulation.new(configuration: conf, evaluator: Object.new)

        result = suppress_output { sim.evaluate_allocation }

        _(result).must_be_kind_of Float

        deployed_pods = sim.cluster_repository.values.sum do |c|
          c.nodes.values.sum { |n| n.pod_id_list.length }
        end
        # the 5 replicas requested across the 3 replica sets above
        _(deployed_pods).must_equal 5

        # no node should have been over-committed past its capacity
        sim.cluster_repository.each_value do |c|
          c.nodes.each_value do |n|
            _(n.available_resources_cpu).must_be :>=, 0
            _(n.available_resources_memory).must_be :>=, 0
          end
        end
      end
    ensure
      tf.delete
    end
  end
end
