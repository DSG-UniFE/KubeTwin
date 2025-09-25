# frozen_string_literal: true

require_relative './request'

module KUBETWIN
  class Statistics
    attr_reader :mean, :n, :received, :longer_than, :shorter_than
    alias closed n

    # see http://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm
    # and https://www.johndcook.com/blog/standard_deviation/
    def initialize(opts = {})
      @n    = 0 # number of requests
      @mean = 0.0
      @m_2  = 0.0
      @q_mean = 0.0
      @q_m_2 = 0.0
      @longer_than = init_counters_for_longer_than_stats(opts)
      @shorter_than = init_counters_for_shorter_than_stats(opts)
      @received = 0
      @csv = []
    end

    def request_received
      @received += 1
    end

    def record_request(req, time)
      # get new sample
      x = req.ttr(time)
      raise "TTR #{x} for request #{req.rid} invalid!" unless x > 0.0

      # string operations are slow << is the fastest
      steps = req.steps_ttr.join(',')
      # @csv << req.rid << ',' << x << ',' << steps << '\n'
      @csv << "#{req.rid},#{x},#{steps}\n"

      qx = req.queuing_time

      @longer_than.each_key do |k|
        @longer_than[k] += 1 if x > k
      end

      @shorter_than.each_key do |k|
        @shorter_than[k] += 1 if x < k
      end

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
      @q_m_2 / (@n - 1)
    end

    def add_custom_kpis(custom_kpis_config)
      # add custom kpis to the longer_than and shorter_than counters
      @longer_than.merge!(init_counters_for_longer_than_stats(custom_kpis_config))
      @shorter_than.merge!(init_counters_for_shorter_than_stats(custom_kpis_config))
    end

    def to_s
      "received: #{@received}, closed: #{@n}\n" +
        "TTR: (mean: #{@mean}, variance: #{variance}, longer_than: #{@longer_than}) shorter_than: #{@shorter_than}\n" +
        "QTIME: (mean: #{@q_mean}, variance: #{q_variance})"
    end

    def to_csv
      header = 'rid,ttr'
      "#{header}\n#{@csv.join}"
    end

    private

    def init_counters_for_longer_than_stats(custom_kpis_config)
      # prepare an infinite length enumerator that always returns zero
      zeros = Enumerator.new { |x| loop { x << 0 } }

      Hash[
        # wrap the values in custom_kpis_config[:longer_than] in an array
        Array(custom_kpis_config[:longer_than]).
        # and interval the numbers contained in that array with zeroes
        zip(zeros) ]
    end

    def init_counters_for_shorter_than_stats(custom_kpis_config)
      # prepare an infinite length enumerator that always returns zero
      zeros = Enumerator.new { |x| loop { x << 0 } }

      Hash[
        # wrap the values in custom_kpis_config[:longer_than] in an array
        Array(custom_kpis_config[:longer_than]).
        # and interval the numbers contained in that array with zeroes
        zip(zeros) ]
    end
  end
end
