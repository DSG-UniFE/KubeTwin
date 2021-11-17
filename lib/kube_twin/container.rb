# frozen_string_literal: true

# require 'dry-validation'
# require 'dry-auto_inject'
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
    attr_reader :containerId, :imageId, :endCode, :state # endCode = 0 if all operations successfull, 0 if there's any kind of error

    Guaranteed = Struct.new(:cpu, :memory)
    Limits = Struct.new(:cpu, :memory)

    def initialize(containerId, imageId, image_info, opts = {})
      @containerId = containerId
      @imageId = imageId
      @state = Container::CONTAINER_WAITING
      @limits = Limits.new(500, 500)
      @guaranteed = Guaranteed.new(500, 500)
      @startedTime = Time.now
      @state = CONTAINER_WAITING

      # retrieving image info here
      # n_cycle and noise distribution
      @service_n_cycles = image_info[:service_n_cycles]
      snd = image_info[:service_noise_rv]

      @service_noise_rv = if snd[:seed]
                            orig_std_conf = snd
                            std_conf = orig_std_conf.dup
                            std_conf[:args] = orig_std_conf[:args].merge(seed: opts[:seed])
                            ERV::RandomVariable.new(std_conf)
                          else
                            ERV::RandomVariable.new(snd)
      end

      @busy           = false
      @request_queue  = [] # queue incoming requests

      @trace = opts[:trace] ? true : false
      @working_time = 0.0
    end

    def startupC
      #sleep(0.002)
      @state = Container::CONTAINER_RUNNING
    end

    def new_request(sim, r, time)
      @request_queue << RequestInfo.new(r, @service_n_cycles.next, time)

      if @trace
        @request_queue.each_cons(2) do |x, y|
          raise 'Inconsistent ordering in request_queue!' if y[1] < x[1]
        end
      end

      try_servicing_new_request(sim, time) unless @busy
    end

    def try_servicing_new_request(sim, time)
      if (@state != Container::CONTAINER_RUNNING) || @busy
        raise "Container not available (id: #{@containerId})"
        end

      unless @request_queue.empty? || (@state == Container::CONTAINER_TERMINATED)
        r = @request_queue.shift

        nc = r.service_time

        # here simulate service time based on cpu and on a random noise
        service_time_request = (nc / @guaranteed.cpu) + @service_noise_rv.sample

        if @trace
          logger.info "Container #{@containerId} fulfilling a new request at time #{time} for #{service_time_request} seconds"
        end

        # update the request's working information
        r.update_queuing_time(time - r.arrival_time)

        r.step_completed(service_time_request)

        # schedule completion of workflow step
        sim.new_event(Event::ET_WORKFLOW_STEP_COMPLETED, nc, time + working_time, self)

      end

      @endCode = 0
      @state   = Container::CONTAINER_TERMINATED
      @busy    = false
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
  end
end
