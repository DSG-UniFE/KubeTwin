
#require 'dry-validation'
#require 'dry-auto_inject'
require_relative './logger'
require_relative './event'

module SISFC
    
    class RequestInfo < Struct.new(:request, :service_time, :arrival_time)
        include Comparable
        def <=>(o)
          arrival_time <=> o.arrival_time
        end
      end

    class Container
        
        #states
        CONTAINER_WAITING      = 0      #still running the operations it requires in order to complete start up
        CONTAINER_RUNNING      = 1      #executing without issues
        CONTAINER_TERMINATED   = 2      #began execution and then either ran to completion or failed for some reason


        attr_reader :containerId, :imageId, :port, :endCode #endCode = 0 if all operations successfull, 0 if there's any kind of error
        Guaranteed = Struct.new(:cpu, :memory)
        Limits = Struct.new(:cpu, :memory)
        
        def initialize(containerId, imageId, port, opts={})
            @containerId        = containerId
            @imageId            = imageId
            @port               = port
            @state              = Container::CONTAINER_WAITING
            @limits             = Limits.new(500, 500)
            @guaranteed         = Guaranteed.new(500, 500)
            @startedTime        = Time.now
            
            @service_n_cycles = if opts[:n_cycles]
                opts[:n_cycles]
            else
                rand(1..10)
            end

            #@service_noise
            
            @busy           = false
            @request_queue     = []

            @trace = opts[:trace] ? true : false
            @working_time   = 0.0
        
        end


        def startupC
            sleep(0.002)
            @state = Container::CONTAINER_RUNNING
        end


        def new_request(sim, r, time)
            @request_queue << RequestInfo.new(r, @service_n_cycles.next, time)

            if @trace
                @request_queue.each_cons(2) do |x,y|
                  if y[1] < x[1]
                    raise "Inconsistent ordering in request_queue!"
                  end
                end
            end

            try_servicing_new_request(sim, time) unless @busy
        end
        

        def try_servicing_new_request(sim, time)
            raise "Container not available (id: #{@containerId})" if @state != Container::CONTAINER_RUNNING or @busy
            
            unless @request_queue.empty? or @state == Container::CONTAINER_TERMINATED
                r = @request_queue.shift

                nc = r.service_time
                service_time_request = nc/@guaranteed.cpu

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
            raise "Impossible assign resources, container is still running" if @state == CONTAINER_RUNNING

            @guaranteed.cpu += moreCpu
            raise "CPU limits error, too much resources in request" if @guaranteed.cpu > @limits.cpu 
            @state = CONTAINER_WAITING
            
            "Resources assigned, waiting for setup..."
            startupC
        end

    end
     
end