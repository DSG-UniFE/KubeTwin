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
    def get_node(pod)
      # get the requirements (we should specify at least a requirement here,
      # CPU percentage)
      reqs = pod.requirements
      # filter available nodes
      # this should return a candidate node
      filter_and_score(reqs)
    end

    private
    # then we need to implement
    # 1) filtering (a lot of policies that can be implemented in external classes
    #    or via a lambda function)
    # 2) scoring the nodes where to allocate the pods
    # when do we need to run these procedures?
    
    # do we need to call filter every time we need to assign a pod?
    # maybe we do
    def filter_and_score(requirements)
      filter(requirements)
      score
    end

    def filter(requirements)
     # reset filtered nodes --- do we need to call delete here?
     @filtered_nodes = [] 
      # here we could implement different policies
      @clusters.each do |k, c|
        @c.nodes do |node|
          # debug node information here
          # filter only those nodes capable to execute the pods
          available_resources = node.available_resources
          @filtered_nodes << {node_id: node.node_id, cluster_id: c.cluster_id, 
             available_resources: available_resources,
             deployed_pods: node.pode_id_list.length} if available_resources >= requirements
        end
      end
    end

    # the following is a simple implementation that returns 
    # just the node
    def score
      # here we need to implement something complex using external or specific classes
      # sorting operations are computionally heavy
      @filtered_nodes.sort_by {|n| n.available_resources}[0]
    end

  end
end