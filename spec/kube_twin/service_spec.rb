# frozen_string_literal: true

require "minitest_helper"

# Service only needs a pod's label to group it, and its node's cluster to
# route by cluster weights.
ServiceSpecPod = Struct.new(:label, :id, :node)
ServiceSpecNode = Struct.new(:cluster_id)

describe KUBETWIN::Service do
  def service_with_pods(random: nil)
    service = KUBETWIN::Service.new("reviews", "reviews", :random, random: random)
    10.times { |i| service.assignPod(ServiceSpecPod.new("reviews", i)) }
    service
  end

  it "draws :random load balancing from the generator it was given" do
    picks = Array.new(2) do
      service = service_with_pods(random: Random.new(7))
      Array.new(20) { service.get_pod("reviews").id }
    end

    _(picks.first).must_equal picks.last
    _(picks.first.uniq.size).must_be :>, 1
  end

  it "falls back to Ruby's global generator without one" do
    service = service_with_pods

    _(service_with_pods.get_pod("reviews").label).must_equal "reviews"
    _(service.get_pod("missing")).must_be_nil
  end

  describe "cluster weights" do
    # Pods 0-4 in :a, 5-9 in :b.
    def split_service
      service = KUBETWIN::Service.new("reviews", "reviews", :random, random: Random.new(3))
      10.times { |i| service.assignPod(ServiceSpecPod.new("reviews", i, ServiceSpecNode.new((i < 5) ? :a : :b))) }
      service
    end

    def clusters_picked(service, n = 400)
      Array.new(n) { service.get_pod("reviews").node.cluster_id }.tally
    end

    it "picks clusters by weight, then any pod in the cluster" do
      service = split_service
      service.cluster_weights = {b: 1}
      _(clusters_picked(service)).must_equal({b: 400})
      _(Array.new(200) { service.get_pod("reviews").id }.uniq.sort).must_equal [5, 6, 7, 8, 9]

      service.cluster_weights = {a: 1, b: 3}
      _(clusters_picked(service, 4000)[:b] / 4000.0).must_be_within_delta 0.75, 0.03
    end

    it "follows pods as they are added and removed" do
      service = split_service
      service.cluster_weights = {c: 1}
      _(clusters_picked(service).keys.sort).must_equal [:a, :b]

      service.assignPod(ServiceSpecPod.new("reviews", 10, ServiceSpecNode.new(:c)))
      _(clusters_picked(service)).must_equal({c: 400})

      service.delete_pod("reviews", service.pods["reviews"].last)
      _(clusters_picked(service).keys.sort).must_equal [:a, :b]
    end

    it "goes back to plain load balancing with nil or empty weights" do
      service = split_service
      service.cluster_weights = {b: 1}
      service.cluster_weights = {}
      _(service.cluster_weights).must_be_nil
      _(clusters_picked(service).keys.sort).must_equal [:a, :b]
    end
  end
end
