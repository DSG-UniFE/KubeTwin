# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

# A network that loses the first `losses` messages it sees, then delivers
# everything after `delay` seconds; records each send.
class MessagingSpecNetwork
  attr_reader :sends

  def initialize(losses:, delay: 0.01)
    @losses = losses
    @delay = delay
    @sends = []
  end

  def transfer(source, destination, bytes:, time:)
    @sends << [source, destination, bytes, time]
    delivered = @sends.size > @losses
    KUBETWIN::Transfer.new(delay: delivered ? @delay : 0.0, delivered:)
  end
end

# Loses one message in `every`, at random; otherwise 20 ms.
class MessagingSpecLossyNetwork
  def initialize(every:, seed: 1)
    @every = every
    @random = Random.new(seed)
  end

  def transfer(source, destination, bytes:, time:)
    KUBETWIN::Transfer.new(delay: 0.02, delivered: @random.rand(@every) != 0)
  end
end

describe KUBETWIN::Messaging do
  it "passes a delivered message's delay through" do
    network = MessagingSpecNetwork.new(losses: 0, delay: 0.03)
    messaging = KUBETWIN::Messaging.new(network)

    _(messaging.message_delay(1, 2, time: 10.0, bytes: 100)).must_equal 0.03
    _(network.sends).must_equal [[1, 2, 100, 10.0]]
    _(messaging.retransmissions).must_equal 0
  end

  it "retransmits lost messages after a doubling timeout" do
    network = MessagingSpecNetwork.new(losses: 2, delay: 0.03)
    messaging = KUBETWIN::Messaging.new(network, timeout: 0.2)

    _(messaging.message_delay(1, 2, time: 10.0)).must_be_within_epsilon 0.2 + 0.4 + 0.03, 1e-12
    _(network.sends.map(&:last)).must_equal [10.0, 10.2, 10.6]
    _(messaging.retransmissions).must_equal 2
    _(messaging.undelivered).must_equal 0
  end

  it "gives up after max_attempts, counting the message as undelivered" do
    network = MessagingSpecNetwork.new(losses: 10)
    messaging = KUBETWIN::Messaging.new(network, timeout: 1.0, max_attempts: 3)

    _(messaging.message_delay(1, 2, time: 0.0)).must_equal 1.0 + 2.0 + 4.0
    _(network.sends.size).must_equal 3
    _(messaging.undelivered).must_equal 1
  end

  it "gives the network times since its origin" do
    network = MessagingSpecNetwork.new(losses: 1)
    messaging = KUBETWIN::Messaging.new(network, timeout: 0.5, origin: 1_000.0)

    _(messaging.message_delay(1, 2, time: 1_010.0)).must_be_within_epsilon 0.5 + 0.01, 1e-12
    _(network.sends.map(&:last)).must_equal [10.0, 10.5]
  end
end

describe "KSimulation over a lossy network" do
  def first_step_over(network)
    conf = KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "parallel-working-test.conf"))
    twin = KUBETWIN::Twin.new(conf, decision_interval: 10.0, network:)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        Characterization.quietly do
          twin.reset
          twin.step
          [twin.observe[:workflows].map { |w| w[:features][:response_p95] }, twin.simulation.messaging]
        end
      end
    end
  end

  it "builds a fresh network for each run when given a builder" do
    built = 0
    builder = lambda do
      built += 1
      MessagingSpecLossyNetwork.new(every: 1_000_000)
    end
    first_step_over(builder)
    first_step_over(builder)
    _(built).must_equal 2
  end

  it "slows responses down when messages are lost" do
    reliable, = first_step_over(-> { MessagingSpecLossyNetwork.new(every: 1_000_000) })
    lossy, messaging = first_step_over(-> { MessagingSpecLossyNetwork.new(every: 10) })

    _(messaging.retransmissions).must_be :>, 0
    lossy.zip(reliable).each { |l, r| _(l).must_be :>, r + 100 } # a 200 ms retransmission shows in p95
  end
end
