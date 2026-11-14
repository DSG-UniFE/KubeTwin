# frozen_string_literal: true

module KUBETWIN
  # Sends KubeTwin's messages (requests between components, responses back)
  # over a network model, retransmitting lost ones the way TCP would: after
  # a timeout that doubles on each loss, up to `max_attempts` sends.
  #
  # A message still lost after the last attempt is counted as undelivered
  # and handed over anyway, after the time spent trying: KubeTwin can't yet
  # abort a request midway through its workflow.
  class Messaging
    DEFAULT_TIMEOUT = 0.2 # seconds, Linux's minimum TCP retransmission timeout
    DEFAULT_MAX_ATTEMPTS = 8

    attr_reader :network, :retransmissions, :undelivered

    def initialize(network, timeout: DEFAULT_TIMEOUT, max_attempts: DEFAULT_MAX_ATTEMPTS)
      raise ArgumentError, "timeout must be positive" unless timeout.positive?
      raise ArgumentError, "max_attempts must be at least 1" unless max_attempts >= 1

      @network = network
      @timeout = timeout.to_f
      @max_attempts = max_attempts
      @retransmissions = 0
      @undelivered = 0
      @legacy = network.is_a?(LegacyNetwork)
    end

    # Seconds from sending `bytes` at `time` from `source` to `destination`
    # (location ids) until it arrives.
    def message_delay(source, destination, time:, bytes: 0)
      return @network.latency(source, destination) if @legacy

      waited = 0.0
      timeout = @timeout
      attempt = 1
      loop do
        transfer = @network.transfer(source, destination, bytes:, time: time + waited)
        return waited + transfer.delay if transfer.delivered

        if attempt == @max_attempts
          @undelivered += 1
          return waited + timeout
        end

        @retransmissions += 1
        waited += timeout
        timeout *= 2
        attempt += 1
      end
    end
  end
end
