# frozen_string_literal: true

require './pod'

module KUBETWIN
  # just a simple class to model a ReplicaSet
  # selector is the label corrisponding to
  # the pod name
  # setReplica allows to change the number of
  # replica
  # the control loop will be implemented within
  # the simulation's code

  class ReplicaSet
    attr_reader :name, :selector, :replicas, :cluster_id

    # name and selector have the same value here
    # the replica set creates the pods, which are 
    # associate to a service that provides naming,
    # discovery, and lookup capabilities
    def initialize(name, cluster_id, selector, replicas, service)
      @name = name
      @cluster_id = cluster_id
      @selector = selector
      @replicas = replicas
      # do we need to keep a reference to the service
      # class?
      @service = service
      # optional parameter to set the control loop?
    end

    # change the number of replicas
    # this method could generate a
    # new event that will activate or deactivate pod
    def setReplicas(replicas)
      @replicas = replicas
    end
    
  end
end
