# frozen_string_literal: true

require "logger"

module KUBETWIN
  # KubeTwin as an environment that a controller (for example, a
  # reinforcement learning agent) drives in steps:
  #
  #   twin = KUBETWIN::Twin.new(configuration)
  #   twin.reset                 # build the world and run the warm-up
  #   twin.step until twin.done? # advance one decision interval at a time
  #   twin.result                # what evaluate_allocation would return
  #
  # Time is measured in simulated seconds from the end of the warm-up.
  # Running a configuration to the end in steps gives exactly the results
  # of KSimulation#evaluate_allocation.
  class Twin
    DEFAULT_DECISION_INTERVAL = 30.0

    # Raised by #reset when the initial pods can't all be placed.
    class UnfeasibleAllocation < StandardError; end

    attr_reader :configuration, :decision_interval, :simulation

    def initialize(configuration, decision_interval: DEFAULT_DECISION_INTERVAL, logger: Logger.new(File::NULL))
      raise ArgumentError, "decision_interval must be positive" unless decision_interval.positive?

      @configuration = configuration
      @decision_interval = decision_interval.to_f
      @logger = logger
    end

    # Builds a fresh simulated world from the configuration and runs the
    # warm-up. Returns #now (0.0).
    def reset
      @simulation = KSimulation.new(configuration: @configuration, evaluator: Evaluator.new(@configuration),
        logger: @logger)
      raise UnfeasibleAllocation, "the initial pods can't all be placed" if @simulation.reset

      @origin = @simulation.warmup_threshold
      @simulation.run_until(@origin)
      @elapsed = 0.0
      @result = nil
      now
    end

    # Advances `duration` simulated seconds (by default one decision
    # interval; it must be a positive multiple of it). Returns #now.
    def step(duration: @decision_interval)
      ensure_reset!
      intervals = duration / @decision_interval
      unless duration.positive? && (intervals - intervals.round).abs < 1e-9
        raise ArgumentError, "duration must be a positive multiple of the decision interval (#{@decision_interval} s)"
      end

      @elapsed += duration
      @simulation.run_until(@origin + @elapsed)
      now
    end

    # Simulated seconds since the end of the warm-up.
    def now
      ensure_reset!
      @elapsed
    end

    # Whether the simulation has processed every event.
    def done?
      ensure_reset!
      @simulation.done?
    end

    # What KSimulation#evaluate_allocation returns for this run (the
    # negated weighted sum); available once #done?.
    def result
      raise "the run isn't finished" unless done?

      @result ||= @simulation.finish
    end

    private

    def ensure_reset!
      raise "call #reset first" unless @simulation
    end
  end
end
