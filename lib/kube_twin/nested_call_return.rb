# frozen_string_literal: true

module KUBETWIN
  # The routing decision behind KSimulation#nested_return_latency: once a
  # nested call (dispatched via #dispatch_nested_call) finishes, where does
  # the *parent* request's waiting container live, and how long is the trip
  # back from wherever the child ended up. Same shape and same reasoning as
  # RequestForwarder for the outbound leg -- constructor-injected with just
  # cluster_repository (no kube_dns needed here; there's no service lookup
  # on the way back, just cluster resolution), no mutation, no event
  # scheduling. Unit-tested directly (spec/kube_twin/nested_call_return_spec.rb)
  # with hand-built Cluster/Node/Pod fixtures.
  class NestedCallReturn
    Return = Struct.new(:latency, :parent_cluster, :child_cluster)

    def initialize(cluster_repository:)
      @cluster_repository = cluster_repository
    end

    # parent_container is the parent request's nested_waiting_container
    # (nil if it has none -- see the guard at nested_return_latency's call
    # site). child_cluster_id is the child request's current data_center_id.
    def resolve(parent_container, child_cluster_id, latency_manager)
      return nil if parent_container.nil?

      parent_cluster = @cluster_repository[parent_container.instance_variable_get(:@node).cluster_id]
      child_cluster = @cluster_repository[child_cluster_id]
      latency = latency_manager.sample_latency_between(child_cluster.location_id, parent_cluster.location_id)

      Return.new(latency, parent_cluster, child_cluster)
    end
  end
end
