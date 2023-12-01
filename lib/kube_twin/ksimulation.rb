# frozen_string_literal: true

require_relative './cluster'
require_relative './replica_set'
require_relative './horizontal_pod_autoscaler'
require_relative './service'
require_relative './event'
require_relative './generator'
require_relative './request_generator'
require_relative './sorted_array'
require_relative './statistics'
require_relative './component_statistics'
require_relative './pod'
require_relative './latency_manager'
require_relative './kube_dns'
require_relative './kube_scheduler'
require_relative './node'


require 'pycall'
require 'pycall/import'
include PyCall::Import



module KUBETWIN

  class KSimulation

    UNFEASIBLE_ALLOCATION_EVALUATION = { unfeasible_configuration: -Float::INFINITY }.freeze
    attr_reader :start_time

    DEFAULT_NUM_REQS = 5000
    CONNECT_TIME = 0.00148205
    SEED = 123

    def initialize(opts = {})
      @configuration = opts[:configuration]
      @evaluator     = opts[:evaluator]
      @results_dir   = opts[:results_dir]
      @num_reqs      = opts[:num_reqs]
      @num_reqs = DEFAULT_NUM_REQS if @num_reqs.nil?
      @results_dir += '/' unless @results_dir.nil?
      @microservice_mdn = Hash.new
      pyfrom :tensorflow, import: :keras
      keras.utils.disable_interactive_logging()
      os = PyCall.import_module("os")
      os.environ['TF_CPP_MIN_LOG_LEVEL'] = '1'

    end

    def retrieve_mdn_model(name, rps)
      # if not create mdn
      # puts "name: #{name} #{@microservice_mdn}"
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
      puts "#{@microservice_types} #{@microservice_types.nil?}"
      @microservice_types.each do |k, v|
        #puts "#{k} #{v}"
        # puts "#{v[:mdn_file]}"
        #abort
        pyfrom :tensorflow, import: :keras
        unless v[:mdn_file].nil?
          model = keras.models.load_model(v[:mdn_file])
          # puts "model: #{model}"
          @microservice_mdn[k] = {model: model, st: Hash.new }
          # puts "v: #{@microservice_mdn}"
        end
      end

      puts "init mdns #{@microservice_mdn}"

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

      #puts @horizontal_pod_autoscaler_repo

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
          #puts "pod #{pod_id} created and ready to be assigned to node #{node.node_id}"
          # assign resources for the pod
          node.assign_resources(pod, reqs_c, reqs_m)
          #puts "assigning pod #{pod_id} to node #{node.node_id}"
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

      # puts "========== Simulation Start =========="
      # generate first request
      # both R and ruby should work request_gen is written in Ruby
      # request_generation is csv or R
      @to_generate = 0
      if @configuration.request_gen.nil?
        #puts "#{@configuration.request_generation}"
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

      # randomly select a node to generate shutdown event
      #random_cluster = cluster_repository.values.sample
      #random_node = random_cluster.nodes.values.sample
      #new_event(Event::ET_SHUTDOWN_NODE, random_node, @current_time + 50, nil)

      random_cluster = cluster_repository.values.sample
      if random_cluster.nodes.length >= 3
        # Selected cluster has enough nodes for chaos event
        random_nodes = random_cluster.nodes.values.sample(3)
        random_nodes.each do |node|
          new_event(Event::ET_SHUTDOWN_NODE, node, @current_time + 50, nil)
        end
      else
        #cluster selected not suitable for chaos event --> ending simulation
        puts "Cluster selected not suitable for chaos event --> ending simulation"
        new_event(Event::ET_END_OF_SIMULATION, nil, @configuration.end_time, nil)
      end

      
      # schedule end of simulation
      unless @configuration.end_time.nil?
        # puts "Simulation ends at: #{@configuration.end_time}"
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
      @sim_bench = File.open("csv_bench_#{time}.csv", 'w')
      @allocation_bench = File.open("allocation_bench_#{time}.csv", 'w')
      @request_profile = File.open("request_profile_#{time}.csv", 'w')
      @request_profile << "Time,CRequests\n"
      @last_second = @current_time.to_i
      @req_in_sec = 0


      @allocation_bench << "Time,Component,Request,TTP,Pods\n"

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
            if @current_time.to_i == @last_second
              @req_in_sec += 1
            elsif @current_time.to_i == @last_second + 1
              @request_profile << "#{@current_time.to_i},#{@req_in_sec}\n"
              @req_in_sec = 1
              @last_second = @current_time.to_i
            elsif  (@current_time.to_i - 1) > @last_second
              @last_second = @current_time.to_i
            end

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
            # puts "next_component_name #{next_component_name}, pod.label #{pod.label}"

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

            # here we should use the delegator
            # puts "#{now},#{pod.container.containerId},#{pod.container.request_queue.length}\n"
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
=begin
            if component_name == "MS1"
              @benchmark_ms1 << "#{req.rid},#{req.ttr_step(@current_time)}\n"
            elsif component_name == "MS2"
              @benchmark_ms2 << "#{req.rid},#{req.ttr_step(@current_time)}\n"
            end
=end
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
            #puts "#{req.arrival_time} #{now}"
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
            # puts hname

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
            # puts service_time

            desired_metric = hpa.target_processing_percentage * service_time

            current_metric = 0
            pods = 0
            d_replicas = 0


            s.pods[hpa.name].each do |pod|
              next if pod.container.served_request.zero?
              current_metric += pod.container.total_queue_processing_time / pod.container.served_request
              # puts "total queue time: #{pod.container.total_queue_time}"
              # puts "served request: #{pod.container.served_request}"
              # reset container metric
              # calculate them each time period
              pod.container.reset_metrics
              # puts "#{pod.container.current_processing_metric}"
              pods += 1
            end
            current_metric /= pods.to_f

            puts "**** Horizontal Pod Autoscaling ****"
            puts "#{hpa.name} pods: #{pods} average processing_time: #{current_metric} desired_metric: #{desired_metric}"
            puts "************************************"

            if pods == 0
              puts "Ending the simulation!"
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
              puts "pods: #{pods} scaling_ratio: #{scaling_ratio}"
              d_replicas = (pods * scaling_ratio).ceil
              # puts "desired_replicas: #{d_replicas} current_replicas #{pods}"

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
                  s.assignPod(pod)
                  pod_id += 1
                end
              else
                # we need to select some pods to terminate
                # deal with requests currently being processed
                #puts "min #{hpa.min_replicas}"
                to_scale = d_replicas > hpa.min_replicas ? (pods - d_replicas) : 0
                unless to_scale.zero?
                  # puts "deactivating pods"
                  ppl = s.pods[hpa.name].sample(to_scale)
                  ppl.each do |p|
                    p.deactivate_pod
                    s.delete_pod(s.selector, p)
                  end
                end
              end

            end

            allocation_map = {}
            cluster_repository.each do |_,c|
               #puts "Allocation -- #{c.name} Pods: #{pods}"
               pods = 0
               c.nodes.values.each do |n|
                pods += n.pod_id_list.length
                #puts "node_id: #{n.node_id}: pods: #{n.pod_id_list.length}"
               end
               allocation_map[c.name] = {tier: c.tier, pods: pods}
               #puts "Allocation -- #{c.name} Pods: #{pods}"
            end
            puts "Allocation_map: #{allocation_map}\n"


            # schedule next control
            if @current_time + hpa.period_seconds < cooldown_treshold
              new_event(Event::ET_HPA_CONTROL, [hname, hpa], @current_time + hpa.period_seconds, nil)
            end

          when Event::ET_END_OF_SIMULATION
            # FOR NOW KEEP PROCESSING REQUEST
            #puts "#{e.time}: end simulation"
            until @event_queue.empty?
              e = @event_queue.shift
            end

          # print some stats (useful to track simulation data)
          when Event::ET_STATS_PRINT

            # calculate the number of pods
            pods_n = ""
            @services.each do |k, s|
              pods_number = s.pods[s.selector].length
              pods_n += "#{k}: #{pods_number} "
              @allocation_bench << "#{now},#{k},#{per_component_stats[k].received},#{per_component_stats[k].mean},#{pods_number}\n"
              #puts "#{now},#{k},#{per_component_stats[k].received},#{per_component_stats[k].mean},#{pods_number}\n"
              # just to print the allocation map
            end

            #puts "++++++++++++++++\n"+
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
              #puts "Node #{check_node.node_id} on cluster #{check_node.cluster_id} is alive"
              check_node.eviction_count = 0
            else
              #puts "Node #{check_node.node_id} on cluster #{check_node.cluster_id} is dead"
              check_node.eviction_count += 1
              if check_node.eviction_count == check_node.eviction_threshold
                #puts "Node #{check_node.node_id} on cluster #{check_node.cluster_id} is going to be evicted"
                new_event(Event::ET_DEALLOCATE_NODE, [check_node, cluster_repository[check_node.cluster_id]], @current_time, nil)
              end
            end

            # schedule next control
            if @current_time + check_node.heartbeat_period < cooldown_treshold
              new_event(Event::ET_NODE_CONTROL, check_node, @current_time + check_node.heartbeat_period, nil)
            end
            
          #try to implement shutdown node event. Example --> select a random node and put ready to false
          when Event::ET_SHUTDOWN_NODE
            node = e.data
            #puts "Node #{node.node_id} on cluster #{node.cluster_id} is going to shutdown"
            break if node.ready == false
            node.ready = false
            #puts "Shutdown event: Node #{node.node_id} on cluster #{node.cluster_id}"
            # schedule next control
            if @current_time + node.heartbeat_period < cooldown_treshold
              new_event(Event::ET_NODE_CONTROL, node, @current_time + node.heartbeat_period, nil)
            end


          when Event::ET_DEALLOCATE_NODE
            node, target_cluster = e.data

            node.pod_id_list.each do |pod_id|
              pod = node.retrieve_pod(pod_id)
              new_event(Event::ET_EVICT_POD, [pod, node], @current_time, nil)
            end

            target_cluster.node_number -= 1
            puts "Cluster #{target_cluster.cluster_id} has now #{target_cluster.node_number} nodes"
            target_cluster.remove_node(node)
            #puts "Node Deallocated: node_id: #{node.node_id} in cluster #{target_cluster.cluster_id} at time #{e.time}"
            #puts "Cluster #{target_cluster.cluster_id} has now #{target_cluster.nodes.length} nodes"
            #if @current_time + node.heartbeat_period < cooldown_treshold
            #  new_event(Event::ET_NODE_CONTROL, node, @current_time + node.heartbeat_period, nil)
            #end
            cluster_repository.each do |k, cluster|
              cluster.nodes.each do |k, node|
                new_event(Event::ET_NODE_CONTROL, node, @current_time + node.heartbeat_period, nil)
              end
            end

          when Event::ET_EVICT_POD
            pod, node = e.data
            raise "Pod #{pod.pod_id} is not running on node #{node.node_id}" unless node.pod_id_list.include?(pod.pod_id)
            puts "Pod #{pod.pod_id} is going to be evicted from node #{node.node_id}"
            puts "Node resources before eviction: #{node.available_resources_cpu} #{node.available_resources_memory}"
            pod.evict_pod
            @evicted_pods[pod.pod_id] = pod
            puts "Pod #{pod.pod_id} is now evicted"
            
            puts "Current Evicted Pods:"
            @evicted_pods.each do |pod_id, pod|
              puts "Pod ID: #{pod_id}, Name: #{pod.podName}, Original Node: #{pod.node&.node_id}"
            end

            puts "Node resources after eviction: #{node.available_resources_cpu} #{node.available_resources_memory}"

        end
      end

      # puts "========== Simulation Finished =========="

      # TODO -- IMPLEMENT COST EVALUATION HERE
      #costs = @evaluator.evaluate_fixed_costs_cpu(vm_allocation)


     #puts "\n\n"
     #@sim_bench.close
     #puts "Finished after #{now - @configuration.end_time}"

      allocation_map = {}
      cluster_repository.each do |_,c|
         #puts "Allocation -- #{c.name} Pods: #{pods}"
         pods = 0
         c.nodes.values.each do |n|
          pods += n.pod_id_list.length
          #puts "node_id: #{n.node_id}: pods: #{n.pod_id_list.length}"
         end
         allocation_map[c.name] = {tier: c.tier, pods: pods}
         #puts "Allocation -- #{c.name} Pods: #{pods}"
      end
      #puts "#{stats.to_csv}"
     puts "====== Evaluating new allocation ======\n" +
           #"costs: #{costs}\n" +
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
      # puts "Res: #{res}"
      # res

      #puts "Percentage of requests within ms"
      #per_workflow_and_customer_stats[1][1].shorter_than.each_key do |t|
      #  puts "#{(per_workflow_and_customer_stats[1][1].shorter_than[t] / per_workflow_and_customer_stats[1][1].closed.to_f) * 100}% #{t}s"
      #end
      #-stats.mean
      #return 0
      #return stats.to_csv
      @sim_bench << stats.to_csv
      @sim_bench.close
      path_file = @allocation_bench.path
      @allocation_bench.close
      path_request = @request_profile.path
      @request_profile.close
      #puts "python figure_generator/tnsm-figure.py #{path_file} #{path_request}"
      #`python figure_generator/tnsm-figure.py #{path_file} #{path_request}`
      #return stats.to_csv # change this
    end
  end
end
