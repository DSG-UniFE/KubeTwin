
require './container'

module SISFC

    class Pod

        #states
        POD_PENDING         = 0     #The Pod has been accepted by the Kubernetes cluster, but one or more of the containers has not been set up and made ready to run
        POD_RUNNING         = 0     #At least one container is still running, or is in the process of starting or restarting.
        POD_SUCCEEDED       = 0     #All containers in the Pod have terminated in success, and will not be restarted.
        POD_FAILED          = 0     #All containers in the Pod have terminated, and at least one container has terminated in failure

        attr_reader :podId, :podName, :podIp, :node

        # here fix it
        def initialize(podId, podName, podIp, nodeIp, label)
            @podId          = podId
            @podName        = podName
            @podIp          = podIp
            @node           = nodeIp
            @container      = Container.new(0, 1, opts[:port])       #@containers = {}
            @startTime      = Time.now
            @status         = Pod::POD_PENDING
            @label          = label
            
            #@namespace      = "default"
            #priority       = 0 
        end


        def startUpPod
            @container.startupC
            raise "Setup container error" if @container.state != Container::CONTAINER_RUNNING

            @status = Pod::POD_RUNNING
            #"Pod started successfully"
        end


        def endPod
            if @container.state == Container::CONTAINER_TERMINATED and @container.endCode == 0
                @status == Pod::POD_SUCCEEDED
            end
            if @container.state == Container::CONTAINER_TERMINATED and @container.endCode == 1
                @status == Pod::POD_FAILED
            end
        end

        def describePod (pod)
            "Name: #{@podName} \nIP: #{@podIp} \nNode IP: #{@nodeIp} \nStart Time: #{@startTime} \nStatus: #{@status} \nContainers: \n\tContainer ID: #{@container.containerId} \n\tImage ID: #{@container.imageId} \n\tPort: #{@container.port} \n\tLimits: \n\t\tcpu: #{@container.limits.cpu} \n\t\tmemory: #{@container.limits.memory} \n\tRequests: \n\t\tcpu: #{@container.guaranteed.cpu} \n\t\tmemory: #{@container.guaranteed.memory}" 
        end


        #Pod running if at least one of its primary containers starts OK
        #def check_containers
        #    @containers.each do |i|
        #        raise "Pod cannot be ready, container #{i} has some problems or is waiting" if i.state != Container::CONTAINER_RUNNING
        #    end
        #    @status = Pod::POD_RUNNING
        #end


        #def add_container(container, service_name)
        #    @containers[service_name] ||= []

        #    @containers[service_name] << container
        #    @containers.size += 1
        #    raise 'Error! Pod full!' if @containers.size == 2

        #    container.startupC
        #end



    end

end