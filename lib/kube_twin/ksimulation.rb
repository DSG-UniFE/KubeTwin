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
require_relative './mdn'

require 'json'
require 'logger'
require 'torch-rb'

module KUBETWIN
  class KSimulation
    UNFEASIBLE_ALLOCATION_EVALUATION = { unfeasible_configuration: -Float::INFINITY }.freeze
    attr_reader :start_time, :cluster_repository

    DEFAULT_NUM_REQS = 5000
    CONNECT_TIME = 0.00148205
    DEFAULT_CPU_PER_NODE = 4000.0 # in mCPU
    SEED = 123

    def initialize(opts = {})
      @configuration = opts[:configuration]
      @evaluator     = opts[:evaluator]
      @results_dir   = opts[:results_dir]
      @num_reqs      = opts[:num_reqs]
      @num_reqs = DEFAULT_NUM_REQS if @num_reqs.nil?
      @results_dir += '/' unless @results_dir.nil?
      @microservice_mdn = {}
      @mapping = nil
      @logger = opts[:logger] || Logger.new(STDOUT)
      @logger.level = opts[:log_level] || Logger::INFO
    end

    def new_event(type, data, time, destination)
      e = Event.new(type, data, time, destination)
      @event_queue << e
    end

    def now
      @current_time
    end

    def get_workflow_components(workflow)
      components = []
      workflow[:component_sequence].each do |cs|
        components << cs[:name]
      end
      components
    end

    ## just an helper method to create the cluster configuration
    def self.create_cluster_configuration(sim_conf)
      if sim_conf.federation.nil?
        cid = -1
        # create clusters and relative nodes and store them in a repository
        Hash[
            @configuration.clusters.map do |k, v|
              cid += 1
              @logger.debug "Cluster: #{k} #{v}"
              [k, Cluster.new(id: k, fixed_hourly_cost_cpu: nil,
                              fixed_hourly_cost_memory: nil, **v)]
            end
          ]
      else
        federation = JSON.parse(sim_conf.federation, symbolize_names: true)
        # puts "Federation resources: #{federation[:resources]}"
        cid = -1
        Hash[
          federation[:resources].map do |k, v|
            # puts "k: #{k} v: #{v}"
            node_number = v[:nodes].length if v[:nodes]
            node_number ||= v[:cpu].to_i / DEFAULT_CPU_PER_NODE
            node_cpu = v[:cpu].to_i / node_number
            node_mem = v[:mem].to_i / node_number
            # we assume that the resources are homogeneous
            # Since we only have an aggregate for CPU and Memoryù
            # we assume to divide clusters equally. Each node
            # has 2000 milliCPU and 2 GB of Memory (2048 MB)
            cid += 1
            [k, Cluster.new(id: cid, fixed_hourly_cost_cpu: nil,
                            fixed_hourly_cost_memory: nil, location_id: cid,
                            node_resources_cpu: node_cpu.to_i,
                            node_resources_memory: node_mem.to_i, name: k,
                            node_number: node_number.to_i, type: :mec, tier: 'local')]
          end
          ]
      end
    end

    # rss is replica set
    # css is service configuration
    def evaluate_allocation(rss = nil, css = nil, mtt = nil, lm = nil, mapping = nil, replicas_mapping = nil)
      # seeds
      latency_seed = @configuration.seeds[:communication_latencies]
      @configuration.seeds[:service_times]
      if @configuration.seeds[:next_component_selection]
        Random.new(@configuration.seeds[:next_component_selection])
      else
        Random.new
      end

      # mapping is the mapping of microservices to clusters
      @mapping ||= mapping
      @replicas_mapping ||= replicas_mapping

      # setup simulation start and current time
      @current_time = @start_time = @configuration.start_time

      # here need to retrieve configuration cost also
      evaluation_cost = {}

      @configuration.evaluation[:cluster_hourly_cost].each_with_index do |c, cid|
        evaluation_cost[cid] = c[:fixed_cpu_hourly_cost]
        # leave memory out for now
      end

      # Let's check if the configuration file contains the description of the
      # Liqo federation

      federation = nil
      if @configuration.federation.nil?
        cid = -1
        # create clusters and relative nodes and store them in a repository
        @cluster_repository = Hash[
          @configuration.clusters.map do |k, v|
            cid += 1
            price = evaluation_cost[cid] || 0.100
            @logger.debug "Cluster: #{k} #{v}"
            [k, Cluster.new(id: k, fixed_hourly_cost_cpu: price,
                            fixed_hourly_cost_memory: price, **v)]
          end
        ]
      else
        # create clusters and relative nodes and store them in a repository
        # Use this as a reference
        # federation \
        # {
        #  "resources": [
        #  "rome": ["cpu": 200, "mem": 8]
        # "milan": ["cpu": 150, "mem": 8]],
        #  "latencies": [["src": "rome", "dst": "milan", "value": 6]]
        # }
        # Convert the @configuration.federation json object into a ruby hash
        federation = JSON.parse(@configuration.federation, symbolize_names: true)
        # puts "Federation resources: #{federation[:resources]}
        cid = -1
        @clusters_mapping = {}
        federation[:resources].each_key do |k|
          cid += 1
          @clusters_mapping[cid] = k
        end

        cid = -1
        @cluster_repository = Hash[
          federation[:resources].map do |k, v|
            # puts "k: #{k} v: #{v}"
            node_number = v[:nodes].length if v[:nodes]
            node_number ||= v[:cpu].to_i / DEFAULT_CPU_PER_NODE
            node_cpu = v[:cpu].to_i / node_number
            node_mem = v[:mem].to_i / node_number
            # we assume that the resources are homogeneous
            # Since we only have an aggregate for CPU and Memoryù
            # we assume to divide clusters equally. Each node
            # has 2000 milliCPU and 2 GB of Memory (2048 MB)
            cid += 1
            price = evaluation_cost[cid] || 0.100
            # @logger.info "Cluster k: #{k}"
            [k, Cluster.new(id: k, fixed_hourly_cost_cpu: price,
                            fixed_hourly_cost_memory: price, location_id: cid,
                            node_resources_cpu: node_cpu.to_i,
                            node_resources_memory: node_mem.to_i, name: k,
                            node_number: node_number.to_i, type: :mec, tier: 'local')]
          end
          ]
      end

      # @logger.info "Clusters: #{@cluster_repository[@clusters_mapping[0]].cluster_id}"
      # abort
      node_id = 0
      @cluster_repository.values.each do |c|
        node_number = c.node_number
        node_number.times do |_i|
          # we suppose to have nodes with homogenous capabilities in a
          # cluster
          # set also the cluster_id here
          n = Node.new(node_id, c.node_resources_cpu, c.node_resources_memory, c.cluster_id, c.type)
          @logger.debug "Creating node #{n.node_id} cluster: #{n.cluster_id} with resources: #{n.resources_cpu} #{n.resources_memory}"
          c.add_node(n)
          node_id += 1
        end
      end

      # If mapping is not nil, get the integer values of mapping to get the cluster id
      # just need to the @cluster_repository to get the cluster id
      if @mapping
        @mapping.each_with_index do |cid, i|
          # get the cluster id from the cluster repository with key at position cid
          cluster = if cid == @cluster_repository.keys.length
                      :none
                    else
                      @cluster_repository.keys[cid]
                    end
          @mapping[i] = cluster.to_sym
        end
      end

      # create latency manager, check if we should use the simplified latency model
      # given by the federation or if we can use the provided map
      if @configuration.federation.nil?
        latency_models = lm.nil? ? @configuration.latency_models : lm
        latency_manager = if latency_seed
                            LatencyManager.new(latency_models, seed: latency_seed)
                          else
                            LatencyManager.new(latency_models)
                          end
      else
        # use the federation latencies
        #  "latencies": [["src": "rome", "dst": "milan", "value": 6]]
        # here is very simple, we can assume simmetric latencies
        # from source to destination and vicersa
        # we assume that the latencies are in milliseconds
        latency_models = federation[:latencies]
        # change cluster name to cluster id
        latency_models = latency_models.map do |lm|
          src = @cluster_repository[lm[:src].to_sym]
          dst = @cluster_repository[lm[:dst].to_sym]
          raise "Cannot find cluster #{lm[:src]} or #{lm[:dst]}" if src.nil? || dst.nil?

          { src: src.location_id, dst: dst.location_id, value: lm[:value].to_f / 2 }
        end
        latency_manager = LatencyManagerFederation.new(latency_models, seed: latency_seed)
      end

      # information regarding microservices
      @microservice_types = mtt.nil? ? @configuration.microservice_types : mtt
      @logger.debug "#{@microservice_types} #{@microservice_types.nil?}"
      @microservice_types.each do |k, v|
        next if v[:mdn_file].nil?

        model = KUBETWIN::MDN.new(
          weights_path: v[:mdn_file],
          scaler_path: v[:mdn_file]
        )
        @microservice_mdn[k] = { model: model, st: {} }
      end

      def retrieve_mdn_model(service_name, rps)
        return nil unless @microservice_mdn[service_name]

        # warn "Called retrieve_mdn_model for service #{service_name} with RPS: #{rps}"
        model = @microservice_mdn[service_name][:model]

        if @microservice_mdn[service_name][:st][rps].nil?
          params = model.get_mixture_params_for_helper(rps)
          components = ERV::GaussianMixtureHelper.RawParametersToMixtureArgsFixedWeights(*params)
          mixture_hash = { distribution: :mixture, args: components }
          @microservice_mdn[service_name][:st][rps] = ERV::RandomVariable.new(mixture_hash)
        end

        # warn "MDN: loaded model for service #{service_name}: #{@microservice_mdn[service_name][:st]&.length}"

        @microservice_mdn[service_name][:st][rps]
      end

      # @logger.debug "init mdns #{@microservice_mdn}"

      # information regarding customers
      customer_repository = @configuration.customers
      workflow_type_repository = @configuration.workflow_types

      # initialize statistics --- leave for later
      stats = Statistics.new

      # statistics for servicemdnmdn
      hpa_component_stats = Hash[
        @microservice_types.keys.map do |m_id|
          [
            m_id,
            ComponentStatistics.new
          ]
        end
      ]

      per_component_stats = Hash[
        @microservice_types.keys.map do |m_id|
          @logger.debug "Microservice type: #{m_id}"
          [
            m_id,
            ComponentStatistics.new
          ]
        end
      ]

      per_workflow_and_customer_stats = Hash[
        workflow_type_repository.keys.map do |wft_id|
          [
            wft_id,
            Hash[
              customer_repository.keys.map do |c_id|
                [c_id, Statistics.new(@configuration.custom_stats.find do |x|
                  x[:customer_id] == c_id && x[:workflow_type_id] == wft_id
                end || {})]
              end
            ]
          ]
        end
      ]

      # Separate workflow and chain stats to do so we need to create a chain and look if microservices in that chain
      # are within a workflow and then get the wokrflow id
      @chain_repository = {}
      per_chain_and_customer_stats = {}

      # reqs_received_per_workflow_and_customer = Hash[
      #  workflow_type_repository.keys.map do |wft_id|
      #    [wft_id, Hash[customer_repository.keys.map { |c_id| [c_id, 0] }]]
      #  end
      # ]

      # Read policies from configuration
      policies = @configuration.policies || {}
      availability_policy = nil

      unless policies.empty?
        policies.each do |policy|
          @logger.debug "Policy: #{policy}"
          # if contains latency_max_value_ms
          if policy[:properties] && policy[:properties][:latency_max_value_ms]
            @logger.debug "  Latency max value (s): #{policy[:properties][:latency_max_value_ms] / 1E3}"
            policy[:targets].each do |target|
              @logger.debug "  Target: #{target}"
              # check if target is a microservice type
              per_component_stats[target].add_custom_kpis(longer_than: [policy[:properties][:latency_max_value_ms] / 1E3])
              @logger.debug per_component_stats[target].longer_than
            end
          end
          if policy[:properties] && policy[:properties][:response_time_value_ms]
            @logger.debug "  Response time value (s): #{policy[:properties][:response_time_value_ms] / 1E3}"
            policy[:targets].each do |target|
              @logger.debug "  Target: #{target}"
              per_component_stats[target].add_custom_kpis(longer_than: [policy[:properties][:response_time_value_ms] / 1E3])
            end
          end
          if policy[:properties] && policy[:properties][:target_availability_percentage]
            @logger.debug "  Target availability percentage: #{policy[:properties][:target_availability_percentage]}"
            availability_policy = policy[:properties][:target_availability_percentage].to_f / 100.0
          end
          next unless policy[:properties] && policy[:properties][:service_chain_max_latency_ms]

          sc_max_latency = policy[:properties][:service_chain_max_latency_ms].to_f / 1E3
          chain = policy[:chains]
          @logger.debug "  Service Chain Max Latency: #{sc_max_latency}"
          @logger.debug "  Targets: #{chain}"
          # we can add this to the evaluator
          # :chains=>["reviews", "ratings"], :targets=>[]}
          # Check for each workflow type if the chain matches
          # create the chain in the chain stats
          wf_cid = nil
          workflow_type_repository.each do |wft_id, wf|
            # verify if chain is part of the workflow
            if chain.to_set.subset?(get_workflow_components(wf).to_set)
              wf_cid = wft_id
              break
            end
          end

          raise 'Chain not found in available workflows' if wf_cid.nil?

          cs = []
          chain.each do |name|
            cs << { name: name }
          end

          @chain_repository[wf_cid] = { component_sequence: cs }

          # @logger.info "chain_repository #{@chain_repository[wf_cid]}"

          per_chain_and_customer_stats[wf_cid] = Hash[
                customer_repository.keys.map do |c_id|
                  [c_id, Statistics.new(@configuration.custom_stats.find do |x|
                    x[:customer_id] == c_id && x[:workflow_type_id] == wf_cid
                  end || {})]
                end
          ]

          customer_repository.each do |c_id, _|
            @logger.debug "Customer: #{c_id}"
            @logger.debug "Adding custom KPI for workflow #{per_chain_and_customer_stats[wf_cid][1]}"
            per_chain_and_customer_stats[wf_cid][c_id].add_custom_kpis(longer_than: [sc_max_latency])
          end
        end

        #           per_workflow_and_customer_stats.each do |wft_id, cust_stats|
        #             @logger.debug "  Workflow Type: #{wft_id}"
        #             @logger.debug "  Customers: #{cust_stats.keys}"
        #             workflow = workflow_type_repository[wft_id]
        #             workflow_chain = workflow[:component_sequence].map { |cs| cs[:name] }
        #             # CHECK IF chain is a subsequence of workflow_chain
        #             @logger.debug "  Workflow Chain: #{workflow_chain}"
        #             next unless workflow_chain == chain
      end

      @logger.debug "per_chain_and_customer_stats: #{per_chain_and_customer_stats}"

      # abort

      # Initialize Kubernetes internal objects/services

      @kube_dns = KubeDns.new

      # debug variables
      @generated = 0
      @arrived = 0
      @processed = 0
      @forwarded = 0

      @replica_sets = {}

      # init from simulation or optimizator
      crs = if rss.nil?
              @configuration.replica_sets
            else
              rss
            end

      # first create the replica_set
      crs.each do |name, conf|
        # nil is service here
        # do we need a reference to service in ReplicaSet?
        @replica_sets[name] = ReplicaSet.new(name, conf[:selector],
                                             conf[:replicas], nil)
      end

      replicas_by_microservice = Hash.new(0)
      @replica_sets.each_value do |rs|
        replicas_by_microservice[rs.selector] += rs.replicas.to_i
      end

      puts ''
      puts ''
      puts '====== Replica snapshot at simulation start ======'
      replicas_by_microservice.sort.each do |selector, replicas|
        puts "microservice: #{selector}, replicas: #{replicas}"
      end
      puts "total_replicas: #{replicas_by_microservice.values.inject(0) { |sum, value| sum + value }}"
      puts '=================================================='

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

      # @logger.debug @horizontal_pod_autoscaler_repo

      # Then create services and pods at startup
      # not simulating starup events in the MVP

      # init from simulation or optimizator
      css = @configuration.services if css.nil?

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
      @kube_scheduler = KubeScheduler.new(@cluster_repository)

      pod_id = 0
      ms_id = 0
      saturation_penalties = 0
      @replica_sets.each do |_k, rs|
        # here we need to create pods and register them into a Service
        pods_created = 0
        pods_tbc = rs.replicas.to_i

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
          node = nil
          if @mapping
            cid = @mapping[ms_id]
            @logger.debug "Mapping: #{@mapping}, got cluster_id: #{cid}"
            node = @kube_scheduler.get_node_from_cluster(reqs_c, reqs_m, cid)
          # if node not found --> go for what available
          elsif @replicas_mapping
            # let's get the mapping from somehting like this --> {:a => 10, :b => 100, :c => 30 }
            cid = @clusters_mapping[@replicas_mapping[pod_id]]
            node = @kube_scheduler.get_node_from_cluster(reqs_c, reqs_m, cid)
            saturation_penalties += 1 if node.nil?
            # @logger.info "Replicas Mapping: #{@replicas_mapping}"
          end

          node = @kube_scheduler.get_node(reqs_c, reqs_m, node_affinity) if node.nil?
          @logger.debug "Node: #{node} for selector: #{selector} with requirements: #{reqs_c} #{reqs_m}"
          # if still cannot be allocated
          next if node.nil?

          pods_created += 1
          # no more resources
          # once we know where the pod is going to be allocated
          # we can retrieve also the service_time_distribution
          # depending on its cluster type

          pod = Pod.new(pod_id, "#{selector}_#{pod_id}", node, selector, sct)
          pod.startUpPod

          # assign resources for the pod
          node.assign_resources(pod, reqs_c, reqs_m)
          # get the service here and assign the pod to the service
          # convert string to sym
          # we could also assing the service to the replica set
          s = @services[selector]
          s.assignPod(pod)
          pod_id += 1
        end
        # return a penalty if no pods were created for rs
        @logger.debug "{selector} Pods Created: #{pods_created}/#{pods_tbc}"
        return - 1_000 if pods_created != pods_tbc

        # increment microservice id
        ms_id += 1
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
        # puts "#{@configuration.request_generation}"
        rg = RequestGeneratorR.new(@configuration.request_generation)
        # this is to avoid mismatch when reproducing logs
        req_attrs = rg.generate(now)
        @current_time = @start_time = req_attrs[:generation_time] - 2
        @configuration.set_start(@current_time)
        new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], rg)
      else
        @configuration.request_gen.each do |k, _v|
          @to_generate += @configuration.request_gen[k][:num_requests]
          rg = RequestGenerator.new(@configuration.request_gen[k])
          req_attrs = rg.generate(@configuration.request_gen[k][:starting_time].to_i)
          new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], rg)
        end
      end
      # new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)

      # generate first HPA check
      @horizontal_pod_autoscaler_repo.each do |name, hpa|
        new_event(Event::ET_HPA_CONTROL, [name, hpa], @current_time + hpa.period_seconds, nil)
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
      unless @stats_print_interval.nil?
        new_event(Event::ET_STATS_PRINT, nil, warmup_threshold + @stats_print_interval,
                  nil)
      end

      requests_being_worked_on = 0
      current_event = 0

      # benchmark file
      Time.now.strftime('%Y%m%d%H%M%S')
      # @sim_bench = File.open("csv_bench_#{time}.csv", 'w')
      # @allocation_bench = File.open("allocation_bench_#{time}.csv", 'w')
      # @request_profile = File.open("request_profile_#{time}.csv", 'w')
      # @request_profile << "Time,CRequests\n"
      @last_second = @current_time.to_i
      @req_in_sec = 0

      # @allocation_bench << "Time,Component,Request,TTP,Pods\n"

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
            # @request_profile << "#{@current_time.to_i},#{@req_in_sec}\n"
            @req_in_sec = 1
            @last_second = @current_time.to_i
          elsif (@current_time.to_i - 1) > @last_second
            @last_second = @current_time.to_i
          end

          # find closest data center
          customer_location_id =
            customer_repository
            .dig(req_attrs[:customer_id], :location_id)

          # find first component name for requested workflow
          workflow = workflow_type_repository[req_attrs[:workflow_type_id]]
          if workflow.nil? || workflow[:component_sequence].nil?
            puts "DEBUG: workflow type #{req_attrs[:workflow_type_id]} = #{workflow.inspect}"
            puts "DEBUG: workflow type repository = #{workflow_type_repository.inspect}"
          end

          first_component_name = workflow[:component_sequence][0][:name]

          # puts "DEBUG: first_component_name = #{first_component_name} #{workflow.inspect}"
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
          cluster = @cluster_repository[cluster_id]

          arrival_time = @current_time + latency_manager.sample_latency_between(customer_location_id,
                                                                                cluster.location_id)
          # here we should also add the HTTP connection time (8 ms)
          arrival_time += CONNECT_TIME

          # generate the request here
          new_req = Request.new(**req_attrs.merge!(initial_data_center_id: cluster_id,
                                                   arrival_time: arrival_time))

          # schedule arrival of current request
          new_event(Event::ET_REQUEST_ARRIVAL, [new_req, pod], arrival_time, nil)

          # schedule generation of next request
          if @current_time < cooldown_treshold && @generated < @to_generate # warmup_threshold
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

            # cluster = @cluster_repository[req.data_center_id]
            # update reqs_received_per_workflow_and_customer
            # reqs_received_per_workflow_and_customer[req.workflow_type_id][req.customer_id] += 1

            # find next component name
            workflow = workflow_type_repository[req.workflow_type_id]
            chain = @chain_repository[req.workflow_type_id] || nil
            # next_component_name = workflow[:component_sequence][req.next_step][:name]
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
          pod = e.destination

          # Check if this is a parallel branch request
          branch_name = req.instance_variable_get(:@branch_name)
          if branch_name
            # For parallel branch requests, use the branch name directly
            component_name = branch_name
          else
            # For regular requests, use the workflow sequence
            workflow = workflow_type_repository[req.workflow_type_id]
            component_name = workflow[:component_sequence][req.next_step][:name]
          end

          # increase count of received requests in hpa_component_stats
          hpa_component_stats[component_name].request_received
          per_component_stats[component_name].request_received

          # here we should use the delegator
          # puts "#{now},#{pod.container.containerId},#{pod.container.request_queue.length}\n"
          pod.container.new_request(self, req, time)

        when Event::ET_WORKFLOW_STEP_COMPLETED

          # retrieve request and vm
          req = e.data
          container = e.destination
          @processed += 1

          # unless next_ms
          container.request_finished(self, e.time) if container.wait_for.empty?

          # tell the old container that it can start processing another request
          # if microservice should wait for one other
          oc = container.free_linked_container
          oc.request_finished(self, e.time) if oc

          # Handle parallel branch completion
          if req.instance_variable_get(:@parent_request)
            parent_req = req.instance_variable_get(:@parent_request)
            branch_name = req.instance_variable_get(:@branch_name)

            # Register branch completion statistics
            if branch_name && hpa_component_stats[branch_name] && per_component_stats[branch_name]
              hpa_component_stats[branch_name].record_request(req, now)
              per_component_stats[branch_name].record_request(req, now)
            end

            if parent_req && parent_req.parallel_context
              parent_req.complete_branch(branch_name, req, @current_time)
              parent_req.parallel_context[:branch_count] -= 1

              # Check if all branches are completed
              if parent_req.parallel_context[:branch_count] <= 0
                # All parallel branches completed, continue with parent request
                parent_req.instance_variable_set(:@parallel_context, nil)
                new_event(Event::ET_WORKFLOW_STEP_COMPLETED, parent_req, e.time, container)
              end
            end
            # Skip further processing for branch requests
            next
          end

          current_cluster = @cluster_repository[req.data_center_id]
          # find the next workflow
          workflow = workflow_type_repository[req.workflow_type_id]
          chain = @chain_repository[req.workflow_type_id] || nil

          # Get current component name safely - handle parallel components
          current_component_step = workflow[:component_sequence][req.worked_step]
          current_component_name = if current_component_step[:type] == 'parallel'
                                     # For parallel components, we don't track them in stats since they're containers
                                     nil
                                   else
                                     current_component_step[:name]
                                   end
          # puts "current_component_name #{current_component_name}"

          if !chain.nil? && !current_component_name.nil? && chain[:component_sequence][0][:name] == current_component_name
            # we are entering the chain, set the workflow to be the chain
            # @logger.info "Request #{req.rid} #{current_component_name} entering chain #{chain}"
            req.chain_entered(@current_time)
            per_chain_and_customer_stats[req.workflow_type_id][req.customer_id].request_received
          end

          if !chain.nil? && !current_component_name.nil? && (chain[:component_sequence][-1][:name] == current_component_name)
            # @logger.info "Request #{req.rid} #{current_component_name} exiting chain #{chain}"
            req.finished_chain(@current_time)
            per_chain_and_customer_stats[req.workflow_type_id][req.customer_id].record_request(req, now, chain = true)
          end

          # Skip processing if request is waiting for parallel branches
          return if req.parallel_context && req.parallel_context[:branch_count] > 0

          # register step completion only for regular components (not parallel containers)
          if current_component_name
            hpa_component_stats[current_component_name].record_request(req, now)
            per_component_stats[current_component_name].record_request(req, now)
          end

          req.ttr_step(@current_time)

          # check if there are other steps left to complete the workflow
          if req.next_step < workflow[:component_sequence].size

            next_step_config = workflow[:component_sequence][req.next_step]

            # Handle parallel execution
            if next_step_config[:type] == 'parallel'
              # Start parallel execution for all branches
              branches = next_step_config[:branches]
              req.start_parallel_execution(branches)

              # Create separate request flows for each branch
              branches.each do |branch|
                branch_req = req.clone_for_parallel_branch(branch[:name])

                # Each branch starts with the branch component
                service = @kube_dns.lookup(branch[:name])
                next if service.nil? # Skip if service not found

                pod = service.get_pod(branch[:name])
                next if pod.nil? # Skip if no pod available

                # Schedule the branch request
                forwarding_time = e.time
                cluster_id = pod.node.cluster_id
                cluster = @cluster_repository[cluster_id]

                transmission_time =
                  latency_manager.sample_latency_between(current_cluster.location_id, cluster.location_id)
                branch_req.update_transfer_time(transmission_time)
                forwarding_time += transmission_time

                branch_req.data_center_id = cluster.cluster_id

                # Create forwarding event for each branch
                new_event(Event::ET_REQUEST_FORWARDING, branch_req, forwarding_time, pod)
              end

              # Move to next step after parallel block (use step_completed)
              req.step_completed(0.0) # Duration 0 for parallel initiation

              # Parent request waits for branches to complete
              next
            else
              # Regular component processing
              next_component_name = next_step_config[:name]

              # resolve the next component name
              service = @kube_dns.lookup(next_component_name)
            end

            # e.time should be equivalent to @current_time
            forwarding_time = e.time

            # get a pod from the one available
            pod = service.get_pod(next_component_name) # same as selector

            # we need to get a reference to the cluster where the pod is running
            cluster_id = pod.node.cluster_id
            cluster = @cluster_repository[cluster_id]

            transmission_time =
              latency_manager.sample_latency_between(current_cluster.location_id, cluster.location_id)
            req.update_transfer_time(transmission_time)
            forwarding_time += transmission_time

            # update request's current data_center_id / cluster_id
            req.data_center_id = cluster.cluster_id

            # make sure we actually found a pod
            unless pod
              raise 'Cannot find a Pod running a component of type ' +
                    "#{next_component_name} in any cluster!"
            end

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
                @cluster_repository[req.data_center_id].location_id,
                # customer location
                customer_repository.dig(req.customer_id, :location_id)
              )

            raise "Negative transmission time (#{transmission_time})!" unless transmission_time >= 0.0

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
          # puts "#{req.arrival_time} #{now}"
          if now >= @configuration.end_time
            raise "Processing request after the simulation time current:#{now} end:#{@configuration.end_time}"
          end

          # update stats
          if req.arrival_time > warmup_threshold && now < @configuration.end_time
            # decrease the number of requests being worked on
            requests_being_worked_on -= 1

            # collect request statistics
            stats.record_request(req, @current_time)

            # collect request statistics in per_workflow_and_customer_stats
            per_workflow_and_customer_stats[req.workflow_type_id][req.customer_id].record_request(req, @current_time)
            # @benchmark << "#{req.rid},#{req.ttr(@current_time)}\n"
          end

        # schedule generation of next request
        # here we want also to cut the number of requests
        # for fitting
        # if @current_time < cooldown_treshold && stats.n < @num_reqs
        #  req_attrs = rg.generate(@current_time)
        #  new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)
        # end

        when Event::ET_HPA_CONTROL
          hname, hpa = e.data
          # is computed by taking the average of the given metric across
          # all Pods in the HorizontalPodAutoscaler's scale target
          # retrieve desired replica_set ...
          # puts hname

          s = @services[hpa.name]

          raise 'Impossible to retrieve s' if s.nil?

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
            pods += 1
            next if pod.container.served_request.zero?

            current_metric += pod.container.total_queue_processing_time / pod.container.served_request
            # puts "total queue time: #{pod.container.total_queue_time}"
            # puts "served request: #{pod.container.served_request}"
            # reset container metric
            # calculate them each time period
            pod.container.reset_metrics
            # puts "#{pod.container.current_processing_metric}"
          end
          current_metric /= pods.to_f

          puts '**** Horizontal Pod Autoscaling ****'
          puts "#{hpa.name} pods: #{pods} average processing_time: #{current_metric} desired_metric: #{desired_metric}"
          puts '************************************'

          if pods == 0
            puts 'Ending the simulation!'
            # break
            # new_event(Event::ET_END_OF_SIMULATION, nil, now, nil)
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
            d_replicas = (pods * scaling_ratio).ceil
            @logger.debug "pods: #{pods} scaling_ratio: #{scaling_ratio} d_replicas #{d_replicas} to_scale #{d_replicas - pods}"
            # @logger.debug "desired_replicas: #{d_replicas} current_replicas #{pods}"
            # get the replica set
            rs = @replica_sets[hname]
            to_scale = d_replicas <= hpa.max_replicas ? (d_replicas - pods) : (hpa.max_replicas - pods)

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
                node = @kube_scheduler.get_node(reqs_c, reqs_m, node_affinity)

                break if node.nil? # check here --- what happens if no nodes are available

                pod = Pod.new(pod_id, "#{selector}_#{pod_id}", node, selector, sct)
                pod.startUpPod
                # assign resources for the pod
                node.assign_resources(pod, reqs_c, reqs_m)
                s.assignPod(pod)
                pod_id += 1
              end
            else
              # we need to select some pods to terminate
              # deal with requests currently being processed
              # @logger.debug "min #{hpa.min_replicas}"
              to_scale = d_replicas > hpa.min_replicas ? (pods - d_replicas).abs : 0
              unless to_scale.zero?
                # @logger.debug "deactivating pods"
                ppl = s.pods[hpa.name].sample(to_scale)
                ppl.each do |p|
                  p.deactivate_pod
                  s.delete_pod(s.selector, p)
                end
              end
            end

          end

          # schedule next control
          if @current_time + hpa.period_seconds < cooldown_treshold
            new_event(Event::ET_HPA_CONTROL, [hname, hpa], @current_time + hpa.period_seconds, nil)
          end

        when Event::ET_END_OF_SIMULATION
          # FOR NOW KEEP PROCESSING REQUEST
          # puts "#{e.time}: end simulation"
          e = @event_queue.shift until @event_queue.empty?

          # print some stats (useful to track simulation data)
        when Event::ET_STATS_PRINT

          # calculate the number of pods
          pods_n = ''
          @services.each do |k, s|
            pods_number = s.pods[s.selector].length
            pods_n += "#{k}: #{pods_number} "
            # @allocation_bench << "#{now},#{k},#{hpa_component_stats[k].received},#{hpa_component_stats[k].mean},#{pods_number}\n"
            # puts "#{now},#{k},#{hpa_component_stats[k].received},#{hpa_component_stats[k].mean},#{pods_number}\n"
            # just to print the allocation map
          end

          # puts "++++++++++++++++\n"+
          # "#{now}\n" +
          # "#{stats.to_s}\n" +
          # "workflow_stats: #{per_workflow_and_customer_stats.to_s}\n"+
          # "component_stats: #{hpa_component_stats.to_s}\n"+
          # ls"#{pods_n}"

          # reset also comoponent statistics

          hpa_component_stats = Hash[
            @microservice_types.keys.map do |m_id|
              [
                m_id,
                ComponentStatistics.new
              ]
            end
          ]

          next_event_time = @current_time + @stats_print_interval

          if (next_event_time < cooldown_treshold) && !@stats_print_interval.nil? && !@stats_print_interval.nil?
            new_event(Event::ET_STATS_PRINT, nil, @current_time + @stats_print_interval,
                      nil)
          end

        when Event::ET_ALLOCATE_NODE
          new_node, target_cluster = e.data
          # target_cluster.node_number += 1
          target_cluster.add_node(new_node)
          puts "New Node Allocated: node_id: #{new_node.node_id} in cluster #{target_cluster.cluster_id} at time #{e.time}"

        when Event::ET_DEALLOCATE_NODE
          new_node, target_cluster = e.data
          # target_cluster.node_number += 1
          target_cluster.remove_node(new_node)
          puts "Node Deallocated: node_id: #{new_node.node_id} in cluster #{target_cluster.cluster_id} at time #{e.time}"

        end
      end

      # puts "========== Simulation Finished =========="
      # puts "Finished after #{now - @configuration.end_time}"

      # Keep track of the number of pods per component and where they are allocated
      allocation_map = {}
      # Keep track of how many nodes per cluster we are using
      node_utilization = {}
      costs = 0
      @logger.debug 'Simulation over'
      @cluster_repository.each do |_, c|
        pods = 0
        node = 0
        c.nodes.values.each do |n|
          if n.pod_id_list.length > 0
            pods += n.pod_id_list.length
            node += 1
          end
          # puts "node_id: #{n.node_id}: pods: #{n.pod_id_list.length}"
        end
        allocation_map[c.name] = { tier: c.tier, pods: pods }
        node_utilization[c.name] = node
        # Assume 24 hrs of operation
        c.fixed_hourly_cost_cpu = 0.100 unless c.fixed_hourly_cost_cpu
        costs += c.fixed_hourly_cost_cpu * node * 24
        # puts "Allocation -- #{c.name} Pods: #{pods}"
      end

      # TODO: -- IMPLEMENT COST EVALUATION HERE
      # costs = @evaluator.evaluate_fixed_costs_cpu(vm_allocation)
      puts "====== Evaluating new allocation ======\n" +
           "stats: #{stats}\n" +
           # "per_workflow_and_customer_stats: #{per_workflow_and_customer_stats}\n" +
           "component_stats: #{per_component_stats}\n" +
           "allocation_map: #{allocation_map}\n" +
           "node_utilization: #{node_utilization}\n" +
           "costs: #{costs.round(2)} per day\n" +
           "=======================================\n"

      # gather information of how many pods are running for each label in each node per cluster
      bmap = {}
      @services.each do |k, s|
        current_spreading = []
        @cluster_repository.each do |_, c|
          pods_number = 0
          c.nodes.values.each do |n|
            pods_number += s.pods[s.selector].count { |p| p.node.node_id == n.node_id }
          end
          current_spreading << pods_number
          if bmap.key?(k)
            bmap[k][c.name] = pods_number
          else
            bmap[k] = { c.name => pods_number }
          end
        end

        # replication_penalties += (current_spreading.count { |x| x > 0 } - 1) * REPLICATION_PENALTY if current_spreading.count { |x| x > 0 } > 1
        # this is to enforce availability. Distributed replicas at least in two different clusters
        # replication_penalties += 5 if current_spreading.count(0) > 1
        # @logger.info "Current spreading for #{k}: #{current_spreading} penalties: #{replication_penalties}"
        # else
        #  replication_penalties -= 10
        # end
      end

      puts "BMAP #{bmap}"

      # cluster_utilization = []
      # @cluster_repository.each do |_, c|
      #  total_cpu = c.node_number * c.node_resources_cpu.to_f
      #  total_mem = c.node_number * c.node_resources_memory.to_f
      #  used_cpu = 0
      #  used_mem = 0
      #  c.nodes.values.each do |n|
      #    used_cpu += n.requested_resources[:cpu]
      #    used_mem += n.requested_resources[:memory]
      #  end
      #  cpu_util = total_cpu > 0 ? used_cpu / total_cpu : 0.0
      #  mem_util = total_mem > 0 ? used_mem / total_mem : 0.0
      #  cluster_utilization << ((cpu_util + mem_util) / 2.0).round(2)
      # end

      # resource_gini = gini_coefficient(cluster_utilization).round(2)
      # @logger.info "Cluster utilization (cpu+mem): #{cluster_utilization} Gini coefficient: #{resource_gini}"

      replica_spreads = bmap.values.map do |cluster_counts|
        normalized_gini(cluster_counts.values)
      end

      @logger.info "Normalized replica spreads for microservices: #{replica_spreads.map { |s| s.round(2) }}"

      # print the spreading and related gini for each microservice (debug purpose)
      bmap.each do |ms, cluster_counts|
        raw_gini = gini_coefficient(cluster_counts.values).round(2)
        norm_gini = normalized_gini(cluster_counts.values).round(2)
        @logger.info "Replica spread for #{ms}: #{cluster_counts.values} raw Gini: #{raw_gini} normalized: #{norm_gini}"
      end

      replica_spreading = if replica_spreads.empty?
                            0.0
                          else
                            (replica_spreads.sum / replica_spreads.length.to_f).round(2)
                          end
      @logger.info "Replica spread normalized Gini (avg across microservices): #{replica_spreading}"

      global_cluster_distribution = Array.new(@cluster_repository.length, 0)
      bmap.each_value do |cluster_counts|
        cluster_counts.values.each_with_index do |pods, idx|
          global_cluster_distribution[idx] += pods
        end
      end

      global_cluster_spreading = if global_cluster_distribution.empty?
                                   0.0
                                 else
                                   normalized_gini(global_cluster_distribution).round(2)
                                 end
      @logger.info "Global cluster spreading normalized Gini: #{global_cluster_spreading} distribution: #{global_cluster_distribution}"

      puts '============================================================================='
      # Produce txt and JSON file with the bmap information
      File.open('final_allocation.txt', 'w') do |f|
        f.puts bmap
      end

      File.open('final_allocation.json', 'w') do |f|
        f.write(JSON.pretty_generate(bmap))
      end

      mean_ttr = stats.mean
      # weighted_sum = mean_ttr + normalize_objective(replication_penalties, 0,
      #                                              mean_ttr) + normalize_objective(saturation_penalties, 0, mean_ttr)
      weighted_sum = mean_ttr + # normalize_objective(resource_gini, 0, mean_ttr) +
                     normalize_objective(replica_spreading, 0, mean_ttr) +
                     normalize_objective(saturation_penalties, 0, mean_ttr)

      per_component_stats.each do |k, v|
        # misconfiguration from TOSCA
        next if v.closed == 0

        # begin
        @logger.debug "Calculating stats for #{k} - #{v}"
        # rescue StandardError => e
        # @logger.error "#{e.backtrace.join}"
        # @logger.debug 'Proceed anyway'
        # next
        # end
        not_closed_penalty = 0
        not_closed_penalty + v.longer_than.inject(0.0) do |sum, (_key, value)|
          # puts "Component: #{k} Longer than #{key} ms: #{value} closed: #{v.closed}"
          next if v.closed.nil? || v.closed.nil?

          sum + (value / v.closed.to_f) if v.closed.to_f > 0
          # sum + (value / v.closed.to_f) * @configuration.custom_stats.find { |x| x[:name] == key }[:weight]
        end
        weighted_sum += normalize_objective(not_closed_penalty, 0, mean_ttr)
      end

      # Let's do the same for the workflow and customer stats
      @logger.info 'Calculating chain and customer stats'
      per_chain_and_customer_stats.each do |wft_id, cust_stats|
        @logger.info "  Workflow Type: #{wft_id}"
        cust_stats.each do |c_id, stats_wc|
          # @logger.debug "Looking for #{wft_id} #{c_id}"
          next if stats_wc.closed.zero?

          chain_penalty = 0
          # @logger.debug "Calculating stats for workflow type #{wft_id} customer #{c_id} - #{per_workflow_and_customer_stats[wft_id][c_id]}"
          chain_penalty += stats_wc.longer_than.inject(0.0) do |sum, (key, value)|
            @logger.info "Workflow Type: #{wft_id} Customer: #{c_id} Longer than #{key} s: #{value} closed: #{per_workflow_and_customer_stats[wft_id][c_id].closed} TTR: #{stats_wc.mean}"
            # next if per_workflow_and_customer_stats[wft_id][c_id].closed.nil? || per_workflow_and_customer_stats[wft_id][c_id].closed.nil?
            penalty_value = stats_wc.closed.to_f > 0 ? (value / stats_wc.closed.to_f) * 10 : 0
            @logger.info "penalty value: #{penalty_value}"
            sum + penalty_value
            # sum + (value / per_workflow_and_customer_stats[wft_id][c_id].closed.to_f) * @configuration.custom_stats.find { |x| x[:name] == key }[:weight]
          end
          weighted_sum += normalize_objective(chain_penalty, 0, mean_ttr)
        end
      end

      ## Add the availability policy
      if availability_policy
        closed_percentage = (stats.closed.to_f / stats.received.to_f) # We scale penalty to 10 factor
        availability_penalty = closed_percentage < availability_policy ? (closed_percentage - availability_policy) * 10 : 0
        puts "Availability penalty: #{availability_penalty} closed_percentage: #{closed_percentage} availability"
        weighted_sum += normalize_objective(availability_penalty, 0, mean_ttr)
      end
      puts "Weighted sum: #{weighted_sum}"
      # Store multiobjective metrics for external access
      @last_mean_ttr = mean_ttr
      @last_replica_spreading = replica_spreading
      @last_global_cluster_spreading = global_cluster_spreading
      @last_bmap = Marshal.load(Marshal.dump(bmap)) # Deep copy of bmap for external access
      -weighted_sum
    end

    # Returns multiobjective metrics as a hash without weighted aggregation.
    # This is used for NSGA-II and multiobjective optimization.
    # Takes the same parameters as evaluate_allocation.
    def evaluate_allocation_multiobjective(rss = nil, css = nil, mtt = nil, lm = nil, mapping = nil,
                                           replicas_mapping = nil)
      # Call the full evaluation to compute all metrics
      evaluate_allocation(rss, css, mtt, lm, mapping, replicas_mapping)

      # Return the raw multiobjective metrics (stored by evaluate_allocation)
      {
        mean_ttr: @last_mean_ttr,
        replica_spreading: @last_replica_spreading,
        global_cluster_spreading: @last_global_cluster_spreading,
        bmap: @last_bmap
      }
    end

    # Compute gini coefficient
    def gini_coefficient(values)
      n = values.length
      return 0.0 if n <= 1

      total = values.sum.to_f
      return 0.0 if total.zero?

      abs_diff_sum = 0.0
      values.each do |x|
        values.each do |y|
          abs_diff_sum += (x - y).abs
        end
      end
      abs_diff_sum / (2 * n * total)
    end

    # Compute the theoretical minimum Gini coefficient for r items distributed
    # across c bins as uniformly as possible.
    # With r replicas and c clusters, the best distribution is:
    #   (c - r % c) bins with floor(r/c) items and (r % c) bins with ceil(r/c) items.
    def min_gini_coefficient(r, c)
      return 0.0 if c <= 1 || r <= 0

      # Build the optimal distribution and compute its Gini
      base = r / c
      remainder = r % c
      optimal = Array.new(c - remainder, base) + Array.new(remainder, base + 1)
      gini_coefficient(optimal)
    end

    # Compute the theoretical maximum Gini coefficient for r items distributed
    # across c bins, which is when all items are in one bin and the rest are empty.
    def max_gini_coefficient(r, c)
      return 0.0 if c <= 1 || r <= 0

      # One bin has all items, the rest are empty
      gini_coefficient([r] + Array.new(c - 1, 0))
    end

    # Gini normalized by its theoretical minimum so that:
    #   0.0 = best possible spreading for the given (replicas, clusters)
    #   1.0 = worst possible spreading
    # This removes the structural bias against low replica counts.
    def normalized_gini(values)
      raw = gini_coefficient(values)
      r = values.sum
      c = values.length
      g_min = min_gini_coefficient(r, c)
      g_max = max_gini_coefficient(r, c)

      return 0.0 if (g_max - g_min).abs < 1e-9

      (raw - g_min) / (g_max - g_min)
    end

    def normalize_objective(value, min_obj, max_obj)
      (value - min_obj) / (max_obj - min_obj)
    rescue StandardError
      1.0
    end
  end
end
