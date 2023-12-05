# frozen_string_literal: true
require 'erv'

module KUBETWIN

  class RequestGenerator

    SEED = 12345

    def initialize(opts={})
      # get the configuration parameters
      @starting_time = opts[:starting_time]
      @rg_rv = ERV::RandomVariable.new(opts[:request_distribution])
      @workflow_types = opts[:workflow_types]
      @num_customers = opts[:num_customers]
      @num_requests = opts[:num_requests]
      @w_rv = Random.new(SEED)
      @c_rv = Random.new(SEED)
      @next_rid = 0
    end

    # generate the next request
    def generate(current_time)
      if @num_requests && @next_rid >= @num_requests
        puts "No more requests to generate!"
        return nil
      end
      #while (nr = @rg_rv.next) <= 1E-2; end
      #rs = Array.new(10) { @rg_rv.next }
      #nr = rs.sum() / rs.length
      nr = @rg_rv.next
      # nr is commentedd for fitting purposes ...
      generation_time = current_time + nr
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
