# frozen_string_literal: true

require "minitest_helper"

# NestedCallReturn holds the routing decision extracted out of
# KSimulation#nested_return_latency: once a nested call (dispatched via
# #dispatch_nested_call) finishes, where does the parent request's waiting
# container live, and how long is the trip back from wherever the child
# ended up. Constructor-injected with just cluster_repository -- there's no
# service lookup on the way back, so unlike RequestForwarder this doesn't
# need kube_dns at all -- and tested directly here with hand-built
# Cluster/Node/Pod fixtures (no gem dependencies, no running simulation).
# The mutation that used to sit right next to this logic
# (parent_req.update_transfer_time, data_center_id=, trace_request) stays
# in KSimulation -- see the comment at nested_return_latency's definition
# for how the two pieces fit together.
describe KUBETWIN::NestedCallReturn do
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
  # whichever node.type key is present (see request_forwarder_spec.rb for
  # the same requirement and examples/parallel-working-test.conf for the
  # same shape in a real config).
  def build_pod(node, label)
    image_info = {node_affinity: nil, blocking: false, max_processes: 1,
                  resources_requirements_cpu: 100, resources_requirements_memory: 100,
                  service_time_distribution: {
                    node.type => {distribution: :gaussian, args: {mean: 0.015, sd: 0.0015, seed: 12_345}}
                  }}
    KUBETWIN::Pod.new(rand(100_000), "#{label}_pod", node, label, image_info)
  end

  describe "#resolve" do
    it "returns nil when parent_container is nil" do
      resolver = KUBETWIN::NestedCallReturn.new(cluster_repository: {})
      result = resolver.resolve(nil, 0, Object.new)
      _(result).must_be_nil
    end

    it "resolves parent_cluster from the container's node and child_cluster from child_cluster_id" do
      cluster_child = build_cluster(:child, location_id: 3)
      cluster_parent = build_cluster(:parent, location_id: 8)
      parent_node = build_node(cluster_parent, "parent-1")
      parent_pod = build_pod(parent_node, "productpage")
      parent_container = parent_pod.container

      cluster_repository = {cluster_child.cluster_id => cluster_child, cluster_parent.cluster_id => cluster_parent}
      resolver = KUBETWIN::NestedCallReturn.new(cluster_repository: cluster_repository)
      latency_manager = Object.new
      latency_manager.define_singleton_method(:sample_latency_between) { |_src, _dst| 0.042 }

      result = resolver.resolve(parent_container, cluster_child.cluster_id, latency_manager)

      _(result).wont_be_nil
      _(result.latency).must_equal 0.042
      _(result.parent_cluster).must_be_same_as cluster_parent
      _(result.child_cluster).must_be_same_as cluster_child
    end

    it "samples latency with child location_id as source and parent location_id as destination" do
      cluster_child = build_cluster(:child, location_id: 11)
      cluster_parent = build_cluster(:parent, location_id: 22)
      parent_node = build_node(cluster_parent, "parent-1")
      parent_pod = build_pod(parent_node, "productpage")
      parent_container = parent_pod.container

      cluster_repository = {cluster_child.cluster_id => cluster_child, cluster_parent.cluster_id => cluster_parent}
      resolver = KUBETWIN::NestedCallReturn.new(cluster_repository: cluster_repository)

      seen_args = nil
      spy = Object.new
      spy.define_singleton_method(:sample_latency_between) do |src, dst|
        seen_args = [src, dst]
        0.1
      end

      resolver.resolve(parent_container, cluster_child.cluster_id, spy)
      _(seen_args).must_equal [11, 22]
    end
  end
end
