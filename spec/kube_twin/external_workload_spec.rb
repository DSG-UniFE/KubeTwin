# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

# Arrivals every 0.1 s from :sensor, for workflow 1, until `until_time`.
class ExternalWorkloadSpecSource
  Arrival = Struct.new(:time, :location, :workflow, :bytes)

  attr_reader :asked

  def initialize(until_time: Float::INFINITY)
    @until_time = until_time
    @asked = []
  end

  def arrivals(from:, to:)
    @asked << [from, to]
    first = (from * 10).ceil
    (first...(to * 10).ceil).map { |k| k / 10.0 }.select { |t| t < @until_time }
      .map { |t| Arrival.new(t, :sensor, 1, 2_000) }
  end
end

# A network that knows :sensor: 30 ms to and from it, 1 ms elsewhere;
# remembers who sent what to whom.
class ExternalWorkloadSpecNetwork
  attr_reader :sends

  def initialize = @sends = []

  def transfer(source, destination, bytes:, time:)
    @sends << [source, destination, bytes]
    KUBETWIN::Transfer.new([source, destination].include?(:sensor) ? 0.03 : 0.001, true)
  end
end

describe "KubeTwin with an external workload" do
  def configuration
    KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "parallel-working-test.conf"))
  end

  def run_with(workload:, network: ExternalWorkloadSpecNetwork.new)
    twin = KUBETWIN::Twin.new(configuration, decision_interval: 5.0, workload:, network:)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        Characterization.quietly do
          twin.reset
          twin.step until twin.done?
          twin.result
        end
      end
    end
    [twin, network]
  end

  it "sends the workload's requests from its location, and responses back there" do
    source = ExternalWorkloadSpecSource.new
    twin, network = run_with(workload: source)

    from_sensor = network.sends.select { |s, _, _| s == :sensor }
    to_sensor = network.sends.select { |_, d, _| d == :sensor }
    _(from_sensor).wont_be_empty
    _(from_sensor.map(&:last).uniq).must_equal [2_000] # the arrival's bytes on the first message
    _(to_sensor.size).must_be_within_delta from_sensor.size, 50 # nearly every request answered by the end
    _(twin.simulation.instance_variable_get(:@external_requests)).must_equal from_sensor.size
  end

  it "asks the workload one interval at a time, until the cool-down" do
    source = ExternalWorkloadSpecSource.new
    twin, = run_with(workload: -> { source })
    simulation = twin.simulation
    horizon = simulation.cooldown_threshold - simulation.instance_variable_get(:@start_time)

    _(source.asked.first).must_equal [0.0, 1.0]
    _(source.asked.each_cons(2).all? { |(_, a), (b, _)| (a - b).abs < 1e-9 }).must_equal true
    _(source.asked.last.first).must_be :<, horizon
  end

  it "adds load: more requests complete than without the workload" do
    plain, = run_with(workload: ExternalWorkloadSpecSource.new(until_time: 0.0))
    loaded, = run_with(workload: ExternalWorkloadSpecSource.new)
    completed = ->(twin) { twin.simulation.instance_variable_get(:@stats).n }

    _(completed.call(loaded)).must_be :>, completed.call(plain)
  end
end
