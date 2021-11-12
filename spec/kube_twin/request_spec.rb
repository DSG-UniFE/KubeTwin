# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'


describe KUBETWIN::Request do

  it 'should create a valid request' do
    KUBETWIN::Request.new(rid:                    rand(100),
                       generation_time:        (Time.now - 1.hour).to_f,
                       initial_data_center_id: rand(10),
                       arrival_time:           Time.now.to_f,
                       workflow_type_id:       rand(4),
                       customer_id:            0)
  end

end
