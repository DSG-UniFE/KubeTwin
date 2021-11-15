# frozen_string_literal: true

require_relative './cluster'
require_relative './replica_set'
require_relative './service'
require_relative './event'
require_relative './generator'
require_relative './sorted_array'
require_relative './statistics'
require_relative './pod'
require_relative './latency_manager'
require_relative './kube_dns'


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

# we do not have data center for now
# configure cluster here? or something similar
# need to check

      # create data centers and store them in a repository
      cluster_repository = Hash[
        @configuration.clusters.map do |k,v|
          [ k, Cluster.new(id: k, **v) ]
        end
      ]

      customer_repository = @configuration.customers
      workflow_type_repository = @configuration.workflow_types


# commented stat initialization... it should work anayway
# here we would need different statistics

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

      # Initialize Kubernetes objects

      @kube_dns = KubeDns.new


      @replica_sets = {}
      # first create the replica_set
      @configuration.replica_sets.each do |name, conf|
        # nil is service here
        # do we need a reference to service in ReplicaSet?
        @replica_sets[name] = ReplicaSet.new(name, conf[:cluster_id],
                    conf[:selector], conf[:replicas], nil)
      end

      puts @replica_sets

      # Replica Sets created here, ... then create pod and services .. we can follow
      # or different events to create pods

      @services = {}

      # we could use a repository here
      # dry could be very useful in here...
      @configuration.services.each do |k, conf|
        @services[k] = Service.new(k, conf[:selector])
        # need to register this service into kube_dns
        @kube_dns.registerService(@services[k])
      end

      # dup here?
      @service_component_types = @configuration.service_component_types

      #puts "List of available Services #{@services}"

      pod_id = 0
      @replica_sets.each do |k, rs|
        # here we need to create pods and register them into a Service
        rs.replicas.times do
          selector = rs.selector
          # the nil fields is a node related information
          # get image info --> service component type (sct)
          # sct has info regarding service execution time
          sct = @service_component_types[selector][:service_time_distribution]
          pod = Pod.new(pod_id, "#{selector}_#{pod_id}", nil, selector, sct)
          # get the service here and assign the pod to the service
          # convert string to sym
          s = @services[selector]
          s.assignPod(pod)
          pod_id += 1
        end
      end

      # debug printing here 
      # select a random pod using a service
      # pod lookup is done by a service
      @services.each {|_, v| puts v.get_random_pod(v.selector)}

      # testing DNS functionalities

      # puts "Testing DNS"
      #puts "Looking up #{@kube_dns.lookup('Web Server')}"
     
      # working here
      # aborting
      abort

      # create event queue
      @event_queue = SortedArray.new

      # puts "========== Simulation Start =========="

      # generate first request
      rg = RequestGenerator.new(@configuration.request_generation)
      req_attrs = rg.generate
      new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)

      # schedule end of simulation
      unless @configuration.end_time.nil?
        # puts "Simulation ends at: #{@configuration.end_time}"
        new_event(Event::ET_END_OF_SIMULATION, nil, @configuration.end_time, nil)
      end

      # calculate warmup threshold
      warmup_threshold = @configuration.start_time + @configuration.warmup_duration.to_i

      requests_being_worked_on = 0
      requests_forwarded_to_other_dcs = 0
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

            # find closest data center
            customer_location_id = customer_repository.dig(req_attrs[:customer_id], :location_id)
            dc_at_customer_location = cluster_repository.values.find {|dc| dc.location_id == customer_location_id }

            raise "No data center found at location id #{customer_location_id}!" unless dc_at_customer_location

            # find first component name for requested workflow
            workflow = workflow_type_repository[req_attrs[:workflow_type_id]]
            first_component_name = workflow[:component_sequence][0][:name]

            closest_dc = if dc_at_customer_location.has_vms_of_type?(first_component_name)
              dc_at_customer_location
            else
              cluster_repository.values.select{|dc| dc.has_vms_of_type?(first_component_name) }&.sample
            end

            raise "Invalid configuration! No VMs of type #{first_component_name} found!" unless closest_dc

            arrival_time = @current_time + latency_manager.sample_latency_between(customer_location_id, closest_dc.location_id)
            new_req = Request.new(req_attrs.merge!(initial_data_center_id: closest_dc.dcid,
                                                   arrival_time: arrival_time))

            # schedule arrival of current request
            new_event(Event::ET_REQUEST_ARRIVAL, new_req, arrival_time, nil)

            # schedule generation of next request
            req_attrs = rg.generate
            new_event(Event::ET_REQUEST_GENERATION, req_attrs, req_attrs[:generation_time], nil)

          when Event::ET_REQUEST_ARRIVAL
            # get request
            req = e.data

            # find data center
            cluster = cluster_repository[req.data_center_id]

            # update reqs_received_per_workflow_and_customer
            reqs_received_per_workflow_and_customer[req.workflow_type_id][req.customer_id] += 1

            # find next component name
            workflow = workflow_type_repository[req.workflow_type_id]
            next_component_name = workflow[:component_sequence][req.next_step][:name]

            # get random vm providing next service component type
            vm = cluster.get_random_vm(next_component_name, random: next_component_rng)

            # schedule request forwarding to vm
            new_event(Event::ET_REQUEST_FORWARDING, req, e.time, vm)

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
            req  = e.data
            time = e.time
            vm   = e.destination

            vm.new_request(self, req, time)


          when Event::ET_WORKFLOW_STEP_COMPLETED
            # retrieve request and vm
            req = e.data
            vm  = e.destination

            # tell the old vm that it can start processing another request
            vm.request_finished(self, e.time)

            # find data center and workflow
            cluster = cluster_repository[req.data_center_id]
            workflow    = workflow_type_repository[req.workflow_type_id]

            # check if there are other steps left to complete the workflow
            if req.next_step < workflow[:component_sequence].size
              # find next component name
              next_component_name = workflow[:component_sequence][req.next_step][:name]

              # get random VM providing next service component type
              new_vm = cluster.get_random_vm(next_component_name, random: next_component_rng)

              # this is the request's time of arrival at the new VM
              forwarding_time = e.time

              # there might not be a VM of the type we need in the current data
              # center, so look in the other data centers
              unless new_vm
                # get list of other data centers, randomly picked
                other_dcs = cluster_repository.values.
                  select{|x| x != cluster && x.has_vms_of_type?(next_component_name) }&.
                  shuffle(random: next_component_rng)
                other_dcs.each do |dc|
                  new_vm = dc.get_random_vm(next_component_name, random: next_component_rng)
                  if new_vm
                    # need to update data_center_id of request
                    req.data_center_id = dc.dcid

                    # keep track of transmission time
                    transmission_time =
                      latency_manager.sample_latency_between(cluster.location_id,
                                                             dc.location_id)

                    unless transmission_time >= 0.0
                      raise "Negative transmission time (#{transmission_time})!"
                    end

                    req.update_transfer_time(transmission_time)
                    forwarding_time += transmission_time

                    # update request's current data_center_id
                    req.data_center_id = dc.dcid

                    # keep track of number of requests forwarded to other data centers
                    requests_forwarded_to_other_dcs += 1

                    # we're done here
                    break
                  end
                end
              end

              # make sure we actually found a VM
              raise "Cannot find VM running a component of type " +
                    "#{next_component_name} in any data center!" unless new_vm

              # schedule request forwarding to vm
              new_event(Event::ET_REQUEST_FORWARDING, req, forwarding_time, new_vm)

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


          when Event::ET_END_OF_SIMULATION
            # puts "#{e.time}: end simulation"
            break

        end
      end

      # puts "========== Simulation Finished =========="

      costs = @evaluator.evaluate_business_impact(stats, per_workflow_and_customer_stats,
                                                  vm_allocation)
      puts "====== Evaluating new allocation ======\n" +
           "costs: #{costs}\n" +
           "vm_allocation: #{vm_allocation.inspect}\n" +
           "stats: #{stats.to_s}\n" +
           "per_workflow_and_customer_stats: #{per_workflow_and_customer_stats.to_s}\n" +
           "=======================================\n"

      # we want to minimize the cost, so we define fitness as the opposite of
      # the sum of all costs incurred
      -costs.values.inject(0.0){|s,x| s += x }
    end

  end
end
