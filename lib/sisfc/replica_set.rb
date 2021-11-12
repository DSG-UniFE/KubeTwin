# frozen_string_literal: true

require './pod'

module SISFC
  # just a simple class to model a ReplicaSet
  # selector is the label corrisponding to
  # the pod name
  # setReplica allows to change the number of
  # replica
  # the control loop will be implemented within
  # the simulation's code

  class ReplicaSet
    attr_reader :name, :selector, :replicas, :node_id

    # name and selector have the same value here
    def initialize(name, node_id, selector, replicas)
      @name = name
      @node_id = node_id
      @selector = selector
      @replicas = replicas
    end

    # change the number of replicas
    # this method could generate a
    # new event that will activate or deactivate pod
    def setReplicas(replicas)
      @replicas = replicas
    end
  end
end
