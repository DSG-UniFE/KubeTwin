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
  FIXTURE = File.join(ROOT, "spec", "fixtures", "characterization.json")

  # Collects (request id, completion time) pairs while a run records.
  module RecordingStatistics
    def record_request(req, time, chain = false)
      Characterization.recorded&.push("#{req.rid}:#{format("%.6f", time.to_f)}")
      super
    end
  end
  KUBETWIN::Statistics.prepend(RecordingStatistics)

  # Counts the events one simulation schedules, by type.
  module CountingEvents
    def new_event(type, data, time, destination)
      @characterization_events[type] += 1
      super
    end
  end

  class << self
    attr_reader :recorded

    def fingerprint(example)
      conf = KUBETWIN::Configuration.load_from_file(File.join(ROOT, "examples", "#{example}.conf"))
      sim = KUBETWIN::KSimulation.new(configuration: conf, evaluator: KUBETWIN::Evaluator.new(conf),
        logger: Logger.new(File::NULL))
      sim.instance_variable_set(:@characterization_events, Hash.new(0))
      sim.singleton_class.prepend(CountingEvents)

      Dir.mktmpdir do |dir|
        # The run writes final_allocation.* into the current directory, and
        # MDN examples load ./mdn_models/.
        File.symlink(File.join(ROOT, "mdn_models"), File.join(dir, "mdn_models"))
        Dir.chdir(dir) do
          @recorded = []
          result = quietly { sim.evaluate_allocation }
          {
            "result" => result.to_f,
            "mean_ttr" => sim.instance_variable_get(:@last_mean_ttr).to_f,
            "replica_spreading" => sim.instance_variable_get(:@last_replica_spreading).to_f,
            "allocation" => JSON.parse(File.read("final_allocation.json")),
            "events" => sim.instance_variable_get(:@characterization_events).sort.to_h.transform_keys(&:to_s),
            "completions" => @recorded.size,
            "completions_digest" => Digest::SHA256.hexdigest(@recorded.join("\n"))
          }
        ensure
          @recorded = nil
        end
      end
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
