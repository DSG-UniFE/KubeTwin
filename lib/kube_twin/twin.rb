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
  # A step can carry actions, applied at its start:
  #
  #   twin.step([KUBETWIN::Twin::ScaleReplicas.new(service: "reviews", cluster: "rome", replicas: 3)])
  #   twin.last_rejected         # => [] or [[action, reason], ...]
  #
  # After each step, #observe summarizes it (see KSimulation#observation).
  #
  # Time is measured in simulated seconds from the end of the warm-up.
  # Running a configuration to the end in steps without actions gives
  # exactly the results of KSimulation#evaluate_allocation.
  class Twin
    DEFAULT_DECISION_INTERVAL = 30.0

    # Raised by #reset when the initial pods can't all be placed.
    class UnfeasibleAllocation < StandardError; end

    # Run `replicas` pods of `service` in `cluster` (names as in the
    # configuration).
    ScaleReplicas = Data.define(:service, :cluster, :replicas)

    attr_reader :configuration, :decision_interval, :simulation

    # The actions the last #step rejected, as [action, reason] pairs (see
    # KSimulation#scale_replicas_rejection for the reasons).
    attr_reader :last_rejected

    # slos: workflow id => p95 response-time objective in ms, for the
    # observation's slo_violation_rate.
    def initialize(configuration, decision_interval: DEFAULT_DECISION_INTERVAL, logger: Logger.new(File::NULL),
      slos: {})
      raise ArgumentError, "decision_interval must be positive" unless decision_interval.positive?

      @configuration = configuration
      @decision_interval = decision_interval.to_f
      @logger = logger
      @slos = slos
      @last_rejected = []
    end

    # Builds a fresh simulated world from the configuration and runs the
    # warm-up. Returns #now (0.0).
    def reset
      @simulation = KSimulation.new(configuration: @configuration, evaluator: Evaluator.new(@configuration),
        logger: @logger, observe: true)
      raise UnfeasibleAllocation, "the initial pods can't all be placed" if @simulation.reset

      @origin = @simulation.warmup_threshold
      @simulation.run_until(@origin)
      @elapsed = 0.0
      @result = nil
      @last_rejected = []
      # Discard what the warm-up recorded.
      @observation = @simulation.observation(0.0, time: 0.0, slos: @slos)
      now
    end

    # Applies `actions` in order (an action that can't be applied is skipped
    # and recorded in #last_rejected), then advances `duration` simulated
    # seconds (by default one decision interval; it must be a positive
    # multiple of it). Returns #now.
    def step(actions = [], duration: @decision_interval)
      ensure_reset!
      intervals = duration / @decision_interval
      unless duration.positive? && (intervals - intervals.round).abs < 1e-9
        raise ArgumentError, "duration must be a positive multiple of the decision interval (#{@decision_interval} s)"
      end

      @last_rejected = actions.filter_map do |action|
        reason = apply(action)
        [action, reason] if reason
      end
      @elapsed += duration
      @simulation.run_until(@origin + @elapsed)
      @observation = @simulation.observation(duration, time: now, slos: @slos)
      now
    end

    # The simulation as of the end of the last step, with rates and
    # statistics over that step (after #reset, an empty window: zero rates).
    def observe
      ensure_reset!
      @observation
    end

    # Whether `action` could be applied now.
    def feasible?(action)
      ensure_reset!
      rejection(action).nil?
    end

    # How many pods of `service` run in `cluster` now.
    def replicas(service, cluster)
      ensure_reset!
      @simulation.replicas(service, cluster)
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

    def apply(action)
      case action
      when ScaleReplicas then @simulation.scale_replicas(action.service, action.cluster, action.replicas)
      else :unknown_action
      end
    end

    def rejection(action)
      case action
      when ScaleReplicas then @simulation.scale_replicas_rejection(action.service, action.cluster, action.replicas)
      else :unknown_action
      end
    end
  end
end
