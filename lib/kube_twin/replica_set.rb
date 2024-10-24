# frozen_string_literal: true

require_relative './pod'

module KUBETWIN
  # just a simple class to model a ReplicaSet
  # selector is the label corrisponding to
  # the pod name
  # setReplica allows to change the number of
  # replica
  # the control loop will be implemented within
  # the simulation's code

  class ReplicaSet
    attr_reader :name,
                :selector,
                :replicas,
                :service

    # name and selector have the same value here
    # the replica set creates the pods, which are 
    # associate to a service that provides naming,
    # discovery, and lookup capabilities
    def initialize(name, selector, replicas, service)
      @name = name
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
    def set_replicas(replicas)
      @replicas = replicas
    end
    
  end
end
