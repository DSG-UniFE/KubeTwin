# frozen_string_literal: true

require "minitest_helper"

require_relative "reference_configuration"

describe KUBETWIN::Evaluator do
  context ".penalties" do
    it "should work if no penalty function is provided" do
      evaluation_no_penalties = EVALUATION.reject { |x| x == :penalties }
      with_reference_config(evaluation: evaluation_no_penalties) do |conf|
        KUBETWIN::Evaluator.new(conf)
      end
    end
  end
end
