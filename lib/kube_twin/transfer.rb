# frozen_string_literal: true

module KUBETWIN
  # The outcome of sending a message: how long it took (seconds), and
  # whether it arrived. Same shape as continuum-twin's Continuum::Transfer.
  Transfer = Data.define(:delay, :delivered)
end
