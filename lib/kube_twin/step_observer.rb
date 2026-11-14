# frozen_string_literal: true

module KUBETWIN
  # Collects what happens between two observations of a stepped simulation
  # (see Twin#observe): requests reaching each placement (a service's pods in
  # one cluster), network latencies between clusters, and workflow arrivals
  # and completions. KSimulation feeds it as events happen; #snapshot
  # summarizes the window that just ended and starts a new one.
  #
  # Only counters and this window's samples are kept, so memory doesn't grow
  # with the length of the run.
  class StepObserver
    # Running totals for one placement; containers update them directly.
    PlacementCounters = Struct.new(:arrivals, :started, :queue_time, :service_time) do
      def initialize = super(0, 0, 0.0, 0.0)

      def clear
        self.arrivals = self.started = 0
        self.queue_time = self.service_time = 0.0
      end

      def request_arrived
        self.arrivals += 1
      end

      def request_started(queue_time, service_time)
        self.started += 1
        self.queue_time += queue_time
        self.service_time += service_time
      end
    end

    def initialize
      @placements = Hash.new { |h, k| h[k] = PlacementCounters.new }
      @link_latencies = Hash.new { |h, k| h[k] = [] }
      @workflow_arrivals = Hash.new(0)
      @workflow_responses = Hash.new { |h, k| h[k] = [] }
      # cluster => cluster => link id, so recording a latency allocates nothing
      @link_ids = Hash.new { |h, a| h[a] = Hash.new { |g, b| g[b] = self.class.link_id(a, b) } }
    end

    # The counters for `service`'s pods in `cluster_id`.
    def placement(service, cluster_id)
      @placements[[service, cluster_id]]
    end

    # A message crossed between two clusters, taking `latency` seconds.
    # Latencies within a cluster aren't recorded.
    def link_latency(cluster_a, cluster_b, latency)
      return if cluster_a == cluster_b

      @link_latencies[@link_ids[cluster_a][cluster_b]] << latency
    end

    def workflow_arrival(workflow)
      @workflow_arrivals[workflow] += 1
    end

    # A request of `workflow` completed after `response_time` seconds.
    def workflow_completion(workflow, response_time)
      @workflow_responses[workflow] << response_time
    end

    # The unordered pair of clusters a link joins, in a stable order.
    def self.link_id(cluster_a, cluster_b)
      [cluster_a, cluster_b].sort_by(&:to_s)
    end

    # This window's data, then a fresh window: placement counters
    # ({[service, cluster_id] => PlacementCounters}), link latency samples,
    # and workflow arrivals and response times.
    def snapshot
      placements = @placements.transform_values(&:dup)
      @placements.each_value(&:clear)

      window = {placements:, link_latencies: @link_latencies, workflow_arrivals: @workflow_arrivals,
                workflow_responses: @workflow_responses}
      @link_latencies = Hash.new { |h, k| h[k] = [] }
      @workflow_arrivals = Hash.new(0)
      @workflow_responses = Hash.new { |h, k| h[k] = [] }
      window
    end
  end
end
