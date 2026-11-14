# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

describe KUBETWIN::Twin do
  def configuration
    KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "parallel-working-test.conf"))
  end

  # The run's wind-down writes final_allocation.* into the current directory.
  def in_scratch_directory(&block)
    Dir.mktmpdir { |dir| Dir.chdir(dir) { Characterization.quietly(&block) } }
  end

  it "starts at time 0 after the warm-up and advances one decision interval per step" do
    twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

    in_scratch_directory do
      _(twin.reset).must_equal 0.0
      _(twin.simulation.now).must_equal twin.simulation.warmup_threshold
      _(twin.step).must_equal 5.0
      _(twin.step(duration: 10.0)).must_equal 15.0
      _(twin.simulation.now).must_equal twin.simulation.warmup_threshold + 15.0
      _(twin.done?).must_equal false
    end
  end

  it "rejects durations that aren't positive multiples of the decision interval" do
    twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0)

    in_scratch_directory do
      twin.reset
      _ { twin.step(duration: 7.0) }.must_raise ArgumentError
      _ { twin.step(duration: 0.0) }.must_raise ArgumentError
    end
  end

  it "runs to the end and reports evaluate_allocation's result" do
    twin = KUBETWIN::Twin.new(configuration)

    in_scratch_directory do
      twin.reset
      _ { twin.result }.must_raise RuntimeError
      twin.step until twin.done?

      _(twin.result).must_be_within_epsilon Characterization.fingerprint("parallel-working-test")["result"], 1e-12
      _(twin.result).must_equal twin.result
    end
  end

  it "needs a reset before stepping, and a positive decision interval" do
    _ { KUBETWIN::Twin.new(configuration).step }.must_raise RuntimeError
    _ { KUBETWIN::Twin.new(configuration, decision_interval: 0) }.must_raise ArgumentError
  end
end
