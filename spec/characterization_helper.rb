# frozen_string_literal: true

require "digest"
require "json"
require "tmpdir"
require "kube_twin"

# Characterization ("golden master") runs: each maintained example is
# simulated in full and reduced to a fingerprint -- result, metrics, final
# allocation, event counts by type, and a digest of every recorded request
# completion. spec/kube_twin/characterization_spec.rb checks that the
# fingerprints still match spec/fixtures/characterization.json, so a
# refactoring that changes behaviour, even only the order of events, fails.
# After an intended behaviour change, regenerate the fixture with
# bin/record_characterization and review its diff.
module Characterization
  ROOT = File.expand_path("..", __dir__)
  EXAMPLES = %w[parallel-working-test example-hpa bookinfo-3c-xr].freeze
  # Examples whose service times come from MDN models: LibTorch evaluates
  # them in float32, and its results differ in the last bits across
  # platforms (bookinfo-3c-xr's result differs by a relative 3e-8 between
  # macOS on Apple Silicon and Linux on x86-64), so their completion times
  # can't be expected to match to the microsecond everywhere.
  MDN_EXAMPLES = %w[bookinfo-3c-xr].freeze
  FIXTURE = File.join(ROOT, "spec", "fixtures", "characterization.json")

  # Collects (request id, completion time) pairs while a run records.
  module RecordingStatistics
    def record_request(req, time, chain = false)
      Characterization.recorded&.push("#{req.rid}:#{format("%.6f", time.to_f)}")
      super
    end
  end
  KUBETWIN::Statistics.prepend(RecordingStatistics)

  # Counts the events simulations schedule, by type, while a run records.
  module CountingEvents
    def new_event(type, data, time, destination)
      Characterization.events[type] += 1 if Characterization.events
      super
    end
  end
  KUBETWIN::KSimulation.prepend(CountingEvents)

  class << self
    attr_reader :recorded, :events

    # Runs `example` with KSimulation#evaluate_allocation, or, given
    # `step` (seconds), with a KUBETWIN::Twin advanced one step at a time.
    def fingerprint(example, step: nil)
      conf = KUBETWIN::Configuration.load_from_file(File.join(ROOT, "examples", "#{example}.conf"))

      Dir.mktmpdir do |dir|
        # The run writes final_allocation.* into the current directory, and
        # MDN examples load ./mdn_models/.
        File.symlink(File.join(ROOT, "mdn_models"), File.join(dir, "mdn_models"))
        Dir.chdir(dir) do
          @recorded = []
          @events = Hash.new(0)
          result, sim = quietly { step ? run_in_steps(conf, step) : run_whole(conf) }
          {
            "result" => result.to_f,
            "mean_ttr" => sim.instance_variable_get(:@last_mean_ttr).to_f,
            "replica_spreading" => sim.instance_variable_get(:@last_replica_spreading).to_f,
            "allocation" => JSON.parse(File.read("final_allocation.json")),
            "events" => @events.sort.to_h.transform_keys(&:to_s),
            "completions" => @recorded.size,
            "completions_digest" => Digest::SHA256.hexdigest(@recorded.join("\n"))
          }
        ensure
          @recorded = nil
          @events = nil
        end
      end
    end

    def run_whole(conf)
      sim = KUBETWIN::KSimulation.new(configuration: conf, evaluator: KUBETWIN::Evaluator.new(conf),
        logger: Logger.new(File::NULL))
      [sim.evaluate_allocation, sim]
    end

    def run_in_steps(conf, step)
      twin = KUBETWIN::Twin.new(conf, decision_interval: step)
      twin.reset
      twin.step until twin.done?
      [twin.result, twin.simulation]
    end

    def quietly
      original = $stdout
      $stdout = File.open(File::NULL, "w")
      yield
    ensure
      $stdout = original
    end
  end
end
