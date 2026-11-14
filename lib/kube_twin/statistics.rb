# frozen_string_literal: true

module KUBETWIN
  class Statistics
    attr_reader :mean, :n, :received, :longer_than, :shorter_than
    alias_method :closed, :n

    # see http://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm
    # and https://www.johndcook.com/blog/standard_deviation/
    #
    # opts[:keep_csv]: keep a CSV line per recorded request, for #to_csv
    # (off by default: it costs several allocations and ~100 bytes per
    # request).
    def initialize(opts = {})
      @n = 0 # number of requests
      @mean = 0.0
      @m_2 = 0.0
      @q_mean = 0.0
      @q_m_2 = 0.0
      @longer_than = init_counters_for_longer_than_stats(opts)
      @shorter_than = init_counters_for_shorter_than_stats(opts)
      @received = 0
      @csv = opts[:keep_csv] ? [] : nil
      @samples = []
    end

    def request_received
      @received += 1
    end

    def record_request(req, time, chain = false)
      # get new sample
      x = if chain
        req.ttr_chain(time)
      else
        req.ttr(time)
      end
      raise "TTR #{x} for request #{req.rid} invalid!" unless x > 0.0

      @csv << "#{req.rid},#{x},#{req.steps_ttr.join(",")}\n" if @csv
      @samples << x

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
      @m_2 += delta * (x - @mean)
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

    def percentile(q)
      return 0.0 if @samples.empty?

      sorted = @samples.sort
      sorted[(q * (sorted.length - 1)).to_i]
    end

    def p50
      percentile(0.50)
    end

    def p90
      percentile(0.90)
    end

    def p95
      percentile(0.95)
    end

    def p99
      percentile(0.99)
    end

    def to_s
      "received: #{@received}, closed: #{@n}\n" \
        "TTR: (mean: #{@mean}, variance: #{variance}, p50: #{p50}, p90: #{p90}, p95: #{p95}, p99: #{p99}, longer_than: #{@longer_than}) shorter_than: #{@shorter_than}\n" \
        "QTIME: (mean: #{@q_mean}, variance: #{q_variance})"
    end

    # The recorded requests as CSV; needs keep_csv: true.
    def to_csv
      raise "create the Statistics with keep_csv: true to get its CSV" unless @csv

      header = "rid,ttr"
      "#{header}\n#{@csv.join}"
    end

    private

    def init_counters_for_longer_than_stats(custom_kpis_config)
      Array(custom_kpis_config[:longer_than]).to_h { |threshold| [threshold, 0] }
    end

    def init_counters_for_shorter_than_stats(custom_kpis_config)
      Array(custom_kpis_config[:longer_than]).to_h { |threshold| [threshold, 0] }
    end
  end
end
