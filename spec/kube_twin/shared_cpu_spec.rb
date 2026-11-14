# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

# One container fed Poisson arrivals, with just enough of a simulation
# around it to run its events. Checks CPU sharing against queueing theory.
class SharedCpuQueue
  ARRIVAL = -1

  Req = Struct.new(:arrival, :arrival_at_container) do
    def update_queuing_time(_) = nil

    def step_completed(_) = nil
  end

  def initialize(service_time:, arrival_rate:, max_processes:, cores: nil, seed: 1)
    image = {max_processes:, cores:, rps: 1}.compact
    @container = KUBETWIN::Container.new(0, 1, service_time,
      {blocking: true, node: nil, label: "s", img_info: image, max_processes:, stream_seeds: Random.new(seed)})
    @queue = KUBETWIN::PriorityQueue.new
    @arrivals = Random.new(seed + 1)
    @arrival_rate = arrival_rate
  end

  def new_event(type, data, time, destination) = @queue << KUBETWIN::Event.new(type, data, time, destination)

  def retrieve_mdn_model(*) = nil

  # Mean response time of `n` requests, after `warmup` more.
  def mean_response(n, warmup: 5_000)
    responses = []
    time = 0.0
    (n + warmup).times do
      time += -Math.log(1.0 - @arrivals.rand) / @arrival_rate
      new_event(ARRIVAL, Req.new(time), time, nil)
    end
    until @queue.empty?
      e = @queue.shift
      case e.type
      when ARRIVAL then @container.new_request(self, e.data, e.time)
      when KUBETWIN::Event::ET_SHARED_COMPLETION then @container.shared_completion(self, e.time, e.data)
      when KUBETWIN::Event::ET_WORKFLOW_STEP_COMPLETED
        responses << e.time - e.data.arrival
        @container.request_finished(self, e.time)
      end
    end
    kept = responses.drop(warmup)
    kept.sum / kept.size
  end
end

SharedCpuQueue::EXPONENTIAL = {distribution: :exponential, args: {rate: 10.0}}.freeze # mean 0.1 s
SharedCpuQueue::NEAR_CONSTANT = {distribution: :gaussian, args: {mean: 0.1, sd: 0.005}}.freeze

describe "Container CPU sharing" do
  def exponential = SharedCpuQueue::EXPONENTIAL

  def near_constant = SharedCpuQueue::NEAR_CONSTANT

  def mean_response(n = 100_000, **options) = SharedCpuQueue.new(**options).mean_response(n)

  it "matches M/M/1 processor sharing: 1 / (mu - lambda)" do
    _(mean_response(service_time: exponential, arrival_rate: 7.0, max_processes: 1_000, cores: 1)).must_be_within_epsilon 1 / (10.0 - 7.0), 0.04
  end

  it "is insensitive to the service time distribution, unlike first come first served" do
    shared = mean_response(service_time: near_constant, arrival_rate: 7.0, max_processes: 1_000, cores: 1)
    fcfs = mean_response(service_time: near_constant, arrival_rate: 7.0, max_processes: 1)

    _(shared).must_be_within_epsilon 0.1 / (1 - 0.7), 0.04 # E[S] / (1 - rho), any distribution
    _(fcfs).must_be_within_epsilon 0.1 + 0.7 * 0.1 / (2 * (1 - 0.7)), 0.04 # Pollaczek-Khinchine, M/D/1
  end

  it "matches M/M/2 when two cores are shared" do
    a = 1.4 # offered load: lambda / mu
    erlang_c = (a**2 / 2 * 2 / (2 - a)) / (1 + a + a**2 / 2 * 2 / (2 - a))
    expected = 0.1 + erlang_c / (2 * 10.0 - 14.0)

    _(mean_response(service_time: exponential, arrival_rate: 14.0, max_processes: 1_000, cores: 2)).must_be_within_epsilon expected, 0.04
  end

  it "changes nothing while there are at least as many cores as processes" do
    plain = SharedCpuQueue.new(service_time: exponential, arrival_rate: 25.0, max_processes: 3).mean_response(5_000, warmup: 0)
    shared = SharedCpuQueue.new(service_time: exponential, arrival_rate: 25.0, max_processes: 3, cores: 3).mean_response(5_000, warmup: 0)

    _(shared).must_be_within_epsilon plain, 1e-9
  end

  it "rejects non-positive cores" do
    _ { SharedCpuQueue.new(service_time: exponential, arrival_rate: 1.0, max_processes: 1, cores: 0) }.must_raise ArgumentError
  end
end

describe "KubeTwin with shared CPUs" do
  def p95s(cores, fork: false)
    conf = KUBETWIN::Configuration.load_from_file(File.join(Characterization::ROOT, "examples", "parallel-working-test.conf"))
    conf.microservice_types["productpage"][:cores] = cores if cores
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        Characterization.quietly do
          twin = KUBETWIN::Twin.new(conf, decision_interval: 5.0)
          twin.reset
          twin.step
          twin = twin.fork if fork
          Array.new(4) { twin.step && twin.observe[:workflows].map { |w| w[:features][:response_p95] } }.flatten
        end
      end
    end
  end

  it "slows a busy service down when its processes share fewer cores" do
    plain = p95s(nil)
    shared = p95s(0.25) # productpage: 4 processes on a quarter core

    _(p95s(4)).must_equal plain # as many cores as processes: unchanged
    _(shared.sum).must_be :>, 2 * plain.sum
    _(p95s(0.25, fork: true)).must_equal shared
  end
end
