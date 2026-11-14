# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

describe "KubeTwin failures" do
  def configuration(example)
    KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "#{example}.conf"))
  end

  def in_scratch_directory(&block)
    Dir.mktmpdir do |dir|
      File.symlink(File.join(Characterization::ROOT, "mdn_models"), File.join(dir, "mdn_models"))
      Dir.chdir(dir) { Characterization.quietly(&block) }
    end
  end

  def scale(service, cluster, replicas) = KUBETWIN::Twin::ScaleReplicas.new(service:, cluster:, replicas:)

  def placement(twin, service, cluster)
    twin.observe[:placements].find { |p| p[:service] == service && p[:location] == cluster }[:features]
  end

  def location(twin, cluster) = twin.observe[:locations].find { |l| l[:id] == cluster }[:features]

  def workflow(twin) = twin.observe[:workflows].first[:features]

  # bookinfo-3c-xr with reviews only in cluster2edge.
  def bookinfo_twin(failures)
    twin = KUBETWIN::Twin.new(configuration("bookinfo-3c-xr"), decision_interval: 10.0, failures:)
    twin.reset
    twin.step([scale("reviews", "cluster2edge", 2), scale("reviews", "cluster1", 0)])
    twin
  end

  it "takes a cluster's pods out during an outage; requests wait, then complete" do
    in_scratch_directory do
      # outage times count from the simulation's start, 10 s of warm-up
      # before the Twin's 0: this one is down from 21 to 29 s Twin time
      twin = bookinfo_twin(outages: [{cluster: "cluster2edge", at: 31.0, duration: 8.0}])
      twin.step # 10-20 s
      _(location(twin, :cluster2edge)[:up]).must_equal 1.0
      normal = workflow(twin)

      twin.step # 20-30 s
      outage = workflow(twin)
      _(outage[:response_p95]).must_be :>, normal[:response_p95] + 1000 # requests waited seconds for reviews

      twin.step
      _(placement(twin, "reviews", :cluster2edge)[:replicas_ready]).must_equal 2
      _(location(twin, :cluster2edge)[:up]).must_equal 1.0
      twin.step until twin.done?
      _(twin.simulation.instance_variable_get(:@stats).n).must_equal 9691 # every request completes, as without the outage
    end
  end

  it "reports a cluster down and its pods restarting during an outage" do
    in_scratch_directory do
      twin = bookinfo_twin(outages: [{cluster: "cluster2edge", at: 35.0, duration: 30.0}]) # 25-55 s Twin time
      2.times { twin.step }
      _(location(twin, :cluster2edge)[:up]).must_equal 0.0
      _(placement(twin, "reviews", :cluster2edge)).must_equal placement(twin, "reviews", :cluster2edge)
        .merge(replicas_ready: 0, replicas_starting: 2)
      _(twin.feasible?(scale("reviews", "cluster2edge", 3))).must_equal false # nothing new on a failed cluster
      _(twin.feasible?(scale("reviews", "cluster3edge", 1))).must_equal true
    end
  end

  it "crashes and restarts pods, reproducibly" do
    traces = 2.times.map do
      in_scratch_directory do
        twin = KUBETWIN::Twin.new(configuration("parallel-working-test"), decision_interval: 1.0,
          failures: {pods: {mtbf: 20.0, restart_time: 2.0}})
        twin.reset
        Array.new(40) { twin.step && twin.observe[:placements].sum { |p| p[:features][:replicas_starting] } }
      end
    end

    _(traces[0]).must_equal traces[1]
    _(traces[0].max).must_be :>, 0 # some pods were restarting
    _(traces[0].min).must_equal 0
  end

  it "fails nodes and clusters at random, and forks with failures pending" do
    in_scratch_directory do
      twin = KUBETWIN::Twin.new(configuration("bookinfo-3c-xr"), decision_interval: 5.0,
        failures: {nodes: {mtbf: 60.0, mttr: 10.0}, clusters: {mtbf: 120.0, mttr: 15.0}, pods: {mtbf: 30.0, restart_time: 1.0}})
      twin.reset
      twin.step([scale("reviews", "cluster2edge", 2)])
      fork = twin.fork
      trace = ->(t) { Array.new(30) { t.step && t.observe[:locations].map { |l| l[:features][:up] } } }
      parent = trace.call(twin)

      _(trace.call(fork)).must_equal parent
      _(parent.flatten.min).must_be :<, 1.0 # something failed
    end
  end

  it "rejects outages on unknown clusters or nodes" do
    in_scratch_directory do
      [{cluster: "nowhere", at: 1.0, duration: 1.0}, {node: 999, at: 1.0, duration: 1.0}].each do |outage|
        twin = KUBETWIN::Twin.new(configuration("parallel-working-test"), failures: {outages: [outage]})
        _ { twin.reset }.must_raise ArgumentError
      end
    end
  end
end
