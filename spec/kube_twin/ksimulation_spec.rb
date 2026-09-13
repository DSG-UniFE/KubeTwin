# frozen_string_literal: true

require 'minitest_helper'

# KSimulation's evaluate_allocation is a ~1200-line method with no unit
# coverage. Before any refactor of that method, this spec starts with the
# lowest-risk possible slice: the handful of KSimulation methods that are
# already pure functions (no @ivar reads, no simulation state) -- the Gini
# spreading metrics used by the multiobjective optimizer, and
# normalize_objective. These need no extraction at all to be testable in
# isolation; KUBETWIN::KSimulation.new takes no required arguments.
describe KUBETWIN::KSimulation do

  let(:sim) { KUBETWIN::KSimulation.new }

  describe '#gini_coefficient' do
    it 'is 0.0 for perfectly equal values (no inequality)' do
      _(sim.gini_coefficient([5, 5, 5, 5])).must_equal 0.0
    end

    it 'is 0.0 for arrays too small to compare (0 or 1 values)' do
      _(sim.gini_coefficient([])).must_equal 0.0
      _(sim.gini_coefficient([7])).must_equal 0.0
    end

    it 'is 0.0 when everything is zero, rather than dividing by zero' do
      _(sim.gini_coefficient([0, 0, 0])).must_equal 0.0
    end

    it 'reflects maximal inequality when all mass sits in one bin' do
      # replicas [10, 0, 0, 0] spread across 4 clusters: the worst possible
      # spreading for 10 replicas over 4 clusters
      _(sim.gini_coefficient([10, 0, 0, 0])).must_equal 0.75
    end
  end

  describe '#min_gini_coefficient / #max_gini_coefficient' do
    it 'min is 0.0 when replicas divide evenly across clusters' do
      _(sim.min_gini_coefficient(4, 4)).must_equal 0.0
    end

    it 'min is the Gini of the most even possible split when they do not divide evenly' do
      # 10 replicas over 4 clusters -> optimal split is [2, 2, 3, 3]
      _(sim.min_gini_coefficient(10, 4)).must_equal 0.1
    end

    it 'max is the Gini of concentrating everything into a single cluster' do
      _(sim.max_gini_coefficient(10, 4)).must_equal 0.75
    end

    it 'both are 0.0 for degenerate inputs (0 or 1 clusters, 0 replicas)' do
      _(sim.min_gini_coefficient(10, 1)).must_equal 0.0
      _(sim.max_gini_coefficient(10, 1)).must_equal 0.0
      _(sim.min_gini_coefficient(0, 4)).must_equal 0.0
      _(sim.max_gini_coefficient(0, 4)).must_equal 0.0
    end
  end

  describe '#normalized_gini' do
    it 'is 0.0 (best possible spreading) for the most even split achievable' do
      # 10 replicas over 4 clusters, split as evenly as possible: this is
      # exactly what min_gini_coefficient(10, 4) considers optimal
      _(sim.normalized_gini([2, 2, 3, 3])).must_equal 0.0
    end

    it 'is 1.0 (worst possible spreading) when everything sits in one cluster' do
      _(sim.normalized_gini([10, 0, 0, 0])).must_equal 1.0
    end
  end

  describe '#normalize_objective' do
    # every real call site passes min_obj: 0 and max_obj: mean_ttr (a
    # Float), so these use the same shape rather than bare integers --
    # Integer#/ silently truncates, and mean_ttr being a Float is exactly
    # what keeps that from biting in practice.
    it 'linearly rescales value into 0.0..1.0 given min_obj/max_obj' do
      _(sim.normalize_objective(5.0, 0, 10.0)).must_equal 0.5
      _(sim.normalize_objective(0.0, 0, 10.0)).must_equal 0.0
      _(sim.normalize_objective(10.0, 0, 10.0)).must_equal 1.0
    end

    it 'rescues to 1.0 when max_obj equals min_obj' do
      # If mean_ttr is ever exactly 0.0 (e.g. a run that closes zero
      # requests), max_obj - min_obj is 0.0 and this divides a non-zero
      # value by zero.
      result = sim.normalize_objective(3.0, 1.0, 1.0)
      _(result).must_equal 1.0
    end
  end

end
