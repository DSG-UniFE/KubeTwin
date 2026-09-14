# frozen_string_literal: true

require "minitest_helper"

require_relative "reference_configuration"

describe KUBETWIN::Request do
  it "should create a valid request and expose the values it was built with" do
    rid = rand(100)
    generation_time = (Time.now - KUBETWIN::Timespan.hours(1)).to_f
    initial_data_center_id = rand(10)
    arrival_time = Time.now.to_f
    workflow_type_id = rand(4)
    customer_id = 0

    req = KUBETWIN::Request.new(rid:                    rid,
      generation_time:        generation_time,
      initial_data_center_id: initial_data_center_id,
      arrival_time:           arrival_time,
      workflow_type_id:       workflow_type_id,
      customer_id:            customer_id)

    _(req.rid).must_equal rid
    _(req.generation_time).must_equal generation_time
    _(req.data_center_id).must_equal initial_data_center_id
    _(req.arrival_time).must_equal arrival_time
    _(req.workflow_type_id).must_equal workflow_type_id
    _(req.customer_id).must_equal customer_id

    # freshly built requests haven't worked any step yet, and haven't queued
    _(req.worked_step).must_equal 0
    _(req.next_step).must_equal 0
    _(req.queuing_time).must_equal 0.0
  end

  it "should default optional chain/branch attributes to nil" do
    req = KUBETWIN::Request.new(rid:                    1,
      generation_time:        Time.now.to_f,
      initial_data_center_id: 0,
      arrival_time:           Time.now.to_f,
      workflow_type_id:       0,
      customer_id:            0)

    _(req.component_sequence).must_be_nil
    _(req.branch_name).must_be_nil
    _(req.parent_request).must_be_nil
    _(req.child_kind).must_be_nil
  end

  it "should accumulate queuing time across multiple waits" do
    req = KUBETWIN::Request.new(rid:                    1,
      generation_time:        Time.now.to_f,
      initial_data_center_id: 0,
      arrival_time:           Time.now.to_f,
      workflow_type_id:       0,
      customer_id:            0)

    req.update_queuing_time(1.5)
    req.update_queuing_time(2.5)

    _(req.queuing_time).must_equal 4.0
    # step_queue_time tracks only the most recent wait, not the running total
    _(req.step_queue_time).must_equal 2.5
  end

  it "should advance worked_step and next_step when a step completes" do
    req = KUBETWIN::Request.new(rid:                    1,
      generation_time:        Time.now.to_f,
      initial_data_center_id: 0,
      arrival_time:           Time.now.to_f,
      workflow_type_id:       0,
      customer_id:            0)

    req.step_completed(0.3)
    _(req.worked_step).must_equal 0
    _(req.next_step).must_equal 1

    req.step_completed(0.2)
    _(req.worked_step).must_equal 1
    _(req.next_step).must_equal 2
  end

  # #complete_parallel_branch bundles what used to be three separate steps
  # at its one call site (KSimulation's ET_WORKFLOW_STEP_COMPLETED handler,
  # completing a branch dispatched via #clone_for_parallel_branch): record
  # the branch as completed, decrement parallel_context[:branch_count],
  # and once every branch has reported in, clear parallel_context and say
  # so -- so the event loop no longer has to reach into parallel_context's
  # internal shape to drive it.
  describe "#complete_parallel_branch" do
    def build_request
      KUBETWIN::Request.new(rid:                    1,
        generation_time:        Time.now.to_f,
        initial_data_center_id: 0,
        arrival_time:           Time.now.to_f,
        workflow_type_id:       0,
        customer_id:            0)
    end

    it "returns false while branches remain outstanding, keeping parallel_context alive" do
      parent = build_request
      parent.start_parallel_execution([{name: "reviews"}, {name: "details"}])

      result = parent.complete_parallel_branch("reviews", "result-a", 10.0)

      _(result).must_equal false
      _(parent.parallel_context).wont_be_nil
      _(parent.parallel_context[:branch_count]).must_equal 1
      _(parent.branch_results["reviews"]).must_equal "result-a"
    end

    it "returns true and clears parallel_context once every branch has completed" do
      parent = build_request
      parent.start_parallel_execution([{name: "reviews"}, {name: "details"}])

      _(parent.complete_parallel_branch("reviews", "result-a", 10.0)).must_equal false
      result = parent.complete_parallel_branch("details", "result-b", 12.0)

      _(result).must_equal true
      _(parent.parallel_context).must_be_nil
      _(parent.branch_results).must_equal({"reviews" => "result-a", "details" => "result-b"})
    end

    it "completes a single-branch parallel block on the first call" do
      parent = build_request
      parent.start_parallel_execution([{name: "solo"}])

      result = parent.complete_parallel_branch("solo", "only-result", 5.0)

      _(result).must_equal true
      _(parent.parallel_context).must_be_nil
    end

    it "records completed_branches/active_branches status via the underlying complete_branch call" do
      parent = build_request
      parent.start_parallel_execution([{name: "reviews"}])

      parent.complete_parallel_branch("reviews", "r", 7.0)

      branch = parent.active_branches.find { |b| b[:name] == "reviews" }
      _(branch[:status]).must_equal "completed"
      _(parent.completed_branches.map { |b| b[:name] }).must_equal ["reviews"]
    end

    it "a three-branch block only completes on the third call" do
      parent = build_request
      parent.start_parallel_execution([{name: "a"}, {name: "b"}, {name: "c"}])

      _(parent.complete_parallel_branch("a", nil, 1.0)).must_equal false
      _(parent.complete_parallel_branch("b", nil, 2.0)).must_equal false
      _(parent.complete_parallel_branch("c", nil, 3.0)).must_equal true
    end
  end
end
