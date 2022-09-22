# frozen_string_literal: true


require_relative './logger'
require_relative './event'

module KUBETWIN

  class RequestInfo < Struct.new(:request, :service_time, :arrival_time)
    include Comparable
    def <=>(o)
      arrival_time <=> o.arrival_time
    end
    end

  class Container
    # states
    CONTAINER_WAITING      = 0      # still running the operations it requires in order to complete start up
    CONTAINER_RUNNING      = 1      # executing without issues
    CONTAINER_TERMINATED   = 2      # began execution and then either ran to completion or failed for some reason

    # no need for :port now
    attr_reader :containerId,
                :imageId,
                :endCode, 
                :state,
                :service_time,
                :served_request,
                :total_queue_time,
                :total_queue_processing_time # endCode = 0 if all operations successfull, 0 if there's any kind of error

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

      unless opts[:blocking].nil?
        @blocking = opts[:blocking]
      else
        @blocking = true
      end

      # node info
      @node = opts[:node]

      # seed should alreay be here
      @service_time = ERV::RandomVariable.new(st_distribution)
      @busy           = false
      @request_queue  = [] # queue incoming requests

      @trace = opts[:trace] ? true : false
      @working_time = 0.0
      # metric info -- first implementation

      @served_request = 0
      @total_queue_processing_time = 0
      @total_queue_time = 0
    end

    def reset_metrics
      @served_request = 0
      @total_queue_processing_time = 0
      @total_queue_time = 0
    end

    def startupC
      #sleep(0.002)
      @state = Container::CONTAINER_RUNNING
    end

    def new_request(sim, r, time)

      # improve this code in the future
      r.arrival_at_container = time

      while (st = @service_time.next) <= 1E-6; end
      # remove truncation --- just to make the optimizer runnings
      #st = @service_time.next
      #st = 1E-6 if st < 1E-6

      # add concurrent execution
      #pod_executing = @node.pod_id_list.length
      #st *= Math::log(pod_executing) if pod_executing > 2
      
      ri = RequestInfo.new(r, st, time)
      @request_queue << ri

      if @trace
        @request_queue.each_cons(2) do |x, y|
          raise 'Inconsistent ordering in request_queue!' if y[1] < x[1]
        end
      end

      #puts "#{containerId} #{@request_queue.length} #{st}}" if @request_queue.length > 1

      try_servicing_new_request(sim, time) unless @busy
    end

    def request_finished(sim, time)
      @busy = false
      # update also the metrics
      @served_request += 1
      try_servicing_new_request(sim, time) unless @busy
    end

    def try_servicing_new_request(sim, time) 
      
      if @busy
        raise "Container is currently processing another request (id: #{@containerId})"
      end

      unless @request_queue.empty? # || (@state == Container::CONTAINER_TERMINATED)
        
        # monkey patch for MQTT service
        if @blocking == true
          @busy = true
        else
          @busy = false
        end

        ri = @request_queue.shift
        # nc = r.service_time

        # here simulate service time based on cpu and on a random noise
        # service_time_request = (nc / @guaranteed.cpu) + @service_noise_rv.sample
        # just implement service_time for now

        if @trace
          logger.info "Container #{@containerId} fulfilling a new request at time #{time} for #{service_time_request} seconds"
        end
        
        req = ri.request
        # update the request's working information

        # this is somehow wrong --- need to fix it
        req.update_queuing_time(time - ri.arrival_time)

        req.step_completed(ri.service_time)

        # update container-based metric here
        @total_queue_time += time - ri.arrival_time
        # raise "We are looking at two different times" if req.queuing_time != (time - ri.arrival_time)
        @total_queue_processing_time += ri.service_time + (time - ri.arrival_time)
        # + req.queuing_time # does the queueing time also contain 
        # the queue time for the previous request? yes 
        # fixed
        # schedule completion of workflow step
        sim.new_event(Event::ET_WORKFLOW_STEP_COMPLETED, req, time + ri.service_time, self)
      end
    end

    def request_resources(moreCpu)
      if @state == CONTAINER_RUNNING
        raise 'Impossible assign resources, container is still running'
        end

      @guaranteed.cpu += moreCpu
      if @guaranteed.cpu > @limits.cpu
        raise 'CPU limits error, too much resources in request'
        end

      @state = CONTAINER_WAITING

      'Resources assigned, waiting for setup...'
      startupC
    end

  # ending module
  end
end
