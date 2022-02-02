# frozen_string_literal: true

require_relative './request'


module KUBETWIN
  class ComponentStatistics
    attr_reader :mean, :n, :received, :longer_than
    alias_method :closed, :n

    # see http://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm
    # and https://www.johndcook.com/blog/standard_deviation/
    def initialize(opts={})
      @n    = 0 # number of requests
      @mean = 0.0
      @m_2  = 0.0
      @q_mean = 0.0
      @q_m_2 = 0.0
      @received = 0
    end

    def request_received
      @received += 1
    end

    def record_request(req, time)
      # get new sample
      x = req.ttr(time)
      raise "TTR #{x} for request #{req.rid} invalid!" unless x > 0.0

      qx = req.queuing_time

      # update counters
      @n += 1
      delta = x - @mean
      @mean += delta / @n
      @m_2  += delta * (x - @mean)
      # update qtime values
      delta_q = qx - @q_mean
      @q_mean += delta_q / @n
      @q_m_2 += delta * (qx - @q_mean)
    end

    def variance
      @m_2 / (@n - 1)
    end

    def q_variance
      @q_m_2 / (@n -1)
    end

    def to_s
      "received: #{@received}, closed: #{@n}\n" +
      "TTR: (mean: #{@mean}, variance: #{variance}, longer_than: #{@longer_than.to_s})\n" +
      "QTIME: (mean: #{@q_mean}, variance: #{q_variance})"
    end

  end
end
