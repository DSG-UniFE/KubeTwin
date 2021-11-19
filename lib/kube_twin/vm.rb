# frozen_string_literal: true

require_relative './event'
require_relative './logger'
require 'erv'

class RequestInfo < Struct.new(:request, :service_time, :arrival_time)
  include Comparable
  def <=>(o)
    arrival_time <=> o.arrival_time
  end
end

module KUBETWIN

  class VM
    include Logging

    # setup readable/accessible attributes
    attr_reader :vmid, :dc_id, :size

    def initialize(vmid, dc_id, size, service_time_distribution, opts={})
      @vmid             = vmid
      @dcid             = dc_id
      @size             = size
      @service_times_rv = if opts[:seed]
        orig_std_conf = service_time_distribution[@size]
        std_conf = orig_std_conf.dup
        std_conf[:args] = orig_std_conf[:args].merge(seed: opts[:seed])
        ERV::RandomVariable.new(std_conf)
      else 
        ERV::RandomVariable.new(service_time_distribution[@size])
      end

      # initialize request queue and related tracking information
      @busy          = false
      @request_queue = []

      @trace = opts[:trace] ? true : false
      @notes = opts[:notes]

      # @request_queue_info          = []
      # @request_currently_servicing = nil
    end

    def new_request(sim, r, time)
      # put request w/ metadata at the end of the queue
      @request_queue << RequestInfo.new(r, @service_times_rv.next, time)

      if @trace
        @request_queue.each_cons(2) do |x,y|
          if y[2] < x[2]
            raise "Inconsistent ordering in request_queue!!!!"
          end
        end
      end

      # update queue size tracking information
      # @request_queue_info << { size: @request_queue.size, time: time }
      if @trace and @request_queue.size % 100 == 0
        logger.info "VM #{@vmid} with #{@notes} has #{@request_queue.size} requests in queue at time #{time} and is " +
           (@busy ? "busy" : "not busy")
      end

      try_servicing_new_request(sim, time) unless @busy
    end

    def request_finished(sim, time)
      @busy = false
      try_servicing_new_request(sim, time)
    end

    # def suspend(time)
    #   raise "VM is already suspended!" if @suspended
    #   @request_currently_servicing.finishing_time =
    #   @request_currently_servicing.status = Request::STATE_WORKING
    # end

    # def resume(time)
    #   raise "VM is already working!" unless @suspended
    # end

    private

      def try_servicing_new_request(sim, time)
        raise "Busy VM (vmid: #{@vmid})!" if @busy

        unless @request_queue.empty?

          # pick request and metadata from the incoming request queue
          ri = @request_queue.shift

          if @trace
            logger.info "VM #{@vmid} with #{@notes} fulfilling a new request at time #{time} for #{ri.service_time} seconds"
          end

          req = ri.request

          # update the request's queuing information
          req.update_queuing_time(time - ri.arrival_time)

          # update the request's working information
          req.step_completed(ri.service_time)

          # schedule completion of workflow step
          sim.new_event(Event::ET_WORKFLOW_STEP_COMPLETED, req, time + ri.service_time, self)
        end
      end

  end

end
