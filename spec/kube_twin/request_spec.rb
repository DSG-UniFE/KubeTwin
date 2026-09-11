# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'

describe KUBETWIN::Request do

  it 'should create a valid request and expose the values it was built with' do
    rid                    = rand(100)
    generation_time        = (Time.now - KUBETWIN::Timespan.hours(1)).to_f
    initial_data_center_id = rand(10)
    arrival_time           = Time.now.to_f
    workflow_type_id       = rand(4)
    customer_id            = 0

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

  it 'should default optional chain/branch attributes to nil' do
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

  it 'should accumulate queuing time across multiple waits' do
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

  it 'should advance worked_step and next_step when a step completes' do
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

end
