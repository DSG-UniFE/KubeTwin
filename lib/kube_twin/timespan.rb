# frozen_string_literal: true

module KUBETWIN
  # Timespan turns human-readable units into a plain number of seconds.
  #
  # KubeTwin never needs calendar-aware duration arithmetic (there is no
  # day/week/month/year unit anywhere in the simulator or its example
  # configs) -- every duration here is a fixed-length span of seconds. That
  # means a Timespan doesn't need to be its own value type: each constructor
  # just returns a Float, so ordinary Float arithmetic already gives us
  # everything the old Integer-monkeypatching approach was for, with none of
  # its downsides (no core-class patching, no refinement scoping gotchas, no
  # JRuby special-casing):
  #
  #   Timespan.seconds(3) + Timespan.minutes(4) # => 243.0
  #   Timespan.new(seconds: 3, minutes: 4)       # => 243.0
  #   Time.now - Timespan.hours(1)               # => a Time one hour ago
  #
  # Add a new unit by adding one constant and one method pair below.
  module Timespan
    SECOND = 1.0
    MINUTE = 60 * SECOND
    HOUR   = 60 * MINUTE
    MSEC   = SECOND / 1000

    class << self
      def seconds(n) = n * SECOND
      alias second seconds

      def minutes(n) = n * MINUTE
      alias minute minutes

      def hours(n) = n * HOUR
      alias hour hours

      def msecs(n) = n * MSEC
      alias msec msecs

      # Timespan.new(seconds: 3, minutes: 4, hours: 1) => 3843.0
      def new(seconds: 0, minutes: 0, hours: 0, msecs: 0)
        seconds(seconds) + minutes(minutes) + hours(hours) + msecs(msecs)
      end
    end
  end
end
