# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

describe KUBETWIN::Twin do
  def configuration
    KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "parallel-working-test.conf"))
  end

  # The run's wind-down writes final_allocation.* into the current
  # directory, and MDN examples load ./mdn_models/.
  def in_scratch_directory(&block)
    Dir.mktmpdir do |dir|
      File.symlink(File.join(Characterization::ROOT, "mdn_models"), File.join(dir, "mdn_models"))
      Dir.chdir(dir) { Characterization.quietly(&block) }
    end
  end

  it "starts at time 0 after the warm-up and advances one decision interval per step" do
    twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

    in_scratch_directory do
      _(twin.reset).must_equal 0.0
      _(twin.simulation.now).must_equal twin.simulation.warmup_threshold
      _(twin.step).must_equal 5.0
      _(twin.step(duration: 10.0)).must_equal 15.0
      _(twin.simulation.now).must_equal twin.simulation.warmup_threshold + 15.0
      _(twin.done?).must_equal false
    end
  end

  it "rejects durations that aren't positive multiples of the decision interval" do
    twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

    in_scratch_directory do
      twin.reset
      _ { twin.step(duration: 7.0) }.must_raise ArgumentError
      _ { twin.step(duration: 0.0) }.must_raise ArgumentError
    end
  end

  it "runs to the end and reports evaluate_allocation's result" do
    twin = KUBETWIN::Twin.new(configuration)

    in_scratch_directory do
      twin.reset
      _ { twin.result }.must_raise RuntimeError
      twin.step until twin.done?

      _(twin.result).must_be_within_epsilon Characterization.fingerprint("parallel-working-test")["result"], 1e-12
      _(twin.result).must_equal twin.result
    end
  end

  describe "ScaleReplicas" do
    def scale(service, replicas, cluster: "europe-cloud-control-plane")
      KUBETWIN::Twin::ScaleReplicas.new(service:, cluster:, replicas:)
    end

    it "scales a service up and down at the start of a step" do
      twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

      in_scratch_directory do
        twin.reset
        _(twin.replicas("reviews", "europe-cloud-control-plane")).must_equal 2

        twin.step([scale("reviews", 5)])
        _(twin.last_rejected).must_equal []
        _(twin.replicas("reviews", "europe-cloud-control-plane")).must_equal 5
        _(twin.simulation.instance_variable_get(:@replica_sets)["reviews-app"].replicas).must_equal 5

        twin.step([scale("reviews", 1)])
        _(twin.replicas("reviews", "europe-cloud-control-plane")).must_equal 1

        twin.step until twin.done?
        _(twin.result).must_be_kind_of Float
      end
    end

    it "frees the resources of the pods it removes" do
      twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

      in_scratch_directory do
        twin.reset
        node = twin.simulation.instance_variable_get(:@cluster_repository).values.first.nodes.values.first
        free_cpu = node.available_resources_cpu

        twin.step([scale("reviews", 6)])
        _(node.available_resources_cpu).must_equal free_cpu - 4 * 400
        twin.step([scale("reviews", 2)])
        _(node.available_resources_cpu).must_equal free_cpu
      end
    end

    it "rejects actions it can't apply, and changes nothing for them" do
      twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

      in_scratch_directory do
        twin.reset
        # One 8000 mCPU node; the eight initial pods take 2000, so at most
        # 15 more reviews pods (400 mCPU each) fit.
        actions = [
          scale("nonexistent", 1),
          scale("reviews", 1, cluster: "nowhere"),
          scale("reviews", -1),
          scale("reviews", 2.5),
          scale("ratings", 0),
          scale("reviews", 18),
          scale("reviews", 17)
        ]
        _(actions.map { |a| twin.feasible?(a) }).must_equal [false, false, false, false, false, false, true]

        twin.step(actions)
        _(twin.last_rejected.map(&:last)).must_equal %i[unknown_service unknown_cluster invalid_replicas
          invalid_replicas no_replicas_left insufficient_resources]
        _(twin.last_rejected.map(&:first)).must_equal actions[0..5]
        _(twin.replicas("ratings", "europe-cloud-control-plane")).must_equal 2
        _(twin.replicas("reviews", "europe-cloud-control-plane")).must_equal 17

        twin.step
        _(twin.last_rejected).must_equal []
        _(twin.feasible?(scale("productpage", 3))).must_equal false
        _(twin.feasible?(:not_an_action)).must_equal false
      end
    end

    it "scales only the pods in the given cluster" do
      config = KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "bookinfo-3c-xr.conf"))
      twin = KUBETWIN::Twin.new(config, decision_interval: 5.0)

      in_scratch_directory do
        twin.reset
        clusters = %w[cluster1 cluster2edge cluster3edge]
        before = clusters.map { |c| twin.replicas("reviews", c) }

        twin.step([scale("reviews", before[1] + 2, cluster: "cluster2edge")])
        _(twin.last_rejected).must_equal []
        _(clusters.map { |c| twin.replicas("reviews", c) }).must_equal [before[0], before[1] + 2, before[2]]
        pods = twin.simulation.instance_variable_get(:@services)["reviews"].pods["reviews"]
        _(pods.count { |p| p.node.cluster_id == :cluster2edge }).must_equal before[1] + 2
      end
    end
  end

  describe "#observe" do
    def bookinfo
      KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "bookinfo-3c-xr.conf"))
    end

    def features(entities, key = :id)
      entities.to_h { |e| [e[key], e[:features]] }
    end

    it "covers every cluster, cluster pair, service in each cluster, and workflow, with zero rates after reset" do
      twin = KUBETWIN::Twin.new(configuration)

      in_scratch_directory do
        twin.reset
        o = twin.observe
        _(o.keys).must_equal %i[time locations links placements workflows global]
        _(o[:time]).must_equal 0.0
        _(o[:locations].map { |l| l[:id] }).must_equal [:"europe-cloud-control-plane"]
        _(o[:links]).must_equal []
        _(o[:placements].map { |p| p[:service] }.sort).must_equal %w[details productpage ratings reviews]
        _(o[:workflows].map { |w| w[:id] }).must_equal configuration.workflow_types.keys
        _(o[:placements].sum { |p| p[:features][:arrival_rate] }).must_equal 0.0
        _(o[:workflows].sum { |w| w[:features][:completed] }).must_equal 0
        _(o[:global]).must_equal({time: 0.0, cost: 0.0})
      end
    end

    it "summarizes the last step" do
      twin = KUBETWIN::Twin.new(configuration, decision_interval: 10.0, slos: {1 => 0.0})

      in_scratch_directory do
        twin.reset
        twin.step([KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "europe-cloud-control-plane", replicas: 3)])
        o = twin.observe
        _(o[:time]).must_equal 10.0

        placements = features(o[:placements], :service)
        _(placements["reviews"][:replicas_ready]).must_equal 3
        _(placements["productpage"][:arrival_rate]).must_be :>, 0
        _(placements["productpage"][:service_time_mean]).must_be :>, 0

        location = o[:locations].first[:features]
        # Eight initial pods plus one more reviews pod.
        _(location[:cpu_requested]).must_equal 2 * 200 + 3 * 400 + 2 * 200 + 2 * 200.0
        _(location[:cpu_utilization]).must_be :>, 0
        _(location[:cpu_utilization]).must_be :<=, 1

        workflows = features(o[:workflows])
        workflows.each_value do |w|
          _(w[:completed]).must_be :>, 0
          _(w[:response_p50]).must_be :<=, w[:response_p95]
        end
        _(workflows[1][:slo_violation_rate]).must_equal 1.0
        _(workflows[2][:slo_violation_rate]).must_equal 0.0

        # One node at 0.100 per hour, for 10 seconds.
        _(o[:global][:cost]).must_be_within_epsilon 0.1 * 10 / 3600, 1e-12

        twin.step
        _(twin.observe[:time]).must_equal 20.0
        _(features(twin.observe[:workflows])[1][:completed]).wont_equal workflows[1][:completed]
      end
    end

    it "reports latencies on the links messages cross" do
      twin = KUBETWIN::Twin.new(bookinfo, decision_interval: 10.0)

      in_scratch_directory do
        twin.reset
        twin.step
        _(features(twin.observe[:links]).values.map { |l| l[:latency_mean] }.uniq).must_equal [0.0]

        # Move reviews from cluster1 to cluster2edge: productpage (cluster1)
        # now calls across the link.
        twin.step([
          KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "cluster2edge", replicas: 2),
          KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "cluster1", replicas: 0)
        ])
        _(twin.last_rejected).must_equal []
        link = features(twin.observe[:links])[[:cluster1, :cluster2edge]]
        _(link[:latency_mean]).must_be :>, 0
        _(link[:latency_p95]).must_be :>=, link[:latency_mean] * 0.5
        _(features(twin.observe[:links])[[:cluster1, :cluster3edge]][:latency_mean]).must_equal 0.0
      end
    end

    it "is reproducible" do
      observations = 2.times.map do
        twin = KUBETWIN::Twin.new(bookinfo, decision_interval: 10.0)
        in_scratch_directory do
          twin.reset
          3.times.map { twin.step && twin.observe }
        end
      end
      _(observations[0]).must_equal observations[1]
    end
  end

  describe "Route" do
    def bookinfo
      KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "bookinfo-3c-xr.conf"))
    end

    def reviews_arrivals(twin)
      twin.observe[:placements].select { |p| p[:service] == "reviews" }
        .to_h { |p| [p[:location], p[:features][:arrival_rate]] }
    end

    def route(weights)
      KUBETWIN::Twin::Route.new(service: "reviews", weights:)
    end

    # reviews with 2 pods in cluster1 and 2 in cluster2edge.
    def split_twin
      twin = KUBETWIN::Twin.new(bookinfo, decision_interval: 30.0)
      twin.reset
      twin.step([
        KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "cluster1", replicas: 2),
        KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "cluster2edge", replicas: 2)
      ])
      _(twin.last_rejected).must_equal []
      twin
    end

    it "sends requests to clusters in proportion to the weights" do
      in_scratch_directory do
        twin = split_twin
        twin.step([route({"cluster2edge" => 1})])
        _(twin.last_rejected).must_equal []
        _(twin.routing("reviews")).must_equal({cluster2edge: 1})
        arrivals = reviews_arrivals(twin)
        _(arrivals[:cluster1]).must_equal 0.0
        _(arrivals[:cluster2edge]).must_be :>, 0

        twin.step([route({cluster1: 1, cluster2edge: 3})])
        arrivals = reviews_arrivals(twin)
        _(arrivals[:cluster2edge] / (arrivals[:cluster1] + arrivals[:cluster2edge])).must_be_within_delta 0.75, 0.05
      end
    end

    it "restores the configured load balancing with empty weights" do
      in_scratch_directory do
        twin = split_twin
        twin.step([route({cluster1: 1})])
        twin.step([route({})])
        _(twin.routing("reviews")).must_be_nil
        arrivals = reviews_arrivals(twin)
        _(arrivals[:cluster1]).must_be :>, 0
        _(arrivals[:cluster2edge]).must_be :>, 0
      end
    end

    it "falls back to any pod when no weighted cluster has pods" do
      in_scratch_directory do
        twin = split_twin
        twin.step([route({cluster3edge: 1})])
        arrivals = reviews_arrivals(twin)
        _(arrivals[:cluster1]).must_be :>, 0
        _(arrivals[:cluster2edge]).must_be :>, 0
        _(arrivals[:cluster3edge]).must_equal 0.0
      end
    end

    it "rejects routes it can't apply, and changes nothing for them" do
      in_scratch_directory do
        twin = KUBETWIN::Twin.new(bookinfo, decision_interval: 30.0)
        twin.reset
        actions = [
          KUBETWIN::Twin::Route.new(service: "nonexistent", weights: {cluster1: 1}),
          route({nowhere: 1}),
          route({cluster1: -1}),
          route({cluster1: 0, cluster2edge: 0}),
          route({cluster1: Float::NAN}),
          route({cluster1: "1"}),
          route([[:cluster1, 1]])
        ]
        _(actions.map { |a| twin.feasible?(a) }.uniq).must_equal [false]
        twin.step(actions)
        _(twin.last_rejected.map(&:last)).must_equal %i[unknown_service unknown_cluster invalid_weights
          invalid_weights invalid_weights invalid_weights invalid_weights]
        _(twin.routing("reviews")).must_be_nil
      end
    end
  end

  it "needs a reset before stepping, and a positive decision interval" do
    _ { KUBETWIN::Twin.new(configuration).step }.must_raise RuntimeError
    _ { KUBETWIN::Twin.new(configuration, decision_interval: 0) }.must_raise ArgumentError
  end
end
