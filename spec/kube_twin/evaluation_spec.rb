# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'


describe KUBETWIN::Evaluator do
  context '.penalties' do
    EXAMPLE_ALLOCATION = [
      { dc_id: 1, vm_size: :medium, vm_num: 20 },
      { dc_id: 1, vm_size:  :large, vm_num: 30 },
      { dc_id: 2, vm_size: :medium, vm_num: 50 },
      { dc_id: 2, vm_size:  :large, vm_num: 60 },
    ]

    it 'should work if no penalty function is provided' do
      evaluation_no_penalties = EVALUATION.reject {|x| x == :penalties }
      with_reference_config(evaluation: evaluation_no_penalties) do |conf|
        KUBETWIN::Evaluator.new(conf)
      end
    end

    it 'should work if penalty function returns something' do
      evaluator = with_reference_config do |conf|
        KUBETWIN::Evaluator.new(conf)
      end
      evaluator.evaluate_business_impact({ mttr: 0.075 }, nil, EXAMPLE_ALLOCATION)
    end

    it 'should work if penalty function returns nil' do
      evaluator = with_reference_config do |conf|
        KUBETWIN::Evaluator.new(conf)
      end
      evaluator.evaluate_business_impact({ mttr: 0.025 }, nil, EXAMPLE_ALLOCATION)
    end
  end
end
