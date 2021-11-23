# frozen_string_literal: true

module KUBETWIN
  class Request

    # # states
    # STATE_WORKING   = 1
    # STATE_SUSPENDED = 2

    attr_reader :rid,
                :arrival_time,
                :closure_time,
                # :communication_latency,
                :customer_id,
                :generation_time,
                :next_step,
                # :status,
                :queuing_time,
                :workflow_type_id

    # the data_center_id attribute is updated as requests move from a Cloud
    # data center to another
    attr_accessor :data_center_id

    def initialize(rid:,
                   generation_time:,
                   initial_data_center_id:,
                   arrival_time:,
                   workflow_type_id:,
                   customer_id:)
      @rid              = rid
      @generation_time  = generation_time
      @data_center_id   = initial_data_center_id
      @arrival_time     = arrival_time
      @workflow_type_id = workflow_type_id
      @customer_id      = customer_id

      # steps start counting from zero
      @next_step = 0

      # calculate communication latency
      @communication_latency = @arrival_time - @generation_time

      @queuing_time = 0.0
      @working_time = 0.0
    end

    def update_queuing_time(duration)
      @queuing_time += duration
    end

    def update_transfer_time(duration)
      @communication_latency += duration
    end

    def step_completed(duration)
      @working_time += duration
      @next_step += 1
    end

    def finished_processing(time)
      # save closure time
      @closure_time = time
    end

    def closed?
      !@closure_time.nil?
    end

    def ttr
      # if incident isn't closed yet, just return nil without raising an exception.
      @closure_time.nil? ? nil : (@closure_time - @arrival_time)
    end

    def to_s
      "rid: #{@rid}, generation_time: #{@generation_time}, data_center_id: #{@data_center_id}, arrival_time: #{@arrival_time}, queuing_time #{@queuing_time}"
    end
  end

end
