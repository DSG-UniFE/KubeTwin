# frozen_string_literal: true

module KUBETWIN

  class Event

    ET_REQUEST_GENERATION      = 0
    ET_REQUEST_ARRIVAL         = 1
    ET_REQUEST_FORWARDING      = 2
    ET_WORKFLOW_STEP_COMPLETED = 3
    ET_REQUEST_CLOSURE         = 4
    ET_HPA_CONTROL             = 5
    ET_STATS_PRINT             = 6
    ET_NODE_CONTROL            = 7
    ET_SHUTDOWN_NODE           = 8
    #ET_ALLOCATE_NODE           = 7
    ET_DEALLOCATE_NODE         = 9
    ET_EVICT_POD               = 10
    #ET_PASSING_WAIT            = 9
    # ET_VM_SUSPEND              = 5
    # ET_VM_RESUME               = 6
    ET_END_OF_SIMULATION       = 100

    # let the comparable mixin provide the < and > operators for us
    include Comparable

    # should this be attr_accessor instead?
    attr_reader :type, :data, :time, :destination

    def initialize(type, data, time, destination)
      @type        = type
      @data        = data
      @time        = time
      @destination = destination
    end

    def <=>(event)
      @time <=> event.time
    end

    def to_s
      "Event type: #{@type}, data: #{@data}, time: #{@time}, #{@destination}"
    end

  end

end
