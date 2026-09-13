# frozen_string_literal: true

module KUBETWIN
  # The routing *decision* behind KSimulation#schedule_request_forward and
  # #dispatch_nested_call: given a component name, where (which pod, on
  # which cluster) would this request go next, and how long would that
  # take. Constructor-injected with just the two read-only registries the
  # decision actually needs -- kube_dns (service discovery) and
  # cluster_repository (cluster_id -> Cluster) -- rather than reaching into
  # a KSimulation instance, so it can be unit-tested directly with fake
  # KubeDns/Service/Pod/Node/Cluster fixtures and a stub latency_manager
  # (spec/kube_twin/request_forwarder_spec.rb), no gem dependencies and no
  # running simulation required.
  #
  # #route deliberately stops at "here is where it would go and what it
  # would cost" and does not mutate anything or schedule any event -- that
  # part (req.update_transfer_time, trace_request, @forwarded, new_event)
  # stays in KSimulation, which is where that simulation state actually
  # lives (same split as HorizontalPodAutoscaler#decide_scaling).
  class RequestForwarder
    Route = Struct.new(:pod, :cluster, :transmission_time, :forwarding_time)

    def initialize(kube_dns:, cluster_repository:)
      @kube_dns = kube_dns
      @cluster_repository = cluster_repository
    end

    # Returns a Route (pod, cluster, transmission_time, forwarding_time)
    # if component_name resolves to a live pod, or nil if there's no
    # service registered for it, or no pod currently assigned to it (the
    # two "can't route this" cases the original inline code handled by
    # returning false).
    def route(component_name, source_cluster, latency_manager, base_time)
      service = @kube_dns.lookup(component_name)
      return nil if service.nil?

      pod = service.get_pod(component_name)
      return nil if pod.nil?

      cluster = @cluster_repository[pod.node.cluster_id]
      transmission_time = latency_manager.sample_latency_between(source_cluster.location_id, cluster.location_id)

      Route.new(pod, cluster, transmission_time, base_time + transmission_time)
    end
  end
end
