# frozen_string_literal: true

require "minitest_helper"

describe KUBETWIN::ReplicaDivision do
  def divide(...) = KUBETWIN::ReplicaDivision.divide(...)

  it "apportions by weight with the largest remainder" do
    _(divide(5, {rome: 2, milan: 1}).counts).must_equal({rome: 3, milan: 2})
    _(divide(10, {a: 1, b: 1, c: 1}).counts).must_equal({a: 4, b: 3, c: 3})
    _(divide(7, {a: 5, b: 3, c: 2}).counts).must_equal({a: 4, b: 2, c: 1})
    _(divide(0, {a: 1}).counts).must_equal({a: 0})
  end

  it "always places the whole total when capacity allows" do
    rng = Random.new(1)
    200.times do
      weights = (1..rng.rand(1..6)).to_h { |i| [:"c#{i}", rng.rand(1..9)] }
      total = rng.rand(0..50)
      _(divide(total, weights).counts.values.sum).must_equal total
    end
  end

  it "keeps only the heaviest clusters under max_clusters" do
    _(divide(6, {a: 1, b: 3, c: 2}, max_clusters: 2).counts).must_equal({b: 4, c: 2})
  end

  it "spreads over at least min_clusters" do
    _(divide(3, {a: 10, b: 1, c: 1}).counts).must_equal({a: 3, b: 0, c: 0})
    _(divide(3, {a: 10, b: 1, c: 1}, min_clusters: 2).counts).must_equal({a: 2, b: 1, c: 0})
    _(divide(1, {a: 10, b: 1}, min_clusters: 2).counts).must_equal({a: 1, b: 0}) # too few replicas to spread
  end

  it "overflows to clusters with room, and counts what fits nowhere" do
    result = divide(9, {a: 2, b: 1}, capacity: {a: 4})
    _(result.counts).must_equal({a: 4, b: 5})
    _(result.unschedulable).must_equal 0

    full = divide(9, {a: 2, b: 1}, capacity: {a: 4, b: 3})
    _(full.counts).must_equal({a: 4, b: 3})
    _(full.unschedulable).must_equal 2
  end

  it "reports everything unschedulable without eligible clusters, and rejects bad input" do
    _(divide(3, {}).unschedulable).must_equal 3
    _ { divide(-1, {a: 1}) }.must_raise ArgumentError
    _ { divide(2, {a: 0}) }.must_raise ArgumentError
  end
end
