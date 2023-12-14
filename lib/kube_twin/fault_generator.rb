# frozen_string_literal: true
require 'erv'

module KUBETWIN

  class FaultGenerator

    SEED = 12345
    attr_reader :rid

    def initialize(opts={})
      # get the configuration parameters
      @starting_time = opts[:starting_time]
      @rg_rv = ERV::RandomVariable.new(opts[:fault_time_distribution])
      @cluster = opts[:cluster]
      @num_faults = opts[:num_faults]
      @next_fid = 0
    end

    # generate the next request
    def generate(current_time)
      if @num_faults && @next_fid >= @num_faults
        puts "No more faults to generate!"
        return nil
      end
      nr = @rg_rv.next
      generation_time = current_time + nr

      # increase @next_fid
      @next_fid += 1

      # return fault
      {
        fid: @next_fid,
        cluster: @cluster,
        generation_time: generation_time,
      }
    end


  end

end
