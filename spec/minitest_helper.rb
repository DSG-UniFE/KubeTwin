# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'kube_twin'

require 'minitest/spec'
require 'minitest-spec-context'

require 'minitest/autorun'

#
# Helper function that temporarily suppresses output, taken from
# https://gist.github.com/moertel/11091573
#
# Usage:
#   suppress_output { ... }
#
def suppress_output
  original_stdout, original_stderr = $stdout.clone, $stderr.clone
  $stderr.reopen File.new('/dev/null', 'w')
  $stdout.reopen File.new('/dev/null', 'w')
  yield
ensure
  $stdout.reopen original_stdout
  $stderr.reopen original_stderr
end

