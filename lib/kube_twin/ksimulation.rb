# frozen_string_literal: true

require_relative './cluster'
require_relative './replica_set'
require_relative './horizontal_pod_autoscaler'
require_relative './service'
require_relative './event'
require_relative './generator'
require_relative './fault_generator'
require_relative './request_generator'
require_relative './sorted_array'
require_relative './statistics'
require_relative './component_statistics'
require_relative './pod'
require_relative './latency_manager'
require_relative './kube_dns'
require_relative './kube_scheduler'
require_relative './node'

require 'json'
require 'socket'
require 'logger'

#require 'pycall'
#require 'pycall/import'
#include PyCall::Import



module KUBETWIN

  class KSimulation

    UNFEASIBLE_ALLOCATION_EVALUATION = { unfeasible_configuration: -Float::INFINITY }.freeze
    attr_reader :start_time

    DEFAULT_NUM_REQS = 5000
    CONNECT_TIME = 0.00148205
    SEED = 123

    def initialize(opts = {})
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO
      @configuration = opts[:configuration]
      @evaluator     = opts[:evaluator]
      @results_dir   = opts[:results_dir]
      @num_reqs      = opts[:num_reqs]
      @num_reqs = DEFAULT_NUM_REQS if @num_reqs.nil?
      @results_dir += '/' unless @results_dir.nil?
      @microservice_mdn = Hash.new
      @socket_sim = establish_socket_connection("/tmp/chaos_telka.sock")
      @total_evicted = 0
      #pyfrom :tensorflow, import: :keras
      #keras.utils.disable_interactive_logging()
      #os = PyCall.import_module("os")
      #os.environ['TF_CPP_MIN_LOG_LEVEL'] = '1'

    end

    def retrieve_mdn_model(name, rps)
      # if not create mdn
      # @logger.debug "name: #{name} #{@microservice_mdn}"
      unless @microservice_mdn[name][:st].key?(rps)
        numpy = PyCall.import_module("numpy")
        # here rember to set replica to the correct value
        weight_pred, conc_pred, scale_pred = @microservice_mdn[name][:model].predict([numpy.array([rps, 1]), numpy.array([1,1])])
        # convert numpy to python list
        ws = weight_pred.tolist()
        cps = conc_pred.tolist()
        scs = scale_pred.tolist()
        gamma_mix = []
        ncomponents = ws[0].length - 1
        (0..ncomponents).each do |i|
          gamma_mix << ws[0][i].to_f
          gamma_mix << cps[0][i].to_f
          gamma_mix << scs[0][i].to_f
        end
        @microservice_mdn[name][:st][rps] = ERV::MixtureDistribution.new(
                  ERV::GammaMixtureHelper.RawParametersToMixtureArgsSeed(*gamma_mix, SEED))
      end
      return @microservice_mdn[name][:st][rps]
    end


    def new_event(type, data, time, destination)
      e = Event.new(type, data, time, destination)
      @event_queue << e
    end


    def now
      @current_time
    end

    def establish_socket_connection(path)
      socket_path = path
      #while true
      #  begin
      File.delete(socket_path) if File.exist?(socket_path)
      socket = UNIXServer.new(socket_path)
      #    break
      #  rescue => e
      #    @logger.error "Error in establishing socket connection: #{e}, retrying..."
      #    sleep(0.5)
      #  end
      #end
      @logger.debug "Socket established at #{socket_path}"
      return socket
    end

    # rss is replica set
    # css is service configuration
    def evaluate_allocation(rss=nil, css=nil, mtt=nil,lm=nil)
      # seeds
      latency_seed = @configuration.seeds[:communication_latencies]
      service_time_seed = @configuration.seeds[:service_times]
      next_component_rng = if @configuration.seeds[:next_component_selection]
        Random.new(@configuration.seeds[:next_component_selection])
      else
        Random.new
      end

      # create latency manager
      latency_models = lm.nil? ? @configuration.latency_models : lm
      latency_manager = latency_seed ?
        LatencyManager.new(latency_models, seed: latency_seed) :
        LatencyManager.new(latency_models)

      # setup simulation start and current time
      @current_time = @start_time = @configuration.start_time

      # here need to retrieve configuration cost also
      evaluation_cost = Hash.new

      @configuration.evaluation[:cluster_hourly_cost].each do |c|
        evaluation_cost[c[:cluster]] = c[:fixed_cpu_hourly_cost]
        # leave memory out for now
        #evaluation_cost[c[:cluster_memory]] = c[:fixed_memory_hourly_cost]
      end

      # create clusters and relative nodes and store them in a repository
      cluster_repository = Hash[
        @configuration.clusters.map do |k,v|
          [ k, Cluster.new(id: k, fixed_hourly_cost_cpu: evaluation_cost[k], fixed_hourly_cost_memory: evaluation_cost[k], **v) ]
        end
      ]

      node_id = 0
      cluster_repository.values.each do |c|
        node_number = c.node_number
        node_number.times do |i|
          # we suppose to have nodes with homogenous capabilities in a
          # cluster
          # set also the cluster_id here
          n = Node.new(node_id, c.node_resources_cpu, c.node_resources_memory, 5, 3, c.cluster_id, c.type) #5 as heartbeat period, 3 as eviction threshold for each node
          c.add_node(n)
          node_id += 1
        end
      end

      # information regarding microservices
      @microservice_types = mtt.nil? ? @configuration.microservice_types : mtt
      @logger.debug "#{@microservice_types} #{@microservice_types.nil?}"
=begin
      @microservice_types.each do |k, v|
        #@logger.debug "#{k} #{v}"
        # @logger.debug "#{v[:mdn_file]}"
        #abort
        pyfrom :tensorflow, import: :keras
        unless v[:mdn_file].nil?
          model = keras.models.load_model(v[:mdn_file])
          # @logger.debug "model: #{model}"
          @microservice_mdn[k] = {model: model, st: Hash.new }
          # @logger.debug "v: #{@microservice_mdn}"
        end
      end
=end

      @logger.debug "init mdns #{@microservice_mdn}"

      # information regarding customers
      customer_repository = @configuration.customers
      workflow_type_repository = @configuration.workflow_types


      # initialize statistics --- leave for later
      stats = Statistics.new

      # statistics for servicemdnmdn
      per_component_stats = Hash[
        @microservice_types.keys.map do |m_id|
          [
            m_id,
            ComponentStatistics.new()
          ]
        end
      ]

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
      @evicted_pods = {}
      @pod_reallocated = 0

      # init from simulation or optimizator
      if rss.nil?
        crs = @configuration.replica_sets
      else
        crs = rss
      end

      # first create the replica_set
      crs.each do |name, conf|
        # nil is service here
        # do we need a reference to service in ReplicaSet?
        @replica_sets[name] = ReplicaSet.new(name, conf[:selector],
           conf[:replicas], nil)
      end

      # @logger.debug @replica_sets

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

      #@logger.debug @horizontal_pod_autoscaler_repo

      # Then create services and pods at startup
      # not simulating starup events in the MVP

      # init from simulation or optimizator
      if css.nil?
        css = @configuration.services
      end

      @services = {}

      # we could use a repository here
      # dry could be very useful in here...
      css.each do |k, conf|
        @services[k] = Service.new(k, conf[:selector])
        # need to register this service into kube_dns
        @kube_dns.registerService(@services[k])
      end


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
          sct = @microservice_types[selector]
          # here we need to call the scheduler to get a node where to allocate this pod
          # retrieve a node where to allocate this pod
          reqs_c = sct[:resources_requirements_cpu]
          reqs_m = sct[:resources_requirements_memory]
          node_affinity = sct[:node_affinity]

          node = @kube_scheduler.get_node(reqs_c, node_affinity)
          next if node.nil? # no more resources
          # once we know where the pod is going to be allocated
          # we can retrieve also the service_time_distribution
          # depending on its cluster type

          pod = Pod.new(pod_id, "#{selector}_#{pod_id}", node, selector, sct)
          pod.startUpPod(node)
          #@logger.debug "pod #{pod_id} created and ready to be assigned to node #{node.node_id}"
          # assign resources for the pod
          node.assign_resources(pod, reqs_c, reqs_m)
          #@logger.debug "assigning pod #{pod_id} to node #{node.node_id}"
          # get the service here and assign the pod to the service
          # convert string to sym
          # we could also assing the service to the replica set
          s = @services[selector]
          s.assignPod(pod)
          pod_id += 1
        end
      end


      # here null check before sending event
      @stats_print_interval = @configuration.stats_print_interval

      # create event queue
      # this stores all simulation events
      @event_queue = SortedArray.new

      # @logger.debug "========== Simulation Start =========="
      # generate first request
      # both R and ruby should work request_gen is written in Ruby
      # request_generation is csv or R
      @to_generate = 0
      if @configuration.request_gen.nil?
        #@logger.debug "#{@configuration.request_generation}"
        rg = RequestGeneratorR.new(@configuration.request_generation)
        # this is to avoid mismatch when reproducing logs
        req_attrs = rg.generate(now)
        @current_time = @start_time = req_attrs[:generation_time] - 2
        @configuration.set_start(@current_time)
        new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], rg)
      else
        @configuration.request_gen.each do |k,v|
          @to_generate += @configuration.request_gen[k][:num_requests]
          rg = RequestGenerator.new(@configuration.request_gen[k])
          req_attrs = rg.generate(@configuration.request_gen[k][:starting_time].to_i)
          new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], rg)
        end
      end
      #new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)
      # Simulate node faults chaos events

      ## Handle faults generation
      unless @configuration.cluster_faults.nil?
        @configuration.cluster_faults.each do |k,v|
          fg = FaultGenerator.new(@configuration.cluster_faults[k])
          fault_attributes = fg.generate(@configuration.cluster_faults[k][:starting_time].to_i)
          node = cluster_repository[fault_attributes[:cluster]].nodes.values.sample(1)[0]
          new_event(Event::ET_SHUTDOWN_NODE, node, req_attrs[:generation_time], fg)
        end
      end

      unless @configuration.delay_model.nil?
        @configuration.delay_model.each do |k,v|
          loc1 = v[:loc1_id]
          loc2 = v[:loc2_id]
          delay = v[:delay]
          start = v[:start].to_i
          @logger.info "Delay model: #{loc1} #{loc2} #{delay} #{start}"
          new_event(Event::ET_DELAY_MODEL, [loc1, loc2, delay], start, nil)
        end
      end

      #generate first heartbeat check
      cluster_repository.each do |k, cluster|
        cluster.nodes.each do |k, node|
          new_event(Event::ET_NODE_CONTROL, node, @current_time + node.heartbeat_period, nil)
        end
      end

      # generate first HPA check
      @horizontal_pod_autoscaler_repo.each do | name, hpa|
        new_event(Event::ET_HPA_CONTROL, [name, hpa], @current_time + hpa.period_seconds, nil)
      end
      
      # schedule end of simulation
      unless @configuration.end_time.nil?
        @logger.debug "Simulation ends at: #{@configuration.end_time} duration: #{@configuration.end_time - @start_time}"
        new_event(Event::ET_END_OF_SIMULATION, nil, @configuration.end_time, nil)
      end

      # calculate warmup threshold
      warmup_threshold = @configuration.start_time + @configuration.warmup_duration.to_i

      cooldown_treshold = @configuration.end_time - @configuration.cooldown_duration.to_i

      # get stats print
      new_event(Event::ET_STATS_PRINT, nil, warmup_threshold + @stats_print_interval, nil) unless @stats_print_interval.nil?

      requests_being_worked_on = 0
      current_event = 0

      # benchmark file
      time = Time.now.strftime('%Y%m%d%H%M%S')
      #@sim_bench = File.open("csv_bench_#{time}.csv", 'w')
      #@allocation_bench = File.open("allocation_bench_#{time}.csv", 'w')
      #@request_profile = File.open("request_profile_#{time}.csv", 'w')
      #@request_profile << "Time,CRequests\n"
      @last_second = @current_time.to_i
      @req_in_sec = 0

      # Socket Communication with RL Agent #
      # Start the socket now and keep it until the end of the simulation
      sock = @socket_sim.accept
      
      #@allocation_bench << "Time,Component,Request,TTP,Pods\n"

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
            pod = service.get_pod(first_component_name) # same as selector

            # we need to get a reference to the cluster where the pod is running
            cluster_id = pod.node.cluster_id
            cluster = cluster_repository[cluster_id]

            arrival_time = @current_time + latency_manager.sample_latency_between(customer_location_id, cluster.location_id)
            # here we should also add the HTTP connection time (8 ms)
            arrival_time += CONNECT_TIME

            # generate the request here
            new_req = Request.new(**req_attrs.merge!(initial_data_center_id: cluster_id,
                                                   arrival_time: arrival_time))

            # schedule arrival of current request
            new_event(Event::ET_REQUEST_ARRIVAL, [new_req, pod], arrival_time, nil)

            # schedule generation of next request
            if @current_time < cooldown_treshold && @generated < @to_generate #warmup_threshold
                rg = e.destination
                req_attrs = rg.generate(@current_time)
                new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], rg) if req_attrs
            else
              @logger.debug "Ending the simulation! Stopping generating requests!"
            end


          when Event::ET_REQUEST_ARRIVAL
            # get request
            req, pod = e.data

            # do not consider warmup here
            if req.arrival_time > warmup_threshold && req.arrival_time < cooldown_treshold

              # get the pod here, we do not need thr cluster
            @arrived += 1

            #cluster = cluster_repository[req.data_center_id]
            # update reqs_received_per_workflow_and_customer
            reqs_received_per_workflow_and_customer[req.workflow_type_id][req.customer_id] += 1

            # find next component name
            workflow = workflow_type_repository[req.workflow_type_id]
            # @logger.debug "next_component_name #{next_component_name}, pod.label #{pod.label}"

            # schedule request forwarding to pod
            @forwarded += 1
            new_event(Event::ET_REQUEST_FORWARDING, req, e.time, pod)

              # update stats
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

            # increase count of received requests in per_component_stats
            workflow = workflow_type_repository[req.workflow_type_id]
            component_name = workflow[:component_sequence][req.next_step][:name]
            per_component_stats[component_name].request_received

            #print "Evicted pod #{pod.pod_id} received request #{req.rid}!\n" if pod.status == Pod::POD_EVICTED
            
            # here we should use the delegator
            # @logger.debug "#{now},#{pod.container.containerId},#{pod.container.request_queue.length}\n"
            pod.container.new_request(self, req, time)


          when Event::ET_WORKFLOW_STEP_COMPLETED

            # retrieve request and vm
            req = e.data
            container  = e.destination
            @processed += 1

            # unless next_ms
            container.request_finished(self, e.time) if container.wait_for.empty?

            # tell the old container that it can start processing another request
            # if microservice should wait for one other
            oc = container.free_linked_container
            oc.request_finished(self, e.time) if oc

            current_cluster = cluster_repository[req.data_center_id]
            # find the next workflow
            workflow = workflow_type_repository[req.workflow_type_id]

            # register step completion
            component_name = workflow[:component_sequence][req.worked_step][:name]
            per_component_stats[component_name].record_request(req, now)

            req.ttr_step(@current_time)

            # check if there are other steps left to complete the workflow
            if req.next_step < workflow[:component_sequence].size

              # find next component name
              next_component_name = workflow[:component_sequence][req.next_step][:name]

              # resolve the next component name
              service = @kube_dns.lookup(next_component_name)

              # e.time should be equivalent to @current_time
              forwarding_time = e.time

              # get a pod from the one available
              pod = service.get_pod(next_component_name) # same as selector

              # we need to get a reference to the cluster where the pod is running
              cluster_id = pod.node.cluster_id
              cluster = cluster_repository[cluster_id]

              transmission_time =
                latency_manager.sample_latency_between(current_cluster.location_id, cluster.location_id)
              req.update_transfer_time(transmission_time)
              forwarding_time += transmission_time

              # update request's current data_center_id / cluster_id
              req.data_center_id = cluster.cluster_id

              # make sure we actually found a pod
              raise "Cannot find a Pod running a component of type " +
                    "#{next_component_name} in any cluster!" unless pod

              # schedule request forwarding to pod
              @forwarded += 1

              # http chained microservices
              # if the current microservice is the one which the old was waiting, free the old container
              pod.container.to_free(container) unless container.wait_for.empty?

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
            #@logger.debug "#{req.arrival_time} #{now}"
            raise "Processing request after the simulation time current:#{now} end:#{@configuration.end_time}" if now >= @configuration.end_time

            # update stats
            if req.arrival_time > warmup_threshold && now < @configuration.end_time
              # decrease the number of requests being worked on
              requests_being_worked_on -= 1

              # collect request statistics
              stats.record_request(req, @current_time)

              # collect request statistics in per_workflow_and_customer_stats
              per_workflow_and_customer_stats[req.workflow_type_id][req.customer_id].record_request(req, @current_time)
              #@benchmark << "#{req.rid},#{req.ttr(@current_time)}\n"
            end

            # schedule generation of next request
            # here we want also to cut the number of requests
            # for fitting
            #if @current_time < cooldown_treshold && stats.n < @num_reqs
            #  req_attrs = rg.generate(@current_time)
            #  new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)
            #end

          when Event::ET_HPA_CONTROL
            hname, hpa = e.data
            # is computed by taking the average of the given metric across
            # all Pods in the HorizontalPodAutoscaler's scale target
            # retrieve desired replica_set ...
            # @logger.debug hname

            s = @services[hpa.name]

            raise "Impossible to retrieve s" if s.nil?

            # improve this initialization
            # right now it is terrible (okay for MVP)
            service_time_rv = s.pods[s.selector].sample.container.service_time

            # here need this hack to avoid taking value from tail
            # rejection sampling to implement (crudely) PDF truncation
            sva = 0.upto(100).collect { service_time_rv.sample }
            service_time = sva.sum / sva.length.to_f
            # while (service_time = service_time_rv.next) < 2E-3; end
            # @logger.debug service_time

            desired_metric = hpa.target_processing_percentage * service_time

            current_metric = 0
            pods = 0
            d_replicas = 0


            s.pods[hpa.name].each do |pod|
              next if pod.container.served_request.zero?
              current_metric += pod.container.total_queue_processing_time / pod.container.served_request
              # @logger.debug "total queue time: #{pod.container.total_queue_time}"
              # @logger.debug "served request: #{pod.container.served_request}"
              # reset container metric
              # calculate them each time period
              pod.container.reset_metrics
              # @logger.debug "#{pod.container.current_processing_metric}"
              pods += 1
            end
            current_metric /= pods.to_f

            @logger.debug "**** Horizontal Pod Autoscaling ****"
            @logger.debug "#{hpa.name} pods: #{pods} average processing_time: #{current_metric} desired_metric: #{desired_metric}"
            @logger.debug "************************************"

            if pods == 0
              @logger.warn "Ending the simulation with no pods!"
              #break
              #new_event(Event::ET_END_OF_SIMULATION, nil, now, nil)
              next
            end
            # see here
            # https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
            # if close to 1 do not scale -- use a tolerance range
            scaling_ratio = current_metric / desired_metric
            # tolerance range # should be configurable
            tolerance_range = 0.90..1.10

            unless tolerance_range === scaling_ratio
              # then here implement the check to scale up or down the associated pods
              @logger.debug "pods: #{pods} scaling_ratio: #{scaling_ratio}"
              d_replicas = (pods * scaling_ratio).ceil
              # @logger.debug "desired_replicas: #{d_replicas} current_replicas #{pods}"

              if d_replicas > pods

                # get the replica set
                rs = @replica_sets[hname]
                to_scale = d_replicas <= hpa.max_replicas ? (d_replicas - pods) : (hpa.max_replicas - pods)

                rs.set_replicas(d_replicas)

                # then create the replicas
                to_scale.times do
                  selector = rs.selector
                  sct = @microservice_types[selector]
                  reqs_c = sct[:resources_requirements_cpu]
                  reqs_m = sct[:resources_requirements_memory]

                  node_affinity = sct[:node_affinity]
                  node = @kube_scheduler.get_node(reqs_c, node_affinity)

                  break if node.nil? # check here --- what happens if no nodes are available
                  pod = Pod.new(pod_id, "#{selector}_#{pod_id}", node, selector, sct)
                  pod.startUpPod(node)
                  # assign resources for the pod
                  node.assign_resources(pod, reqs_c, reqs_m)
                  pod_id += 1
                end
              else
                # we need to select some pods to terminate
                # deal with requests currently being processed
                #@logger.debug "min #{hpa.min_replicas}"
                to_scale = d_replicas > hpa.min_replicas ? (pods - d_replicas) : 0
                unless to_scale.zero?
                  # @logger.debug "deactivating pods"
                  ppl = s.pods[hpa.name].sample(to_scale)
                  ppl.each do |p|
                    unless p.status == Pod::POD_EVICTED
                      p.deactivate_pod 
                      s.delete_pod(s.selector, p)
                    end
                  end
                end
              end

            end

            allocation_map = {}
            cluster_repository.each do |_,c|
               #@logger.debug "Allocation -- #{c.name} Pods: #{pods}"
               pods = 0
               c.nodes.values.each do |n|
                pods += n.pod_id_list.length
                #@logger.debug "node_id: #{n.node_id}: pods: #{n.pod_id_list.length}"
               end
               allocation_map[c.name] = {tier: c.tier, pods: pods}
               #@logger.debug "Allocation -- #{c.name} Pods: #{pods}"
            end

            # @logger.debug "Allocation_map: #{allocation_map}\n"


            # schedule next control
            if @current_time + hpa.period_seconds < cooldown_treshold
              new_event(Event::ET_HPA_CONTROL, [hname, hpa], @current_time + hpa.period_seconds, nil)
            end

          when Event::ET_END_OF_SIMULATION
            # FOR NOW KEEP PROCESSING REQUEST
            @logger.debug "#{e.time}: end simulation @event_queue size: #{@event_queue.length}"
            until @event_queue.empty?
              e = @event_queue.shift
            end
            # calculate some statistics
            ratio = @pod_reallocated.to_f / @total_evicted.to_f
            med_ttr = stats.mean 
            additional_reward = ratio / med_ttr.to_f 
            @logger.info "ratio: #{ratio} med_ttr: #{med_ttr} additional_reward: #{additional_reward}"
            begin
              sock.write("END;#{ratio};#{med_ttr};#{additional_reward}\n")
              sock.close
            rescue => e
              @logger.error "Error in sending data to RL Agent"
            end

          # print some stats (useful to track simulation data)
          when Event::ET_STATS_PRINT

            # calculate the number of pods
            pods_n = ""
            @services.each do |k, s|
              pods_number = s.pods[s.selector].length
              pods_n += "#{k}: #{pods_number} "
              #@allocation_bench << "#{now},#{k},#{per_component_stats[k].received},#{per_component_stats[k].mean},#{pods_number}\n"
              #@logger.debug "#{now},#{k},#{per_component_stats[k].received},#{per_component_stats[k].mean},#{pods_number}\n"
              # just to print the allocation map
            end

            #@logger.debug "++++++++++++++++\n"+
            #"#{now}\n" +
            #"#{stats.to_s}\n" +
            #"workflow_stats: #{per_workflow_and_customer_stats.to_s}\n"+
            #"component_stats: #{per_component_stats.to_s}\n"+
            #ls"#{pods_n}"

            # reset also comoponent statistics

            per_component_stats = Hash[
              @microservice_types.keys.map do |m_id|
                [
                  m_id,
                  ComponentStatistics.new()
                ]
              end
            ]

            next_event_time = @current_time + @stats_print_interval

            if next_event_time < cooldown_treshold
              new_event(Event::ET_STATS_PRINT, nil, @current_time + @stats_print_interval, nil) unless @stats_print_interval.nil?
            end

          when Event::ET_NODE_CONTROL #periodically check nodes heartbeat signal
            check_node = e.data
            if check_node.ready == true
              #@logger.debug "Node #{check_node.node_id} on cluster #{check_node.cluster_id} is alive"
              check_node.eviction_count = 0
            else
              #@logger.debug "Node #{check_node.node_id} on cluster #{check_node.cluster_id} is dead"
              check_node.eviction_count += 1
              if check_node.eviction_count == check_node.eviction_threshold
                #@logger.debug "Node #{check_node.node_id} on cluster #{check_node.cluster_id} is going to be evicted"
                new_event(Event::ET_SHUTDOWN_NODE, check_node, @current_time, nil)
              end
            end

            # schedule next control
            if @current_time + check_node.heartbeat_period < cooldown_treshold
              new_event(Event::ET_NODE_CONTROL, check_node, @current_time + check_node.heartbeat_period, nil)
            end
            
          #try to implement shutdown node event. Example --> select a random node and put ready to false
          when Event::ET_SHUTDOWN_NODE
            node = e.data
            next if node.ready == false
            node.ready = false
            node.pod_id_list.each do |pod_id|
              pod = node.retrieve_pod(pod_id)
              pod.simulate_issue
              new_event(Event::ET_EVICT_POD, [pod, node], @current_time, nil)
            end

            @logger.debug "Node #{node.node_id} on cluster #{node.cluster_id} is going to be deallocated"
            new_event(Event::ET_DEALLOCATE_NODE, [node, cluster_repository[node.cluster_id]], @current_time + 0.5, nil)
            
            # schedule generation of next faults
            if @current_time < cooldown_treshold
              fg = e.destination
              fault_attrs = fg.generate(@current_time)
              next if fault_attrs.nil?
              @logger.debug "fault_attrs: #{fault_attrs}"
              cluster = fault_attrs[:cluster]
              @logger.debug "cluster: #{cluster}"
              node = cluster_repository[fault_attrs[:cluster]].nodes.values.sample(1)[0]
              new_event(Event::ET_SHUTDOWN_NODE, node, fault_attrs[:generation_time], fg) if fault_attrs
            end

          when Event::ET_DEALLOCATE_NODE
            node, target_cluster = e.data
            nodes_alive_json = {}
            target_cluster.remove_node(node)
            target_cluster.node_number -= 1
            @logger.debug "Cluster #{target_cluster.cluster_id} has now #{target_cluster.node_number} nodes"
            @logger.debug "Node Deallocated: node_id: #{node.node_id} in cluster #{target_cluster.cluster_id} at time #{e.time}"
            
            #evicted_pods_json = @evicted_pods.transform_values { |pod| pod.as_json }.to_json



           
            @evicted_pods.each do |pod_id, pod|
              
              nodes_alive_json = {}

              cluster_repository.each do |k, cluster|
                cluster.nodes.each do |_, node|
                  nodes_alive_json[node.node_id] = node
                end
              end
              
              nodes_alive_json = nodes_alive_json.transform_values { |node| node.as_json }.to_json

              @logger.debug "Evicted Pod: #{pod}"
              podj = pod.as_json.to_json
              bytes = 0
              begin
                bytes += sock.write(podj + "\n")  # Send evicted pods to RL Agent
                ack = sock.recv(128)
                @logger.debug "ACK: #{ack}"
                bytes += sock.write(nodes_alive_json + "\n")  # Send alive nodes to RL Agent
              rescue => e
                @logger.error "Error in sending data to RL Agent: Written bytes: #{bytes}"
                @logger.error "#{e}"
                sock.close()
                break 
              end 
              begin
                # Receive new allocation from RL Agent
                new_allocation = sock.recv(1024)
              rescue => e 
                @logger.error "Error in receiving new allocation from RL agent"
                @logger.error "#{e}"
                sock.close()
                break 
              end
              # Here, the action space is of variable size, so we need to check if the action is valid
              # if the action is not valid, we are going to do nothing, so what we receive from the RL agent would be END_PODS
              unless new_allocation.empty? or new_allocation.strip == "END_PODS"  # Legge fino a 1024 byte dalla socket
                # Running some checks here
                # it should not be nil here
                
                break if new_allocation.nil?

                if new_allocation.strip == "WRONG_ACTION"
                  move_on = false
                else
                  move_on = true
                end

                if move_on 
                  # this is the id where to allocate the new node
                  new_allocation = JSON.parse(new_allocation)
                  @logger.debug "New Allocation: #{new_allocation}"

                  new_pod_id = new_allocation["pod_id"]
                  new_node_id = new_allocation["node_id"].to_i
                  @logger.debug "New Node ID: #{new_node_id}"

                  evicted_pod_to_reallocate = @evicted_pods[new_pod_id]
                  @logger.debug "Evicted Pod to reallocate: #{evicted_pod_to_reallocate}"

                  target_node = nil
                  cluster_repository.each do |cluster_key, cluster|
                    if cluster.nodes[new_node_id] != nil
                      target_node = cluster.nodes[new_node_id]
                    end
                    break if target_node
                  end

                  @logger.debug "Target Node: #{target_node}"

                  sct = @microservice_types[evicted_pod_to_reallocate.label]
                  reqs_c = sct[:resources_requirements_cpu]
                  reqs_m = sct[:resources_requirements_memory]

                  # TODO: check if target_node is in a ready state, if not assign a negative reward
                  if target_node.ready == false
                    @logger.debug "Node #{target_node.node_id} on cluster #{target_node.cluster_id} is not ready"
                    reward = -0.2
                  else
                    if target_node.available_resources_cpu >= reqs_c && target_node.available_resources_memory >= reqs_m
                      @logger.debug "Node resources before reallocation: #{target_node.available_resources_cpu} #{target_node.available_resources_memory}"
                      # Reallocate pod to target node
                      evicted_pod_to_reallocate.startUpPod(target_node)
                      # assign resources for the pod
                      target_node.assign_resources(evicted_pod_to_reallocate, reqs_c, reqs_m)
                      @logger.debug "Node resources after reallocation: #{target_node.available_resources_cpu} #{target_node.available_resources_memory}"

                      #TODO: improve reward structure to a more informative and effective one
                      # 1. Reward based on node resources usage (try to avoid overloading nodes)
                      # 2. Reward based on pod TTP (try to avoid long TTP)
                      reward = 1
                      @pod_reallocated += 1
                      @evicted_pods.delete(evicted_pod_to_reallocate.pod_id)
                    else
                      @logger.debug "Node #{target_node.node_id} on cluster #{target_node.cluster_id} does not have enough resources to reallocate pod #{evicted_pod_to_reallocate.pod_id}"
                      reward = -0.2
                    end
                  end
                else
                  @logger.debug "The action received from RL agent is not valid"
                  reward = -0.5
                end # if move_on
              begin  
                # Send reward to RL Agent
                sock.write(reward.to_json + "\n")
                ack = sock.recv(128)
                @logger.debug "ACK: #{ack}"
              rescue => e
                @logger.error "Error in sending reward to RL Agent"
                @logger.error "#{e}"
                sock.close()
                break
              end
            end # ciclo for each pod
            end
              

          when Event::ET_EVICT_POD
            pod, node = e.data
            raise "Pod #{pod.pod_id} is not running on node #{node.node_id}" unless node.pod_id_list.include?(pod.pod_id)
            @logger.debug "Pod #{pod.pod_id} is going to be evicted from node #{node.node_id}"
            pod.evict_pod
            @evicted_pods[pod.pod_id] = pod
            @total_evicted += 1
            @logger.debug "Pod #{pod.pod_id} is now evicted"
            
            @logger.debug "Current Evicted Pods:"
            @evicted_pods.each do |pod_id, pod|
              @logger.debug "Pod ID: #{pod_id}, Name: #{pod.podName}, Original Node: #{pod.node&.node_id}"
            end

          when Event::ET_DELAY_MODEL
            loc1, loc2, delay = e.data
            @logger.debug "Delay Model: #{loc1} #{loc2} #{delay}"
            latency_manager.add_fixed_delay_between(loc1, loc2, delay)
          end
        
      end

      # @logger.debug "========== Simulation Finished =========="

      # TODO -- IMPLEMENT COST EVALUATION HERE
      #costs = @evaluator.evaluate_fixed_costs_cpu(vm_allocation)


     #@logger.debug "\n\n"
     #@sim_bench.close
     #@logger.debug "Finished after #{now - @configuration.end_time}"

      allocation_map = {}
      cluster_repository.each do |_,c|
         #@logger.debug "Allocation -- #{c.name} Pods: #{pods}"
         pods = 0
         c.nodes.values.each do |n|
          pods += n.pod_id_list.length
          #@logger.debug "node_id: #{n.node_id}: pods: #{n.pod_id_list.length}"
         end
         allocation_map[c.name] = {tier: c.tier, pods: pods}
         #@logger.debug "Allocation -- #{c.name} Pods: #{pods}"
      end
      #@logger.debug "#{stats.to_csv}"
     @logger.info "====== Evaluating new allocation ======\n" +
           #"costs: #{costs}\n" +
           "generated: #{@generated} arrived #{@arrived}\n" +
           "stats: #{stats.to_s}\n" +
           #"per_workflow_and_customer_stats: #{per_workflow_and_customer_stats.to_s}\n" +
           "component_stats: #{per_component_stats.to_s}\n" +
           "allocation_map: #{allocation_map}\n" +
           "=======================================\n"
      # debug info here
      # we want to minimize the cost, so we define fitness as the opposite of
      # the sum of all costs incurred
      # -costs.values.inject(0.0){|s,x| s += x }
      # 99-th percentile ttr + closed_request +
      # (- 0.99 )
      # -stats.mean
      #res = -per_workflow_and_customer_stats[1][1].longer_than[0.51] /
      #    per_workflow_and_customer_stats[1][1].closed.to_f
      # @logger.debug "Res: #{res}"
      # res

      #@logger.debug "Percentage of requests within ms"
      #per_workflow_and_customer_stats[1][1].shorter_than.each_key do |t|
      #  @logger.debug "#{(per_workflow_and_customer_stats[1][1].shorter_than[t] / per_workflow_and_customer_stats[1][1].closed.to_f) * 100}% #{t}s"
      #end
      #-stats.mean
      #return 0
      #return stats.to_csv
      #@sim_bench << stats.to_csv
      #@sim_bench.close
      #path_file = @allocation_bench.path
      #@allocation_bench.close
      #path_request = @request_profile.path
      #@request_profile.close
      #@logger.debug "python figure_generator/tnsm-figure.py #{path_file} #{path_request}"
      #`python figure_generator/tnsm-figure.py #{path_file} #{path_request}`
      #return stats.to_csv # change this
    end
  end
end
