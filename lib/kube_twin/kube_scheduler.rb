module KUBETWIN

  # the scheduler selects the nodes where to allocate pods
  class KubeScheduler

    # this class is inspired by the concepts described in here
    # here we ned a reference to the cluster
    def initialize(clusters)
      @clusters = clusters
      @filtered_nodes = []
    end

    # information regarding requirements are available usin the pod class
    def get_node(resource_requirements, node_affinity)
      # get the requirements (we should specify at least a requirement here,
      # CPU percentage)
      # filter available nodes
      # this should return a candidate node
      filter_and_score(resource_requirements, node_affinity)
    end

    private
    # then we need to implement
    # 1) filtering (a lot of policies that can be implemented in external classes
    #    or via a lambda function)
    # 2) scoring the nodes where to allocate the pods
    # when do we need to run these procedures?
    
    # do we need to call filter every time we need to assign a pod?
    # maybe we do
    def filter_and_score(requirements, node_affinity)
      filter(requirements)
      score(node_affinity)
    end

    # filtering here is an expensive operation
    def filter(requirements)
     # reset filtered nodes --- do we need to call delete here?
     @filtered_nodes = [] 
      # here we could implement different policies
      #puts "Clusters: #{@clusters}"
      @clusters.values.each do |c|
        raise "Ranking nodes from a nil cluster" if c.nil?
        c.nodes.values.each do |node|
          # debug node information here
          # filter only those nodes capable to execute the pods
          available_resources_cpu = node.available_resources_cpu
          @filtered_nodes << {node: node, cluster_id: c.cluster_id,
                             tier: c.tier,
                             price: c.fixed_hourly_cost_cpu,
                             available_resources_cpu: available_resources_cpu,
                             requested_resources: node.requested_resources[:cpu],
                             deployed_pods: node.pod_id_list.length} if available_resources_cpu >= requirements
        end
      end
    end

    # the following is a simple implementation that returns 
    # just the node
    def score(node_affinity)
      # here we need to implement something complex using external or specific classes
      # sorting operations are computionally heavy
      # implementing a sorting algorithm here
      # {|n| (n[requested_resources] + n[:deployed_pods])}

      if @filtered_nodes.empty?
        puts "Resource saturation"
        return nil
      end
      node = nil
      # check also for node affinity here
      unless node_affinity.nil?
        node_with_affinity = @filtered_nodes.select{|n| n[:tier] == node_affinity}
        
        if node_with_affinity.empty?
          node = nil
        else
          node = node_with_affinity.sort_by { |n| -n[:available_resources_cpu] }[0][:node]
        end
      end

      # distribute the application load among clusters
      # available_resources_cpu prefers powerful nodes
      # select mec first
      if node.nil?
        #node = @filtered_nodes.sort_by { |n| -n[:available_resources_cpu] }[0][:node]
        #puts "#{@filtered_nodes.sort_by { |n| n[:price] }}"
        #abort
        node = @filtered_nodes.sort_by { |n| n[:price] }[0][:node]
      end
      return node
    end

  end
end