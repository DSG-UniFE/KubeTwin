# frozen_string_literal: true

require 'minitest_helper'

# KubeScheduler is a small, self-contained piece of the scheduling/allocation
# logic the roadmap calls out for coverage: given a set of clusters (each
# holding some Nodes), it filters out nodes that can't fit a pod's resource
# request and then scores/picks one candidate node. Unlike KSimulation's
# giant evaluate_allocation event loop, this class has no simulation-clock
# or event-queue dependency, so it can be exercised directly with a couple
# of hand-built Cluster/Node fixtures.
describe KUBETWIN::KubeScheduler do

  def build_cluster(id:, tier:, node_number: 1, node_resources_cpu: 100, node_resources_memory: 100)
    KUBETWIN::Cluster.new(id: id,
                          fixed_hourly_cost_cpu: 1.0,
                          fixed_hourly_cost_memory: 1.0,
                          location_id: 0,
                          name: id.to_s,
                          type: :cloud,
                          tier: tier,
                          node_number: node_number,
                          node_resources_cpu: node_resources_cpu,
                          node_resources_memory: node_resources_memory)
  end

  def add_node(cluster, node_id, resources_cpu: 100, resources_memory: 100, type: :cloud)
    node = KUBETWIN::Node.new(node_id, resources_cpu, resources_memory, cluster.cluster_id, type)
    cluster.add_node(node)
    node
  end

  it 'returns nil when no node has enough free resources' do
    small = build_cluster(id: :small, tier: :cloud)
    add_node(small, 'small-1', resources_cpu: 1, resources_memory: 1)

    scheduler = KUBETWIN::KubeScheduler.new(small.cluster_id => small)

    _(scheduler.get_node(50, 50, nil)).must_be_nil
  end

  it 'filters out nodes that cannot fit the requested resources' do
    cluster = build_cluster(id: :c1, tier: :cloud)
    too_small = add_node(cluster, 'too-small', resources_cpu: 10, resources_memory: 10)
    big_enough = add_node(cluster, 'big-enough', resources_cpu: 100, resources_memory: 100)

    scheduler = KUBETWIN::KubeScheduler.new(cluster.cluster_id => cluster)

    node = scheduler.get_node(50, 50, nil)

    _(node).must_equal big_enough
    refute_equal too_small, node
  end

  it 'prefers a node matching the requested node affinity (tier) when one is available' do
    mec_cluster   = build_cluster(id: :mec, tier: :mec)
    cloud_cluster = build_cluster(id: :cloud, tier: :cloud)
    mec_node   = add_node(mec_cluster, 'mec-1')
    cloud_node = add_node(cloud_cluster, 'cloud-1')

    scheduler = KUBETWIN::KubeScheduler.new(mec_cluster.cluster_id => mec_cluster,
                                            cloud_cluster.cluster_id => cloud_cluster)

    node = scheduler.get_node(10, 10, :mec)

    _(node).must_equal mec_node
  end

  it 'falls back to any fitting node when no node matches the requested affinity' do
    cloud_cluster = build_cluster(id: :cloud, tier: :cloud)
    cloud_node = add_node(cloud_cluster, 'cloud-1')

    scheduler = KUBETWIN::KubeScheduler.new(cloud_cluster.cluster_id => cloud_cluster)

    # :mec affinity requested, but only a :cloud-tier node exists
    node = scheduler.get_node(10, 10, :mec)

    _(node).must_equal cloud_node
  end

  it 'prefers the node with the most available CPU among affinity matches' do
    cluster = build_cluster(id: :c1, tier: :mec)
    busy_node  = add_node(cluster, 'busy',  resources_cpu: 100, resources_memory: 100)
    quiet_node = add_node(cluster, 'quiet', resources_cpu: 100, resources_memory: 100)
    # eat up most of busy_node's CPU so quiet_node has more room left
    busy_node.assign_resources(Struct.new(:pod_id).new('filler'), 90, 0)

    scheduler = KUBETWIN::KubeScheduler.new(cluster.cluster_id => cluster)

    node = scheduler.get_node(5, 5, :mec)

    _(node).must_equal quiet_node
  end

  describe '#get_node_from_cluster' do
    it 'restricts candidate nodes to the requested cluster_id' do
      c1 = build_cluster(id: :c1, tier: :cloud)
      c2 = build_cluster(id: :c2, tier: :cloud)
      node_c1 = add_node(c1, 'c1-node')
      add_node(c2, 'c2-node')

      scheduler = KUBETWIN::KubeScheduler.new(c1.cluster_id => c1, c2.cluster_id => c2)

      _(scheduler.get_node_from_cluster(10, 10, :c1)).must_equal node_c1
    end

    it 'scores across all clusters when cluster_id is :none' do
      c1 = build_cluster(id: :c1, tier: :cloud)
      node_c1 = add_node(c1, 'c1-node')

      scheduler = KUBETWIN::KubeScheduler.new(c1.cluster_id => c1)

      _(scheduler.get_node_from_cluster(10, 10, :none)).must_equal node_c1
    end
  end

end
