# frozen_string_literal: true

require 'logger'


module KUBETWIN
  module Logging
    class << self
      def logger
        @logger ||= ::Logger.new(STDERR).tap{|l| l.level = ::Logger::INFO }
      end
    end

    def self.included(base)
      class << base
        # this version of the logger method will be called from class methods
        def logger
          Logging.logger
        end
      end
    end

    # this version of the logger method will be called from instance methods
    def logger
      Logging.logger
    end
  end
end
