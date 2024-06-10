# frozen_string_literal: true

require_relative './container'

module KUBETWIN
  class Pod
    # states
    POD_PENDING         = 0     # The Pod has been accepted by the Kubernetes cluster, but one or more of the containers has not been set up and made ready to run
    POD_RUNNING         = 0     # At least one container is still running, or is in the process of starting or restarting.
    POD_SUCCEEDED       = 0     # All containers in the Pod have terminated in success, and will not be restarted.
    POD_FAILED          = 0     # All containers in the Pod have terminated, and at least one container has terminated in failure

    # commenting podIP info for now :podIp
    attr_reader :pod_id, :podName, :node, :label,
     :container, :requirements

    # here fix it
    # instead of nodeIP we could use a nodeID
    # pod name could not be important
    def initialize(pod_id, podName, node, label, image_info)
      @pod_id = pod_id
      @podName = podName
      @node = node
      
      @node_affinity = image_info[:node_affinity].nil? ? nil : image_info[:node_affinity]

      @container = Container.new(pod_id, 1, image_info[:service_time_distribution][node.type],
                        {blocking: image_info[:blocking], node: @node, label: label, img_info: image_info})
                        
       # image_info[:blocking]) #, opts[:port]) # @containers = {}
      # startup the container here -- we just need a MVP for now
      @container.startupC
      @startTime = Time.now
      @status = Pod::POD_PENDING
      @label = label
      @requirements = {cpu: image_info[:resources_requirements_cpu], memory: image_info[:resources_requirements_memory]}
      # @namespace      = "default"
      # priority       = 0
    end

    def startUpPod
      @container.startupC
      # here commented to speed-up the simulation
      # it is working 
      # raise 'Setup container error' if @container.state != Container::CONTAINER_RUNNING

      @status = Pod::POD_RUNNING
      # "Pod started successfully"
    end

    def deactivate_pod
      @status = Pod::POD_PENDING
      # then container will continue processing queued requests
      @node.remove_resources(self, @requirements[:cpu], @requirements[:memory])
    end

    def endPod
      if (@container.state == Container::CONTAINER_TERMINATED) && (@container.endCode == 0)
        @status == Pod::POD_SUCCEEDED
      end
      if (@container.state == Container::CONTAINER_TERMINATED) && (@container.endCode == 1)
        @status == Pod::POD_FAILED
      end
    end

    # TODO refactor this method to remove unused fields
    #def describePod(_pod)
    #  "Name: #{@podName} \nIP: #{@pod_id} \nNode IP: #{@nodeIp} \nStart Time: #{@startTime} \nStatus: #{@status} \nContainers: \n\tContainer ID: #{@container.containerId} \n\tImage ID: #{@container.imageId} \n\tPort: #{@container.port} \n\tLimits: \n\t\tcpu: #{@container.limits.cpu} \n\t\tmemory: #{@container.limits.memory} \n\tRequests: \n\t\tcpu: #{@container.guaranteed.cpu} \n\t\tmemory: #{@container.guaranteed.memory}"
    #end

    # Pod running if at least one of its primary containers starts OK
    # def check_containers
    #    @containers.each do |i|
    #        raise "Pod cannot be ready, container #{i} has some problems or is waiting" if i.state != Container::CONTAINER_RUNNING
    #    end
    #    @status = Pod::POD_RUNNING
    # end

    # def add_container(container, service_name)
    #    @containers[service_name] ||= []

    #    @containers[service_name] << container
    #    @containers.size += 1
    #    raise 'Error! Pod full!' if @containers.size == 2

    #    container.startupC
    # end
  end
end
