# frozen_string_literal: true

require "minitest_helper"

# RequestForwarder holds the routing decision extracted out of
# KSimulation#schedule_request_forward (and, one level up,
# #dispatch_nested_call, plus the very first hop in ET_REQUEST_GENERATION):
# given a component name, does it resolve to a live pod, and if so, on
# which cluster and at what latency. It's constructor-injected with just
# kube_dns and cluster_repository -- the two read-only registries the
# decision needs -- rather than a whole KSimulation instance, so it's
# tested directly here with hand-built KubeDns/Service/Pod/Node/Cluster
# fixtures (no gem dependencies, no running simulation). The mutation that
# used to sit right next to this logic (req.update_transfer_time,
# trace_request, the @forwarded counter, scheduling the ET_REQUEST_FORWARDING
# event) stays in KSimulation -- see the comment at its schedule_request_forward
# call site for how the two pieces fit together.
#
# #route takes a bare source_location_id rather than a Cluster -- the
# source side of a route can be a cluster's location_id (an inter-component
# hop) or a customer's location_id (the very first hop, in
# ET_REQUEST_GENERATION), and #route only ever needs the id itself.
#
# schedule_request_forward/dispatch_nested_call/ET_REQUEST_GENERATION
# themselves still need a real KSimulation (torch-rb) to exercise
# end-to-end, so they were instead verified by hand against the actual
# patched source, copied verbatim into a throwaway harness object exposing
# just the ivars/methods each touches -- confirming the KSimulation-side
# rewrites still match the original inline behavior exactly.
describe KUBETWIN::RequestForwarder do
  def build_cluster(id, location_id: 0)
    KUBETWIN::Cluster.new(id: id, fixed_hourly_cost_cpu: 1.0, fixed_hourly_cost_memory: 1.0,
      location_id: location_id, name: id.to_s, type: :cloud, tier: :cloud,
      node_number: 1, node_resources_cpu: 1000, node_resources_memory: 1000)
  end

  def build_node(cluster, node_id, type: :cloud)
    node = KUBETWIN::Node.new(node_id, 1000, 1000, cluster.cluster_id, type)
    cluster.add_node(node)
    node
  end

  # service_time_distribution needs a real ERV distribution shape here --
  # Pod -> Container#initialize builds an ERV::RandomVariable eagerly for
  # whichever node.type key is present (see examples/parallel-working-test.conf
  # for the same shape in a real config); RequestForwarder never samples
  # from it, but Container still constructs it as soon as the Pod exists.
  def build_pod(node, label)
    image_info = {node_affinity: nil, blocking: false, max_processes: 1,
                  resources_requirements_cpu: 100, resources_requirements_memory: 100,
                  service_time_distribution: {
                    node.type => {distribution: :gaussian, args: {mean: 0.015, sd: 0.0015, seed: 12_345}}
                  }}
    KUBETWIN::Pod.new(rand(100_000), "#{label}_pod", node, label, image_info)
  end

  def register(kube_dns, label, pod)
    service = KUBETWIN::Service.new(label, label)
    service.assignPod(pod)
    kube_dns.registerService(service)
  end

  describe "#route" do
    it "returns nil when no service is registered for the component name" do
      # a bare Object.new as the latency_manager (no sample_latency_between
      # defined) doubles as proof that this path returns before ever
      # touching it -- calling it would raise NoMethodError
      kube_dns = KUBETWIN::KubeDns.new
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: {})

      result = forwarder.route("unregistered", 0, Object.new, 10.0)
      _(result).must_be_nil
    end

    it "returns nil when the service has no pod assigned" do
      kube_dns = KUBETWIN::KubeDns.new
      kube_dns.registerService(KUBETWIN::Service.new("reviews", "reviews"))
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: {})

      result = forwarder.route("reviews", 0, Object.new, 10.0)
      _(result).must_be_nil
    end

    it "routes to the pod/cluster the service resolves to, with forwarding_time = base_time + sampled latency" do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_b = build_cluster(:b, location_id: 1)
      node_b = build_node(cluster_b, "b-1")
      pod = build_pod(node_b, "reviews")
      register(kube_dns, "reviews", pod)

      cluster_repository = {cluster_b.cluster_id => cluster_b}
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      latency_manager = Object.new
      latency_manager.define_singleton_method(:sample_latency_between) { |_src, _dst| 0.025 }

      source_location_id = 0
      result = forwarder.route("reviews", source_location_id, latency_manager, 100.0)

      _(result).wont_be_nil
      _(result.pod).must_be_same_as pod
      _(result.cluster).must_be_same_as cluster_b
      _(result.transmission_time).must_equal 0.025
      _(result.forwarding_time).must_equal 100.025
    end

    it "resolves the cluster via the pod's node cluster_id, unrelated to source_location_id" do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_a = build_cluster(:a, location_id: 0)
      pod_on_a = build_pod(build_node(cluster_a, "a-1"), "checkout")
      register(kube_dns, "checkout", pod_on_a)

      cluster_repository = {cluster_a.cluster_id => cluster_a}
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      latency_manager = Object.new
      latency_manager.define_singleton_method(:sample_latency_between) { |_src, _dst| 0.0 }

      # source_location_id here is an arbitrary id (e.g. a different
      # cluster's, or a customer's) that has nothing to do with cluster_a --
      # result.cluster must still be cluster_a, where the pod actually lives
      result = forwarder.route("checkout", 999, latency_manager, 0.0)
      _(result.cluster).must_be_same_as cluster_a
    end

    it "passes source_location_id straight through as the sample_latency_between source (no cluster indirection)" do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_b = build_cluster(:b, location_id: 9)
      node_b = build_node(cluster_b, "b-1")
      pod = build_pod(node_b, "reviews")
      register(kube_dns, "reviews", pod)

      seen_args = nil
      spy = Object.new
      spy.define_singleton_method(:sample_latency_between) do |src, dst|
        seen_args = [src, dst]
        0.5
      end

      cluster_repository = {cluster_b.cluster_id => cluster_b}
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      forwarder.route("reviews", 7, spy, 0.0)

      _(seen_args).must_equal [7, 9]
    end

    it "works with a customer's location_id as the source, not just a cluster's (the ET_REQUEST_GENERATION case)" do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_b = build_cluster(:b, location_id: 3)
      node_b = build_node(cluster_b, "b-1")
      pod = build_pod(node_b, "productpage")
      register(kube_dns, "productpage", pod)

      cluster_repository = {cluster_b.cluster_id => cluster_b}
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      latency_manager = Object.new
      latency_manager.define_singleton_method(:sample_latency_between) { |_src, _dst| 0.008 }

      customer_location_id = 42 # no Cluster object behind this at all
      result = forwarder.route("productpage", customer_location_id, latency_manager, 5.0)

      _(result.pod).must_be_same_as pod
      _(result.forwarding_time).must_equal 5.008
    end
  end
end
