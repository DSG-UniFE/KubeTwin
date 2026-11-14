# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

# A network with its own random state: loses one message in ten.
class ForkSpecNetwork
  def initialize = @random = Random.new(11)

  def transfer(source, destination, bytes:, time:)
    KUBETWIN::Transfer.new(delay: 0.01 + @random.rand * 0.02, delivered: @random.rand(10) != 0)
  end
end

describe "KUBETWIN::Twin#fork" do
  def configuration(example)
    KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "#{example}.conf"))
  end

  def in_scratch_directory(&block)
    Dir.mktmpdir do |dir|
      File.symlink(File.join(Characterization::ROOT, "mdn_models"), File.join(dir, "mdn_models"))
      Dir.chdir(dir) { Characterization.quietly(&block) }
    end
  end

  # Everything a run shows from now on: each step's observation and
  # rejections, then the result.
  def future(twin, actions = [])
    trace = []
    until twin.done?
      twin.step(actions.shift || [])
      trace << [twin.observe, twin.last_rejected]
    end
    trace << twin.result
    # a digest, so a mismatch doesn't print thousands of observations
    Digest::SHA256.hexdigest(Marshal.dump(trace))
  end

  def scale(service, cluster, replicas) = KUBETWIN::Twin::ScaleReplicas.new(service:, cluster:, replicas:)

  Characterization::EXAMPLES.each do |example|
    it "replays its parent's future on #{example}" do
      in_scratch_directory do
        twin = KUBETWIN::Twin.new(configuration(example), decision_interval: 10.0)
        twin.reset
        2.times { twin.step }
        fork = twin.fork

        _(fork.now).must_equal twin.now
        _(future(fork)).must_equal future(twin)
      end
    end
  end

  it "replays the future with actions and a stateful network" do
    in_scratch_directory do
      twin = KUBETWIN::Twin.new(configuration("bookinfo-3c-xr"), decision_interval: 10.0, network: -> { ForkSpecNetwork.new })
      twin.reset
      twin.step
      fork = twin.fork
      actions = -> { [[scale("reviews", "cluster2edge", 2)], [scale("reviews", "cluster1", 0)]] }

      _(future(fork, actions.call)).must_equal future(twin, actions.call)
      _(fork.simulation.messaging.retransmissions).must_equal twin.simulation.messaging.retransmissions
    end
  end

  it "leaves the parent alone when the fork acts differently" do
    in_scratch_directory do
      baseline = KUBETWIN::Twin.new(configuration("parallel-working-test"), decision_interval: 10.0)
      baseline.reset
      baseline.step

      twin = KUBETWIN::Twin.new(configuration("parallel-working-test"), decision_interval: 10.0)
      twin.reset
      twin.step
      fork = twin.fork
      future(fork, [[scale("reviews", "europe-cloud-control-plane", 6)]])

      _(fork.replicas("reviews", "europe-cloud-control-plane")).must_equal 6
      _(twin.replicas("reviews", "europe-cloud-control-plane")).must_equal 2
      _(future(twin)).must_equal future(baseline)
    end
  end

  it "needs a reset first" do
    _ { KUBETWIN::Twin.new(configuration("parallel-working-test")).fork }.must_raise RuntimeError
  end
end
