# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'


describe KUBETWIN::LatencyManager do
  it 'should correctly work with reference configuration' do
    KUBETWIN::LatencyManager.new(LATENCY_MODELS)
  end
end
