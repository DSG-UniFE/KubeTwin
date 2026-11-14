# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

module FederationSpec
  CLUSTERS = %w[cluster1 cluster2edge cluster3edge].freeze
  REVIEWS_HALF_AND_HALF = {policies: {"reviews" => {replicas: 4, clusters: %w[cluster1 cluster2edge]}}}.freeze
end

describe "KubeTwin federation" do
  def configuration
    KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "bookinfo-3c-xr.conf"))
  end

  def in_scratch_directory(&block)
    Dir.mktmpdir do |dir|
      File.symlink(File.join(Characterization::ROOT, "mdn_models"), File.join(dir, "mdn_models"))
      Dir.chdir(dir) { Characterization.quietly(&block) }
    end
  end

  def twin(federation: nil, failures: nil, interval: 5.0)
    KUBETWIN::Twin.new(configuration, decision_interval: interval, federation:, failures:).tap(&:reset)
  end

  def spread(twin, service = "reviews") = FederationSpec::CLUSTERS.map { |c| twin.replicas(service, c) }

  def divide(total, weights, service: "reviews") = KUBETWIN::Twin::DivideReplicas.new(service:, total:, weights:)

  it "places a service as its policy divides it" do
    in_scratch_directory do
      _(spread(twin(federation: FederationSpec::REVIEWS_HALF_AND_HALF))).must_equal [2, 2, 0]
      weighted = {policies: {"reviews" => {replicas: 6, weights: {cluster1: 1, cluster2edge: 2, cluster3edge: 3}}}}
      _(spread(twin(federation: weighted))).must_equal [1, 2, 3]
    end
  end

  it "moves replicas off a failed cluster after the toleration, and back when it recovers" do
    in_scratch_directory do
      # cluster2edge down from 25 to 145 s Twin time (outage times count from the start, 10 s earlier)
      t = twin(federation: FederationSpec::REVIEWS_HALF_AND_HALF.merge(failover_toleration: 10.0),
        failures: {outages: [{cluster: "cluster2edge", at: 35.0, duration: 120.0}]})
      t.step until t.now >= 30.0
      _(spread(t)).must_equal [2, 2, 0] # down, but within the toleration
      _(t.observe[:placements].find { |p| p[:service] == "reviews" && p[:location] == :cluster2edge }[:features][:replicas_ready]).must_equal 0

      t.step until t.now >= 40.0
      _(spread(t)).must_equal [4, 0, 0] # failed over
      _(t.observe[:placements].find { |p| p[:service] == "reviews" && p[:location] == :cluster1 }[:features][:replicas_ready]).must_equal 4

      t.step until t.now >= 150.0
      _(spread(t)).must_equal [2, 2, 0] # back
      t.step until t.done?
      _(t.simulation.instance_variable_get(:@stats).n).must_equal 9691
    end
  end

  it "divides replicas as an action, and keeps them divided" do
    in_scratch_directory do
      t = twin
      t.step([divide(5, {"cluster2edge" => 3, "cluster3edge" => 2})])
      _(t.last_rejected).must_equal []
      _(spread(t)).must_equal [0, 3, 2]
      _(t.simulation.federation_policy("reviews").replicas).must_equal 5

      scale = KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "cluster1", replicas: 2)
      t.step([scale])
      _(t.last_rejected).must_equal [[scale, :managed_by_federation]]

      t.step([divide(2, {"cluster1" => 1})])
      _(spread(t)).must_equal [2, 0, 0]
    end
  end

  it "rejects divisions it can't apply" do
    in_scratch_directory do
      t = twin
      actions = [
        divide(2, {cluster1: 1}, service: "nonexistent"), divide(0, {cluster1: 1}), divide(2.5, {cluster1: 1}),
        divide(2, {}), divide(2, {nowhere: 1}), divide(2, {cluster1: -1}), divide(2, {cluster1: 0})
      ]
      t.step(actions)
      _(t.last_rejected.map(&:last)).must_equal %i[unknown_service invalid_replicas invalid_replicas invalid_weights
        unknown_cluster invalid_weights invalid_weights]
      _(t.simulation.federation_policy("reviews")).must_be_nil
    end
  end

  it "duplicates a service into every cluster" do
    in_scratch_directory do
      t = twin(federation: {policies: {"details" => {mode: :duplicated, replicas: 2}}})
      _(spread(t, "details")).must_equal [2, 2, 2]
    end
  end

  it "overflows to clusters with room, and reports what fits nowhere" do
    in_scratch_directory do
      # cluster3edge has 4000 mCPU free; reviews pods take 400
      t = twin(federation: {policies: {"reviews" => {replicas: 14, weights: {cluster3edge: 3, cluster2edge: 1}}}})
      _(spread(t)).must_equal [0, 4, 10]
      _(t.simulation.unschedulable("reviews")).must_equal 0

      t.step([divide(14, {"cluster3edge" => 1})])
      _(spread(t)).must_equal [0, 0, 10]
      _(t.simulation.unschedulable("reviews")).must_equal 4
    end
  end

  it "forks with policies and failures pending" do
    in_scratch_directory do
      t = twin(federation: FederationSpec::REVIEWS_HALF_AND_HALF.merge(failover_toleration: 5.0),
        failures: {clusters: {mtbf: 60.0, mttr: 20.0}})
      t.step
      fork = t.fork
      trace = ->(x) { Array.new(30) { x.step && spread(x) } }
      parent = trace.call(t)

      _(trace.call(fork)).must_equal parent
      _(parent.uniq.size).must_be :>, 1 # replicas moved
    end
  end
end
