# frozen_string_literal: true

require_relative './cluster'
require_relative './replica_set'
require_relative './horizontal_pod_autoscaler'
require_relative './service'
require_relative './event'
require_relative './generator'
require_relative './sorted_array'
require_relative './statistics'
require_relative './pod'
require_relative './latency_manager'
require_relative './kube_dns'
require_relative './kube_scheduler'
require_relative './node'


module KUBETWIN

  class KSimulation

    UNFEASIBLE_ALLOCATION_EVALUATION = { unfeasible_configuration: -Float::INFINITY }.freeze

    attr_reader :start_time


    def initialize(opts = {})
      @configuration = opts[:configuration]
      @evaluator     = opts[:evaluator]
    end


    def new_event(type, data, time, destination)
      e = Event.new(type, data, time, destination)
      @event_queue << e
    end


    def now
      @current_time
    end


    def evaluate_allocation(vm_allocation)
      # TODO: allow to define which feasibility controls to run in simulation
      # configuration. Here we hardcode a simple feasibility check: fail unless
      # there is at least one vm for each software component.
      @configuration.service_component_types.each do |sc_id,_|
        unless vm_allocation.find{|x| x[:component_type] == sc_id }
          puts "====== Unfeasible allocation ======\n" +
               "costs: #{UNFEASIBLE_ALLOCATION_EVALUATION}\n" +
               "vm_allocation: #{vm_allocation.inspect}\n" +
               "=======================================\n"
          return UNFEASIBLE_ALLOCATION_EVALUATION
        end
      end

      # seeds
      latency_seed = @configuration.seeds[:communication_latencies]
      service_time_seed = @configuration.seeds[:service_times]
      next_component_rng = if @configuration.seeds[:next_component_selection]
        Random.new(@configuration.seeds[:next_component_selection])
      else
        Random.new
      end

      # create latency manager
      latency_manager = latency_seed ?
        LatencyManager.new(@configuration.latency_models, seed: latency_seed) :
        LatencyManager.new(@configuration.latency_models)

      # setup simulation start and current time
      @current_time = @start_time = @configuration.start_time

      # here need to retrieve configuration cost also
      evaluation_cost = Hash.new

      @configuration.evaluation[:vm_hourly_cost].each do |c| 
        evaluation_cost[c[:cluster]] = c[:cost]
      end

      # create clusters and relative nodes and store them in a repository
      cluster_repository = Hash[
        @configuration.clusters.map do |k,v|
          [ k, Cluster.new(id: k, hourly_cost: evaluation_cost[k], **v) ]
        end
      ]

      node_id = 0
      cluster_repository.values.each do |c|
        node_number = c.node_number
        node_number.times do |i|
          # we suppose to have nodes with homogenous capabilities in a 
          # cluster
          # set also the cluster_id here
          n = Node.new(node_id, c.node_resources, c.cluster_id, c.type)
          c.add_node(n)
          node_id += 1
        end
      end

      # information regarding customers
      customer_repository = @configuration.customers
      workflow_type_repository = @configuration.workflow_types


      # initialize statistics --- leave for later
      stats = Statistics.new
      per_workflow_and_customer_stats = Hash[
        workflow_type_repository.keys.map do |wft_id|
          [
            wft_id,
            Hash[
              customer_repository.keys.map do |c_id|
                [ c_id, Statistics.new(@configuration.custom_stats.find{|x| x[:customer_id] == c_id && x[:workflow_type_id] == wft_id } || {}) ]
              end
            ]
          ]
        end
      ]
      reqs_received_per_workflow_and_customer = Hash[
        workflow_type_repository.keys.map do |wft_id|
          [ wft_id, Hash[customer_repository.keys.map {|c_id| [ c_id, 0 ]}] ]
        end
      ]

      # Initialize Kubernetes internal objects/services
  
      @kube_dns = KubeDns.new

      # debug variables
      @generated = 0
      @arrived = 0
      @processed = 0
      @forwarded = 0

      @replica_sets = {}
      # first create the replica_set
      @configuration.replica_sets.each do |name, conf|
        # nil is service here
        # do we need a reference to service in ReplicaSet?
        @replica_sets[name] = ReplicaSet.new(name, conf[:cluster_id],
                    conf[:selector], conf[:replicas], nil)
      end

      # puts @replica_sets

      @horizontal_pod_autoscaler_repo = {}
      unless @configuration.horizontal_pod_autoscalers.nil?
        @configuration.horizontal_pod_autoscalers.each do |name, conf|
          # implement the horizontal_pod_autoscaler
          @horizontal_pod_autoscaler_repo[name] = 
              HorizontalPodAutoscaler.new(conf[:name],
                  conf[:minReplicas], conf[:maxReplicas],
                    conf[:targetProcessingPercentage],
                    conf[:periodSeconds])
        end
      end

      puts @horizontal_pod_autoscaler_repo

      # Then create services and pods at startup
      # not simulating starup events in the MVP

      @services = {}

      # we could use a repository here
      # dry could be very useful in here...
      @configuration.services.each do |k, conf|
        @services[k] = Service.new(k, conf[:selector])
        # need to register this service into kube_dns
        @kube_dns.registerService(@services[k])
      end

      # do we want to use dup here?
      @service_component_types = @configuration.service_component_types

      # creating a KubeScheduler
      # the KubeScheduler decides on which nodes schedule
      # the pods
      @kube_scheduler = KubeScheduler.new(cluster_repository)

      pod_id = 0
      @replica_sets.each do |k, rs|
        # here we need to create pods and register them into a Service
        rs.replicas.times do
          selector = rs.selector
          # the nil fields is a node related information
          # get image info --> service component type (sct)
          # sct has info regarding service execution time
          sct = @service_component_types[selector]
          # here we need to call the scheduler to get a node where to allocate this pod
          # retrieve a node where to allocate this pod
          reqs = sct[:resources_requirements]
          node = @kube_scheduler.get_node(reqs)

          # once we know where the pod is going to be allocated
          # we can retrieve also the service_time_distribution
          # depending on its cluster type

          pod = Pod.new(pod_id, "#{selector}_#{pod_id}", node, selector, sct)
          pod.startUpPod

          # assign resources for the pod
          node.assign_resources(pod, reqs)
          # get the service here and assign the pod to the service
          # convert string to sym
          # we could also assing the service to the replica set
          s = @services[selector]
          s.assignPod(pod)
          pod_id += 1
        end
      end

      # create event queue
      # this stores all simulation events
      @event_queue = SortedArray.new

      # puts "========== Simulation Start =========="

      # generate first request
      rg = RequestGenerator.new(@configuration.request_generation)
      req_attrs = rg.generate
      new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)

      # generate first HPA check
      @horizontal_pod_autoscaler_repo.each do | name, hpa|
        new_event(Event::ET_HPA_CONTROL, [name, hpa], @current_time + hpa.period_seconds, nil)
      end

      # schedule end of simulation
      unless @configuration.end_time.nil?
        # puts "Simulation ends at: #{@configuration.end_time}"
        new_event(Event::ET_END_OF_SIMULATION, nil, @configuration.end_time, nil)
      end

      # calculate warmup threshold
      warmup_threshold = @configuration.start_time + @configuration.warmup_duration.to_i

      requests_being_worked_on = 0
      current_event = 0

      # launch simulation
      until @event_queue.empty?
        e = @event_queue.shift

        current_event += 1
        # sanity check on simulation time flow
        if @current_time > e.time
          raise "Error: simulation time inconsistency for event #{current_event} " +
                "e.type=#{e.type} @current_time=#{@current_time}, e.time=#{e.time}"
        end

        @current_time = e.time

        case e.type
          when Event::ET_REQUEST_GENERATION
            req_attrs = e.data

            @generated += 1
            # find closest data center
            customer_location_id = 
                                    customer_repository.
                                    dig(req_attrs[:customer_id], :location_id)

            # find first component name for requested workflow
            workflow = workflow_type_repository[req_attrs[:workflow_type_id]]
            first_component_name = workflow[:component_sequence][0][:name]

            # first we need to resolve the component name using
            # the kubernetes DNS

            # TODO -- modeling internal service time
            # this code can be split into two when

            service = @kube_dns.lookup(first_component_name)

            # the closest_dc stuff should be implmented within a load balancer / service 
            # here we cloud implement different policies rather than random policy
            pod = service.get_pod_rr(first_component_name) # same as selector

            # we need to get a reference to the cluster where the pod is running
            cluster_id = pod.node.cluster_id
            cluster = cluster_repository[cluster_id]
            
            arrival_time = @current_time + latency_manager.sample_latency_between(customer_location_id, cluster.location_id)

            # generate the request here
            new_req = Request.new(req_attrs.merge!(initial_data_center_id: cluster_id,
                                                   arrival_time: arrival_time))

            # schedule arrival of current request
            new_event(Event::ET_REQUEST_ARRIVAL, [new_req, pod], arrival_time, nil)

            # schedule generation of next request
            req_attrs = rg.generate
            new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)

          when Event::ET_REQUEST_ARRIVAL
            # get request
            req, pod = e.data
            # get the pod here, we do not need thr cluster
            @arrived += 1


            #cluster = cluster_repository[req.data_center_id]
            # update reqs_received_per_workflow_and_customer
            reqs_received_per_workflow_and_customer[req.workflow_type_id][req.customer_id] += 1

            # find next component name
            workflow = workflow_type_repository[req.workflow_type_id]
            next_component_name = workflow[:component_sequence][req.next_step][:name]
            #puts "next_component_name #{next_component_name}, pod.label #{pod.label}"

            # schedule request forwarding to pod
            @forwarded += 1
            new_event(Event::ET_REQUEST_FORWARDING, req, e.time, pod)

            # update stats
            if req.arrival_time > warmup_threshold
              # increase the number of requests being worked on
              requests_being_worked_on += 1

              # increase count of received requests
              stats.request_received

              # increase count of received requests in per_workflow_and_customer_stats
              per_workflow_and_customer_stats[req.workflow_type_id][req.customer_id].request_received
            end

          # Leave these events for when we add VM migration support
          # when Event::ET_VM_SUSPEND
          # when Event::ET_VM_RESUME

          when Event::ET_REQUEST_FORWARDING
            # get request
            # do we need to handle this event? we could have 
            # done everything in the previous one
            req  = e.data
            time = e.time
            pod   = e.destination

            # here we should use the delegator
            pod.container.new_request(self, req, time)


          when Event::ET_WORKFLOW_STEP_COMPLETED

            # retrieve request and vm
            req = e.data
            container  = e.destination
            @processed += 1

            # TODO check the following code here
            # tell the old container that it can start processing another request
            container.request_finished(self, e.time)

            current_cluster = cluster_repository[req.data_center_id]
            # find the next workflow
            workflow = workflow_type_repository[req.workflow_type_id]

            # check if there are other steps left to complete the workflow
            if req.next_step < workflow[:component_sequence].size

              # find next component name
              next_component_name = workflow[:component_sequence][req.next_step][:name]

              # resolve the next component name
              service = @kube_dns.lookup(next_component_name)

              forwarding_time = e.time

              # get a pod from the one available
              pod = service.get_pod_rr(next_component_name) # same as selector
              
              # we need to get a reference to the cluster where the pod is running
              cluster_id = pod.node.cluster_id
              cluster = cluster_repository[cluster_id]

              transmission_time =
                latency_manager.sample_latency_between(current_cluster.location_id,
                                                     cluster.location_id)

              req.update_transfer_time(transmission_time)
              forwarding_time += transmission_time

              # update request's current data_center_id / cluster_id
              req.data_center_id = cluster.cluster_id

              # make sure we actually found a VM
              raise "Cannot find a Pod running a component of type " +
                    "#{next_component_name} in any cluster!" unless pod

              # schedule request forwarding to vm
              @forwarded += 1
              new_event(Event::ET_REQUEST_FORWARDING, req, forwarding_time, pod)

            else # workflow is finished
              # calculate transmission time
              transmission_time =
                latency_manager.sample_latency_between(
                  # data center location
                  cluster_repository[req.data_center_id].location_id,
                  # customer location
                  customer_repository.dig(req.customer_id, :location_id)
                )

              unless transmission_time >= 0.0
                raise "Negative transmission time (#{transmission_time})!"
              end

              # keep track of transmission time
              req.update_transfer_time(transmission_time)

              # schedule request closure
              new_event(Event::ET_REQUEST_CLOSURE, req, e.time + transmission_time, nil)
            end


          when Event::ET_REQUEST_CLOSURE
            # retrieve request and vm
            req = e.data

            # request is closed
            req.finished_processing(e.time)

            # update stats
            if req.arrival_time > warmup_threshold
              # decrease the number of requests being worked on
              requests_being_worked_on -= 1

              # collect request statistics
              stats.record_request(req)

              # collect request statistics in per_workflow_and_customer_stats
              per_workflow_and_customer_stats[req.workflow_type_id][req.customer_id].record_request(req)
            end

          when Event::ET_HPA_CONTROL
            hname, hpa = e.data
            # is computed by taking the average of the given metric across
            # all Pods in the HorizontalPodAutoscaler's scale target
            # retrieve desired replica_set ...
            # puts hname

            s = @services[hpa.name]

            raise "Impossible to retrieve s" if s.nil?

            # improve this initialization
            # right now it is terrible (okay for MVP)
            service_time_rv = s.pods.values.sample[1].container.service_time

            # here need this hack to avoid taking value from tail
            sva = 0.upto(100).collect { service_time_rv.sample }
            service_time = sva.sum / sva.length.to_f
            # puts service_time
          
            desired_metric = service_time +
                           hpa.target_processing_percentage * service_time

            current_metric = 0
            pods = 0
            d_replicas = 0

            s.pods[hpa.name].each do |pod|
              current_metric += pod.container.current_processing_metric
              # puts "pod: #{pod.pod_id} current_metric #{pod.container.current_processing_metric}"
              pods += 1
            end
            current_metric /= pods.to_f

            puts "#{hname} pods: #{pods} average metric: #{current_metric} desired_metric: #{desired_metric}"

            # if close to 1 do not scale -- use a tolerance range
            scaling_ratio = current_metric / desired_metric
            # tolerance range # should be configurable
            tolerance_range = 0.90..1.10

            unless tolerance_range === scaling_ratio
              # then here implement the check to scale up or down the associated pods
              d_replicas = (pods * scaling_ratio).ceil
              puts "desired_replicas: #{d_replicas} current_replicas #{pods}"

              if d_replicas > pods

                # get the replica set
                rs = @replica_sets[hname]
                to_scale = d_replicas <= hpa.max_replicas ? (d_replicas - pods) : (hpa.max_replicas - pods)

                rs.set_replicas(d_replicas) 

                # then create the replicas
                to_scale.times do 
                  selector = rs.selector
                  sct = @service_component_types[selector]
                  reqs = sct[:resources_requirements]
                  node = @kube_scheduler.get_node(reqs)
                  pod = Pod.new(pod_id, "#{selector}_#{pod_id}", node, selector, sct)
                  pod.startUpPod
                  # assign resources for the pod
                  node.assign_resources(pod, reqs)
                  s.assignPod(pod)
                  pod_id += 1
                end
              end

            end


            # schedule next control
            new_event(Event::ET_HPA_CONTROL, [hname, hpa], @current_time + hpa.period_seconds, nil)

          when Event::ET_END_OF_SIMULATION
            # puts "#{e.time}: end simulation"
            break

        end
      end

      # puts "========== Simulation Finished =========="

      # here the evaluation will fail
      # we don't have an allocation array
      # costs = @evaluator.evaluate_business_impact(stats, per_workflow_and_customer_stats,
      #                                            vm_allocation)
      puts "====== Evaluating new allocation ======\n" +
          # "costs: #{costs}\n" +
          # "vm_allocation: #{vm_allocation.inspect}\n" +
           "stats: #{stats.to_s}\n" +
           "per_workflow_and_customer_stats: #{per_workflow_and_customer_stats.to_s}\n" +
           "=======================================\n"

      # debug info here

      # puts "generated: #{@generated} arrived: #{@arrived}, processed: #{@processed}, forwarded: #{@forwarded}"
      # cluster_repository.each do |_,c|
      #  puts "#{c.name} -- Allocation:"
      #  c.nodes.values.each do |n|
      #    puts "node_id: #{n.node_id}: pods: #{n.pod_id_list.length}"
      #  end
      # end

      # we want to minimize the cost, so we define fitness as the opposite of
      # the sum of all costs incurred
      #-costs.values.inject(0.0){|s,x| s += x }
      0
    end

  end
end
