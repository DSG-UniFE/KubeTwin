# frozen_string_literal: true

require 'minitest_helper'
require 'kube_twin/request'

describe KUBETWIN::Request do
  def request(**opts)
    KUBETWIN::Request.new(rid: 1, generation_time: 10.0, initial_data_center_id: :cluster1,
                          arrival_time: 10.5, workflow_type_id: 1, customer_id: 1, **opts)
  end

  it 'measures the response time from the arrival by default' do
    r = request
    r.finished_processing(12.0)
    _(r.ttr(12.0)).must_be_close_to 1.5, 1E-9
  end

  it 'measures it from the generation (client side) when asked' do
    r = request(ttr_from_generation: true)
    r.finished_processing(12.0)
    _(r.ttr(12.0)).must_be_close_to 2.0, 1E-9
  end
end
