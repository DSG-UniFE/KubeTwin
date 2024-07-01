# frozen_string_literal: true


require_relative './logger'
require_relative './event'
require 'pycall'
require 'pycall/import'
include PyCall::Import


module KUBETWIN

  class RequestInfo < Struct.new(:request, :service_time, :arrival_time)
    include Comparable
    def <=>(o)
      arrival_time <=> o.arrival_time
    end
  end

  class Container

    SEED = 123
    #pyfrom :tensorflow, import: :keras
    #pyfrom :sklearn, import: :mixture

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
                :containers_to_free,
                :busy,
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
      @name = opts[:label]

      unless opts[:blocking].nil?
        @blocking = opts[:blocking]
      else
        @blocking = true
      end

      # node info
      @node = opts[:node]
      @wait_for = opts[:img_info][:wait_for].nil? ? [] : opts[:img_info][:wait_for]

      @busy           = false
      @request_queue  = [] # queue incoming requests

      @trace = opts[:trace] ? true : false
      @working_time = 0.0
      # metric info -- first implementation
      @containers_to_free = []

      @served_request = 0
      @total_queue_processing_time = 0
      @total_queue_time = 0
      @last_request_time = nil
      @path = opts[:img_info][:mdn_file]
      @rps = opts[:img_info][:rps].to_f
      @replica = opts[:img_info][:replica].to_i
      @service_time = nil
      @arrival_times = []
      @service_time = ERV::RandomVariable.new(st_distribution) if @path.nil?
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
    end

    def check_rps(interval=8)
      #@arrival_times.last(interval).reverse.inject(:-) / interval.to_f
      i = 0
      interarrival_times = 0.0
      @arrival_times.last(interval).reverse.each_slice(2) do |t,tl|
        break if t.nil? || tl.nil?
        #puts "t: #{t} tl: #{tl}"
        i += 1
        interarrival_times += t - tl
      end
      return interarrival_times / i.to_f
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
      @arrival_times << time
      # begin was here
      # end was here
      #rps = @rps
      #puts "RPS: #{rps}"
      @last_request_time = time
      s_time = calculate_service_time(sim)
      @logger.debug "Container #{@name}, service_time: #{s_time}"

      ri = RequestInfo.new(r, s_time, time)
      # Setting a maximum queue size
      @logger.debug "Container #{@name}:#{@containerId} queue size: #{@request_queue.size}"
      #if @request_queue.size >= 20
      #  @logger.debug "Queue size exceeded for container #{@name}"
      #  return 
      #end 
      
      @request_queue << ri
      
      if @trace
        puts "***"
        @request_queue.each_cons(2) do |x, y|
          puts "#{x[2]},#{y[2]},#{y[2]-x[2]}"
          raise 'Inconsistent ordering in request_queue!' if y[2] < x[2]
        end
        puts "***"
      end
      #puts "Request #{r.rid} arrived at container #{@containerId} at #{time} --> busy: #{@busy}"
      try_servicing_new_request(sim, time) unless @busy
    end

    def request_finished(sim, time)
      @busy = false
      # update also the metrics
      @logger.debug "Container #{@name} is now busy: #{@busy}"
      #puts "Request finished at #{time} --> busy: #{@busy}"
      @served_request += 1
      try_servicing_new_request(sim, time) unless @busy
    end

    def calculate_service_time(sim)
      unless @path.nil?
        if @arrival_times.length < 2
          rps = 0.2 # default value for the current use-case
        else
          inter_arrival_times = check_rps
          #@logger.info "Inter_Arrival_time; #{inter_arrival_times}"
          if inter_arrival_times == 0.0
            rps = 0.2 # default value for the current use-case
          else
            begin
              #rps = (1 / inter_arrival_times).ceil
              rps = (1 / inter_arrival_times.to_f)
              # ceil the rps to the second decimal digit
              rps = rps.round(1)
            rescue
              puts inter_arrival_times
              abort
            end
          end
        end
        @logger.debug("Name: #{@name} Retrieved RPS: #{rps}")
        rps = 34 if rps > 34
      end
      if @name == 'FE1' 
        @logger.debug "Container #{@name} RPS: #{rps}"
      end 
      @service_time = sim.retrieve_mdn_model(@name, rps, @replica) unless @path.nil?
      while (st = @service_time.sample) <= 1E-6; end
      case @name
      when 'FE1'
        st *= 0.43
      when 'FE2'
        st *= 0.36
      when 'FE3'
        st *= 0.21
      else
        st
      end
      st
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
        req = ri.request
        # update the request's working information
        #req.update_queuing_time(time - ri.arrival_time)
        req.update_queuing_time(time - req.arrival_at_container)
        #s_time = calculate_service_time(sim)
        req.step_completed(ri.service_time)
        next_step = req.next_step

        # update container-based metric here
        @total_queue_time += time - ri.arrival_time
        # raise "We are looking at two different times" if req.queuing_time != (time - ri.arrival_time)
        @total_queue_processing_time += ri.service_time + (time - ri.arrival_time)
        # schedule completion of workflow step
        sim.new_event(Event::ET_WORKFLOW_STEP_COMPLETED, [req, next_step], time + ri.service_time, self)

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

      puts 'Resources assigned, waiting for setup...'
      startupC
    end

  end
end
