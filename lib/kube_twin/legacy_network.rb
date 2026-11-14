# frozen_string_literal: true

module KUBETWIN
  # KubeTwin's own latency models (LatencyManager, LatencyManagerFederation)
  # as a network model: every message arrives, after the latency the model
  # samples between the two locations; size doesn't matter.
  #
  # A network model is any object with
  #   transfer(source, destination, bytes:, time:) -> #delay, #delivered
  # where source and destination are location ids (a cluster's
  # location_id, or a customer's). continuum-twin's network layer provides
  # models with bandwidth, loss and outages (KSimulation's network: option).
  class LegacyNetwork
    def initialize(latency_manager)
      @latency_manager = latency_manager
    end

    def transfer(source, destination, bytes:, time:)
      Transfer.new(latency(source, destination), true)
    end

    # The delay alone: Messaging's shortcut, since nothing is ever lost.
    def latency(source, destination)
      @latency_manager.sample_latency_between(source, destination)
    end

    # Link states don't change in the legacy model.
    def advance(to:)
    end
  end
end
