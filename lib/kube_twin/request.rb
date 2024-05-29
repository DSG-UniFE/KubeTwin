# frozen_string_literal: true

module KUBETWIN
  class Request

    # # states
    # STATE_WORKING   = 1
    # STATE_SUSPENDED = 2

    attr_reader :rid,
                :arrival_time,
                :closure_time,
                :customer_id,
                :generation_time,
                :next_step,
                :queuing_time,
                :workflow_type_id,
                :worked_step,
                :step_queue_time,
                :steps_ttr

    attr_accessor :arrival_at_container,
                  :data_center_id,
                  :component,
                  :next_component
    # the data_center_id attribute is updated as requests move from a Cloud
    # data center to another

    def initialize(rid:,
                   generation_time:,
                   initial_data_center_id:,
                   arrival_time:,
                   workflow_type_id:,
                   customer_id:,
                   component:)
      @rid              = rid
      @generation_time  = generation_time
      @data_center_id   = initial_data_center_id
      @arrival_time     = arrival_time
      @workflow_type_id = workflow_type_id
      @customer_id      = customer_id
      @component        = component
      @next_component   = nil

      # steps start counting from zero
      @worked_step = 0
      # for multi-step requests, this is the next step to be executed
      @step_count = 0
      @next_step = 0

      # calculate communication latency
      @communication_latency = @arrival_time - @generation_time

      # set this to arrival time, then change it
      @arrival_at_container = arrival_time
      @queuing_time = 0.0
      @working_time = 0.0
      @step_queue_time = 0.0
      @steps_ttr = []
    end

    def update_queuing_time(duration)
      @queuing_time += duration
      @step_queue_time = duration
    end

    def update_transfer_time(duration)
      @communication_latency += duration
    end

    def step_completed(duration)
      @step_count += 1
      @working_time += duration
      @worked_step = @next_step
      @next_step += 1
    end

    def finished_processing(time)
      # save closure time
      @closure_time = time
    end

    def closed?
      !@closure_time.nil?
    end

    def ttr(time)
      # if incident isn't closed yet, just return nil without raising an exception.
      @closure_time.nil? ? (time - @arrival_at_container) : (@closure_time - @arrival_time)
    end

    def ttr_step(time, step_name)
      ts = time - @arrival_at_container
      puts "TTR Step: #{step_name} - #{ts}"
      @steps_ttr << ts # unless @steps_ttr.include? ts
      ts
    end

    def to_s
      "rid: #{@rid}, generation_time: #{@generation_time}, data_center_id: #{@data_center_id}, arrival_time: #{@arrival_time}, queuing_time #{@queuing_time}"
    end
  end

end
