# frozen_string_literal: true

require 'minitest_helper'

# RequestForwarder holds the routing decision extracted out of
# KSimulation#schedule_request_forward (and, one level up, #dispatch_nested_call):
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
# schedule_request_forward/dispatch_nested_call themselves still need a
# real KSimulation (torch-rb) to exercise end-to-end, so they were instead
# verified by hand against the actual patched source, copied verbatim into
# a throwaway harness object exposing just the ivars/methods those two
# methods touch -- confirming the KSimulation-side rewrite (mutation order,
# the "parent_req.data_center_id is set even when the forward itself is
# unroutable" quirk) still matches the original inline behavior exactly.
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
    image_info = { node_affinity: nil, blocking: false, max_processes: 1,
                   resources_requirements_cpu: 100, resources_requirements_memory: 100,
                   service_time_distribution: {
                     node.type => { distribution: :gaussian, args: { mean: 0.015, sd: 0.0015, seed: 12_345 } }
                   } }
    KUBETWIN::Pod.new(rand(100_000), "#{label}_pod", node, label, image_info)
  end

  def register(kube_dns, label, pod)
    service = KUBETWIN::Service.new(label, label)
    service.assignPod(pod)
    kube_dns.registerService(service)
  end

  describe '#route' do
    it 'returns nil when no service is registered for the component name' do
      # a bare Object.new as the latency_manager (no sample_latency_between
      # defined) doubles as proof that this path returns before ever
      # touching it -- calling it would raise NoMethodError
      kube_dns = KUBETWIN::KubeDns.new
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: {})
      source = build_cluster(:a)

      result = forwarder.route('unregistered', source, Object.new, 10.0)
      _(result).must_be_nil
    end

    it 'returns nil when the service has no pod assigned' do
      kube_dns = KUBETWIN::KubeDns.new
      kube_dns.registerService(KUBETWIN::Service.new('reviews', 'reviews'))
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: {})
      source = build_cluster(:a)

      result = forwarder.route('reviews', source, Object.new, 10.0)
      _(result).must_be_nil
    end

    it 'routes to the pod/cluster the service resolves to, with forwarding_time = base_time + sampled latency' do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_a = build_cluster(:a, location_id: 0)
      cluster_b = build_cluster(:b, location_id: 1)
      node_b = build_node(cluster_b, 'b-1')
      pod = build_pod(node_b, 'reviews')
      register(kube_dns, 'reviews', pod)

      cluster_repository = { cluster_a.cluster_id => cluster_a, cluster_b.cluster_id => cluster_b }
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      latency_manager = Object.new
      latency_manager.define_singleton_method(:sample_latency_between) { |_src, _dst| 0.025 }

      result = forwarder.route('reviews', cluster_a, latency_manager, 100.0)

      _(result).wont_be_nil
      _(result.pod).must_be_same_as pod
      _(result.cluster).must_be_same_as cluster_b
      _(result.transmission_time).must_equal 0.025
      _(result.forwarding_time).must_equal 100.025
    end

    it 'resolves the cluster via the pod node cluster_id, not the source cluster' do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_a = build_cluster(:a, location_id: 0)
      cluster_b = build_cluster(:b, location_id: 1)
      node_a = build_node(cluster_a, 'a-1')
      pod_on_a = build_pod(node_a, 'checkout')
      register(kube_dns, 'checkout', pod_on_a)

      cluster_repository = { cluster_a.cluster_id => cluster_a, cluster_b.cluster_id => cluster_b }
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      latency_manager = Object.new
      latency_manager.define_singleton_method(:sample_latency_between) { |_src, _dst| 0.0 }

      # routing *from* cluster_b, but the pod actually lives on cluster_a --
      # result.cluster must be cluster_a (where the pod is), not cluster_b
      result = forwarder.route('checkout', cluster_b, latency_manager, 0.0)
      _(result.cluster).must_be_same_as cluster_a
    end

    it 'passes source and destination location ids through to the latency manager' do
      kube_dns = KUBETWIN::KubeDns.new
      cluster_a = build_cluster(:a, location_id: 7)
      cluster_b = build_cluster(:b, location_id: 9)
      node_b = build_node(cluster_b, 'b-1')
      pod = build_pod(node_b, 'reviews')
      register(kube_dns, 'reviews', pod)

      seen_args = nil
      spy = Object.new
      spy.define_singleton_method(:sample_latency_between) do |src, dst|
        seen_args = [src, dst]
        0.5
      end

      cluster_repository = { cluster_a.cluster_id => cluster_a, cluster_b.cluster_id => cluster_b }
      forwarder = KUBETWIN::RequestForwarder.new(kube_dns: kube_dns, cluster_repository: cluster_repository)
      forwarder.route('reviews', cluster_a, spy, 0.0)

      _(seen_args).must_equal [7, 9]
    end
  end
end
