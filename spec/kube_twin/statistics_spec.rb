# frozen_string_literal: true

require "minitest_helper"

# What Statistics and ComponentStatistics read from a request.
StatisticsSpecRequest = Struct.new(:rid, :ttr_value, :queuing_time, :steps_ttr) do
  def ttr(_time) = ttr_value

  def step_queue_time = queuing_time
end

describe KUBETWIN::ComponentStatistics do
  it "resets to its initial state, keeping its thresholds" do
    stats = KUBETWIN::ComponentStatistics.new(longer_than: [0.5])
    stats.request_received
    stats.record_request(StatisticsSpecRequest.new(1, 1.0, 0.1, []), 0)
    stats.record_request(StatisticsSpecRequest.new(2, 0.2, 0.0, []), 0)
    _(stats.longer_than).must_equal({0.5 => 1})

    _(stats.reset).must_be_same_as stats
    _([stats.n, stats.received, stats.mean, stats.longer_than]).must_equal [0, 0, 0.0, {0.5 => 0}]

    fresh = KUBETWIN::ComponentStatistics.new(longer_than: [0.5])
    [stats, fresh].each { |s| s.record_request(StatisticsSpecRequest.new(3, 0.7, 0.2, []), 0) }
    _(stats.to_s).must_equal fresh.to_s
  end
end

describe KUBETWIN::Statistics do
  it "keeps a CSV line per request only when asked to" do
    req = StatisticsSpecRequest.new("r1", 0.25, 0.0, [0.1, 0.15])

    kept = KUBETWIN::Statistics.new(keep_csv: true)
    kept.record_request(req, 0)
    _(kept.to_csv).must_equal "rid,ttr\nr1,0.25,0.1,0.15\n"

    plain = KUBETWIN::Statistics.new
    plain.record_request(req, 0)
    _(plain.mean).must_equal 0.25
    _ { plain.to_csv }.must_raise RuntimeError
  end
end
