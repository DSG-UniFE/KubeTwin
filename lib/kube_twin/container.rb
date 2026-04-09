# frozen_string_literal: true

require_relative './logger'
require_relative './event'

module KUBETWIN
  class RequestInfo < Struct.new(:request, :service_time, :arrival_time)
    include Comparable
    def <=>(other)
      arrival_time <=> other.arrival_time
    end
  end

  class Container
    SEED = 123

    # states
    CONTAINER_WAITING      = 0      # still running the operations it requires in order to complete start up
    CONTAINER_RUNNING      = 1      # executing without issues
    CONTAINER_TERMINATED   = 2      # began execution and then either ran to completion or failed for some reason

    # no need for :port now
    attr_reader :containerId,
                :imageId,
                :endCode,
                :name,
                :state,
                :wait_for,
                :service_time,
                :request_queue,
                :served_request,
                :total_queue_time,
                :total_queue_processing_time,
                :max_processes,
                :active_processes,
                :max_concurrent_processes_used # endCode = 0 if all operations successfull, 0 if there's any kind of error

    Guaranteed = Struct.new(:cpu, :memory)
    Limits = Struct.new(:cpu, :memory)

    def initialize(containerId, imageId, st_distribution, opts = {})
      @containerId = containerId
      @imageId = imageId
      @state = Container::CONTAINER_WAITING
      @limits = Limits.new(500, 500)
      @guaranteed = Guaranteed.new(500, 500)
      @startedTime = Time.now
      @state = CONTAINER_WAITING
      @name = opts[:label]

      @blocking = opts[:blocking].nil? || opts[:blocking]

      # node info
      @node = opts[:node]
      @wait_for = opts[:img_info][:wait_for].nil? ? [] : opts[:img_info][:wait_for]

      @active_processes = 0
      @max_processes = opts[:max_processes] || 1
      @request_queue = [] # queue incoming requests

      @trace = opts[:trace] ? true : false
      @working_time = 0.0
      # metric info -- first implementation
      @containers_to_free = []

      @served_request = 0
      @total_queue_processing_time = 0
      @total_queue_time = 0
      @last_request_time = nil
      @path = opts[:img_info][:mdn_file]
      @rps = opts[:img_info][:rps].to_i
      @service_time = ERV::RandomVariable.new(st_distribution) if @path.nil?
      @arrival_times = []
      @max_concurrent_processes_used = 0
    end

    def current_rps
      return @rps if @arrival_times.empty?

      window = 10.0 # 10 second window
      now = @arrival_times.last || 0
      recent = @arrival_times.select { |t| t > now - window }
      return @rps if recent.size < 2

      # RPS = number of arrivals in window / window duration
      recent.size / window
    end

    def utilization
      return 0 if @max_processes == 0

      @active_processes.to_f / @max_processes
    end

    def queue_load
      (@request_queue.size + @active_processes).to_f / [@max_processes, 1].max
    end

    def to_free(container)
      # add a chained container, which must wait
      # until the next workflow step is completed
      @containers_to_free << container
    end

    def free_linked_container
      # return the reference to the container
      # which was waiting the next step to be
      # completed
      @containers_to_free.shift
    end

    def reset_metrics
      @served_request = 0
      @total_queue_processing_time = 0
      @total_queue_time = 0
    end

    def startupC
      @state = Container::CONTAINER_RUNNING
    end

    def new_request(sim, r, time)
      # improve this code in the future
      r.arrival_at_container = time

      # Track arrival time for RPS calculation
      @arrival_times << time

      # Keep only last 60 seconds of arrivals to avoid memory growth
      @arrival_times.shift while @arrival_times.any? && @arrival_times.first < time - 60

      # Determine RPS: use dynamic RPS if available, otherwise fallback to static
      rps = if @path.nil?
              @rps
            else
              # Use dynamic RPS from traffic if we have enough data, else use static
              computed_rps = current_rps
              computed_rps > 0 ? computed_rps.to_i : @rps
            end

      @last_request_time = time
      # Retrieve MDN model with computed RPS if so
      if @path.nil?
        while (st = @service_time.sample) <= 1E-6; end
      else
        @service_time = sim.retrieve_mdn_model(name, rps)
        st = @service_time.forward(rps)
      end

      ri = RequestInfo.new(r, st, time)
      @request_queue << ri

      if @trace
        puts '***'
        @request_queue.each_cons(2) do |x, y|
          puts "#{x[2]},#{y[2]},#{y[2] - x[2]}"
          raise 'Inconsistent ordering in request_queue!' if y[2] < x[2]
        end
        puts '***'
      end

      try_servicing_new_request(sim, time) while @active_processes < @max_processes && !@request_queue.empty?
    end

    def request_finished(sim, time)
      @active_processes -= 1 if @active_processes > 0
      # update also the metrics
      @served_request += 1

      # Check if this is a parallel branch request
      if respond_to?(:is_parallel_branch?) && is_parallel_branch?
        # Get parent request and branch name
        parent_request = instance_variable_get(:@parent_request)
        branch_name = instance_variable_get(:@branch_name)

        # Schedule parallel branch completion event
        sim.new_event(Event::ET_PARALLEL_BRANCH_COMPLETED,
                      { request: parent_request, branch_name: branch_name, result: 'branch_result' },
                      time, nil)
      end

      try_servicing_new_request(sim, time) while @active_processes < @max_processes && !@request_queue.empty?
    end

    def try_servicing_new_request(sim, time)
      if @active_processes >= @max_processes
        return # No capacity available
      end

      return if @request_queue.empty? # || (@state == Container::CONTAINER_TERMINATED)

      # monkey patch for MQTT service
      if @blocking == true
        @active_processes += 1
        @max_concurrent_processes_used = [@max_concurrent_processes_used, @active_processes].max
      else
        # For non-blocking services, don't count against process limit
        @active_processes += 1 unless @max_processes == Float::INFINITY
        unless @max_processes == Float::INFINITY
          @max_concurrent_processes_used = [@max_concurrent_processes_used,
                                            @active_processes].max
        end
      end
      # puts "Start: #{time}"
      ri = @request_queue.shift
      # puts "#{containerId} #{@request_queue.length} sr: #{served_request} #{time - ri.arrival_time}" if @request_queue.length > 2

      req = ri.request
      # update the request's working information

      # req.update_queuing_time(time - ri.arrival_time)
      req.update_queuing_time(time - req.arrival_at_container)

      req.step_completed(ri.service_time)

      # update container-based metric here
      @total_queue_time += time - ri.arrival_time
      # raise "We are looking at two different times" if req.queuing_time != (time - ri.arrival_time)
      @total_queue_processing_time += ri.service_time + (time - ri.arrival_time)
      # schedule completion of workflow step
      # puts "Finished #{time + ri.service_time} #{@request_queue.length}"
      sim.new_event(Event::ET_WORKFLOW_STEP_COMPLETED, req, time + ri.service_time, self)
    end

    def request_resources(moreCpu)
      raise 'Impossible assign resources, container is still running' if @state == CONTAINER_RUNNING

      @guaranteed.cpu += moreCpu
      raise 'CPU limits error, too much resources in request' if @guaranteed.cpu > @limits.cpu

      @state = CONTAINER_WAITING

      puts 'Resources assigned, waiting for setup...'
      startupC
    end
  end
end
