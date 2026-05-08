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
                :workflow_type_id,
                :worked_step,
                :step_queue_time,
                :steps_ttr,
                :active_branches,
                :completed_branches,
                :parallel_context,
                :branch_results,
                :component_sequence,
                :branch_name,
                :parent_request,
                :child_kind,
                :nested_call_context

    attr_accessor :arrival_at_container, :chain_entering_time

    # the data_center_id attribute is updated as requests move from a Cloud
    # data center to another
    attr_accessor :data_center_id

    def initialize(rid:,
                   generation_time:,
                   initial_data_center_id:,
                   arrival_time:,
                   workflow_type_id:,
                   customer_id:,
                   component_sequence: nil,
                   branch_name: nil,
                   parent_request: nil,
                   child_kind: nil)
      @rid              = rid
      @generation_time  = generation_time
      @data_center_id   = initial_data_center_id
      @arrival_time     = arrival_time
      @workflow_type_id = workflow_type_id
      @customer_id      = customer_id

      # steps start counting from zero
      @worked_step = 0
      @next_step = 0

      # calculate communication latency
      @communication_latency = @arrival_time - @generation_time

      # set this to arrival time, then change it
      @arrival_at_container = arrival_time
      @queuing_time = 0.0
      @working_time = 0.0
      @step_queue_time = 0.0
      @steps_ttr = []
      @chain_entering_time = nil
      @chain_exiting_time = nil

      # Parallel execution tracking
      @active_branches = []
      @completed_branches = []
      @parallel_context = nil
      @branch_results = {}
      @component_sequence = component_sequence
      @branch_name = branch_name
      @parent_request = parent_request
      @child_kind = child_kind
      @nested_call_context = nil
      @completed_call_steps = {}
    end

    def update_queuing_time(duration)
      @queuing_time += duration
      @step_queue_time = duration
    end

    def update_transfer_time(duration)
      @communication_latency += duration
    end

    def step_completed(duration)
      @working_time += duration
      @worked_step = @next_step
      @next_step += 1
    end

    def chain_entered(time)
      @chain_entering_time = time
    end

    def finished_processing(time)
      # save closure time
      @closure_time = time
    end

    def finished_chain(time)
      @chain_exiting_time = time
    end

    def closed?
      !@closure_time.nil?
    end

    def ttr(time)
      # if incident isn't closed yet, just return nil without raising an exception.
      base_ttr = @closure_time.nil? ? (time - @arrival_at_container) : (@closure_time - @arrival_time)
      
      # For requests with completed branches, include maximum branch completion time
      if @completed_branches && !@completed_branches.empty?
        max_branch_time = @completed_branches.map { |branch| 
          branch[:completed_at] ? (branch[:completed_at].to_f - @arrival_time.to_f) : 0 
        }.max
        # Return the maximum between base TTR and branch completion times
        [base_ttr, max_branch_time].max
      else
        base_ttr
      end
    end

    def ttr_chain(time)
      (@chain_exiting_time || time) - @chain_entering_time
    end

    def ttr_step(time)
      ts = time - @arrival_at_container
      @steps_ttr << ts # unless @steps_ttr.include? ts
      ts
    end

    # Parallel execution management methods
    def start_parallel_execution(branches)
      @parallel_context = {
        branch_count: branches.size,
        started_at: Time.now,
        parent_step: @next_step
      }
      @active_branches = branches.map { |branch| { name: branch[:name], status: "running", started_at: Time.now } }
      @branch_results = {}
    end

    def complete_branch(branch_name, result_data = nil, completion_time = nil)
      branch = @active_branches.find { |b| b[:name] == branch_name }
      if branch
        branch[:status] = "completed"
        branch[:completed_at] = completion_time || Time.now
        @branch_results[branch_name] = result_data
        @completed_branches << { name: branch_name, data: result_data, completed_at: completion_time || Time.now }
      end
    end

    def all_branches_completed?(required_branches = nil)
      if required_branches.nil?
        @active_branches.all? { |branch| branch[:status] == "completed" }
      else
        required_branches.all? { |branch_name| @branch_results.key?(branch_name) }
      end
    end

    def get_completed_branch_names
      @branch_results.keys
    end

    def start_nested_calls(calls, container, sequence_key)
      @nested_call_context = {
        pending_calls: Marshal.load(Marshal.dump(calls)),
        waiting_container: container,
        sequence_key: sequence_key
      }
    end

    def nested_calls_active?
      !@nested_call_context.nil?
    end

    def next_nested_call
      return nil unless @nested_call_context

      @nested_call_context[:pending_calls].shift
    end

    def nested_calls_remaining?
      @nested_call_context && !@nested_call_context[:pending_calls].empty?
    end

    def nested_waiting_container
      @nested_call_context && @nested_call_context[:waiting_container]
    end

    def finish_nested_calls
      return nil unless @nested_call_context

      waiting_container = @nested_call_context[:waiting_container]
      mark_calls_completed(@nested_call_context[:sequence_key])
      @nested_call_context = nil
      waiting_container
    end

    def calls_completed?(sequence_key)
      @completed_call_steps[sequence_key]
    end

    def mark_calls_completed(sequence_key)
      @completed_call_steps[sequence_key] = true
    end

    def clone_for_parallel_branch(branch)
      branch_sequence = branch[:component_sequence] || [{ name: branch[:name] }]
      branch_name = branch[:name] || branch_sequence.first[:name]

      # Create a new request for parallel branch execution
      cloned = self.class.new(
        rid: "#{@rid}-#{branch_name}",
        generation_time: @generation_time,
        initial_data_center_id: @data_center_id,
        arrival_time: @arrival_at_container,
        workflow_type_id: @workflow_type_id,
        customer_id: @customer_id,
        component_sequence: Marshal.load(Marshal.dump(branch_sequence)),
        branch_name: branch_name,
        parent_request: self,
        child_kind: :parallel_branch
      )

      # Initialize parallel tracking for branch
      cloned.instance_variable_set(:@active_branches, [])
      cloned.instance_variable_set(:@completed_branches, [])
      cloned.instance_variable_set(:@parallel_context, nil)
      cloned.instance_variable_set(:@branch_results, {})

      cloned
    end

    def clone_for_nested_call(call)
      call_sequence = call[:component_sequence] || [{ name: call[:name] }]
      call_name = call[:name] || call_sequence.first[:name]

      cloned = self.class.new(
        rid: "#{@rid}-#{call_name}",
        generation_time: @generation_time,
        initial_data_center_id: @data_center_id,
        arrival_time: @arrival_at_container,
        workflow_type_id: @workflow_type_id,
        customer_id: @customer_id,
        component_sequence: Marshal.load(Marshal.dump(call_sequence)),
        branch_name: call_name,
        parent_request: self,
        child_kind: :nested_call
      )

      cloned.instance_variable_set(:@active_branches, [])
      cloned.instance_variable_set(:@completed_branches, [])
      cloned.instance_variable_set(:@parallel_context, nil)
      cloned.instance_variable_set(:@branch_results, {})

      cloned
    end

    def is_parallel_branch?
      @child_kind == :parallel_branch
    end

    def is_nested_call?
      @child_kind == :nested_call
    end

    def to_s
      "rid: #{@rid}, generation_time: #{@generation_time}, data_center_id: #{@data_center_id}, arrival_time: #{@arrival_time}, queuing_time #{@queuing_time}, branches: #{@active_branches.size}, completed_branches: #{@completed_branches.size}"
    end
  end
end
