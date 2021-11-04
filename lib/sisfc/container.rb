
require 'dry-validation'
require 'dry-auto_inject'
require_relative './logger'
require_relative './event'
require_relative './request'

module SISFC
    
    class Limits < Dry::Validation::Contract
        params do 
            required(:cpu).filled(:integer)
            required(:memory).filled(:integer)
        end
    
        rule(:cpu) {key.failure("No Cpu limit") if value <= 0}
        rule(:memory) {key.failure("No memory limit") if value <= 0}
    end

    class Guaranteed < Dry::Validation::Contract
        params do
            required(:cpu).filled(:integer)
            required(:memory).filled(:integer)
        end

        rule(:cpu) {key.failure("No Cpu request") if value <= 0}
        rule(:memory) {key.failure("No memory request") if value <= 0}
    end


    class RequestContainer
        extend Dry::Container::Mixin

        register "requests_repository" do
            RequestsRepository.new
        end

        register "operations.create_request" do
            CreateRequest.new
        end
    end

    Import = Dry::AutoInject(RequestContainer)

    class CreateRequest 
        include Import["tasks_repository"] 


        def call(requests_attrs)
            requests_repository.create(requests_attrs)
        end
    end
    

    class Container
        
        #states
        CONTAINER_WAITING      = 0      #still running the operations it requires in order to complete start up
        CONTAINER_RUNNING      = 1      #executing without issues
        CONTAINER_TERMINATED   = 2      #began execution and then either ran to completion or failed for some reason


        attr_reader :containerId, :imageId, :state, :port, :state, :startedTime, #:nRestart
        
        
        def initialize(containerId, imageId, port)
            @containerId        = containerId
            @imageId            = imageId
            @port               = port
            @state              = Container::CONTAINER_WAITING
            @limits             = Limits.new("cpu" => "500", "memory" => "500")
            @guaranteed         = Guaranteed.new("cpu" => "500", "memory" => "500")
            @startedTime        = Time.now
        
            @busy           = false
            @request_queue     = []

            @trace = opts[:trace] ? true : false
            @working_time   = 0.0
        
        end


        def startupC
            sleep(0.002)
            @state = Container::CONTAINER_RUNNING
        end
        
        def new_request(sim, n, time)
            create_request = RequestContainer["operations.create_request"]
            @request_queue << create_request.call(n_cycles: n, arrival_time: time)
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
            raise "Container not available (id: #{@containerId})" if @state == CONTAINER_TERMINATED or @state == CONTAINER_WAITING or @busy
            
            unless @request_queue.empty? or @state == CONTAINER_TERMINATED
                r = @request_queue.shift

                # retrieve service time
                # TODO verify the unit of service time (s/ms)?
                nc = r.n_cycles
                service_time_request = nc/@guaranteed.cpu

                if @trace
                    logger.info "Container #{@containerId} fulfilling a new request at time #{time} for #{service_time_request} seconds"
                end

                t.update_queuing_time(time - t.arrival_time)

                # update the request's workinginformation
                t.step_completed(service_time_task)

                #@working_time += service_time_task

                "Total working time: #{@working_time}"

                # schedule completion of workflow step
                sim.new_event(Event::ET_WORKFLOW_STEP_COMPLETED, nc, time + working_time, self)

            end
            
            @busy = false

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
