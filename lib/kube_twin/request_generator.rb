# frozen_string_literal: true
require 'erv'

module KUBETWIN

  class RequestGenerator

    SEED = 12345

    def initialize(opts={})
      # get the configuration parameters
      @rg_rv = ERV::RandomVariable.new(opts[:request_distribution])
      @workflow_types = opts[:workflow_types]
      @num_customers = opts[:num_customers]
      @w_rv = Random.new(SEED)
      @c_rv = Random.new(SEED)
      @next_rid = 0
    end

    # generate the next request
    def generate(current_time)

      generation_time = current_time + @rg_rv.next
      workflow_type_id = @w_rv.rand(1..@workflow_types)
      customer_id = @c_rv.rand(1..@num_customers)

      # increase @next_rid
      @next_rid += 1

      # return request
      {
        rid: @next_rid,
        generation_time: generation_time,
        workflow_type_id: workflow_type_id,
        customer_id: customer_id,
      }
    end


  end

end
