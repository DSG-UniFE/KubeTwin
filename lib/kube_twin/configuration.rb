# frozen_string_literal: true

require_relative './support/dsl_helper'
require_relative './logger'

require 'as-duration'
require 'ice_nine'

module ERV
  module GaussianMixtureHelper
    def self.RawParametersToMixtureArgs(*args)
      raise ArgumentError, "Arguments must be a multiple of 3!" if (args.count % 3) != 0
      args.each_slice(3).map do |(a,b,c)|
        { distribution: :gaussian, weight: a * c, args: { mean: b, sd: c } }
      end
    end

    def self.RawParametersToMixtureArgsSeed(*args, seed)
      raise ArgumentError, "Arguments must be a multiple of 3!" if (args.count % 3) != 0
      args.each_slice(3).map do |(a,b,c)|
        { distribution: :gaussian, weight: a * c, args: { mean: b, sd: c, seed: seed } }
      end
    end
  end

  module GammaMixtureHelper
    def self.RawParametersToMixtureArgsSeed(*args, seed)
      raise ArgumentError, "Arguments must be a multiple of 3!" if (args.count % 3) != 0
      args.each_slice(3).map do |(a,b,c)|
        { distribution: :gamma, weight: a, args: { scale: c, shape: b, seed: seed } }
      end
    end
  end
end

if defined? JRUBY_VERSION
  # JRuby 9.2 still has a buggy support for refinements, so we need to revert
  # to the brutal monkeypatching of the Integer class
  class Integer
    # def minute; self * 60; end
    # def minutes; self * 60; end
    # def second; self; end
    # def seconds; self; end
    def msec; self * 1E-3; end
    def msecs; self * 1E-3; end
  end
else
  module TimeExtensions
    refine Integer do
      # def minute; self * 60; end
      # def minutes; self * 60; end
      # def second; self; end
      # def seconds; self; end
      def msec; self * 1E-3; end
      def msecs; self * 1E-3; end
    end
  end
end

module KUBETWIN

  module Configurable
    dsl_accessor :constraints,
                 :customers,
                 :custom_stats,
                 :stats_print_interval,
                 :data_centers,
                 :federation,
                 :clusters,
                 :node,
                 :replica_sets,
                 :horizontal_pod_autoscalers,
                 :services,
                 :duration,
                 :evaluation,
                 :kpi_customization,
                 :latency_models,
                 :request_generation,
                 :request_gen,
                 :microservice_types,
                 :seeds,
                 :start_time,
                 :warmup_duration,
                 :cooldown_duration,
                 :workflow_types,
                 :seed,
                 :policies
  end

  class Configuration
    include Configurable
    include Logging
    using TimeExtensions unless defined? JRUBY_VERSION

    attr_accessor :filename

    def initialize(filename)
      @filename = filename
    end

    def end_time
      @start_time + @duration
    end

    def validate
      # convert datetimes and integers into floats
      @start_time        = @start_time.to_f
      @duration          = @duration.to_f
      @warmup_duration   = @warmup_duration.to_f
      @cooldown_duration = @cooldown_duration.to_f
      @cooldown_duration = 10 if @cooldown_duration.nil?

      @kpi_customization ||= {}

      # if @request_generation is not defined in the configuration file, use request_gen
      if @request_generation.nil?
        @request_generation = @request_gen
      else
        @request_generation.each do |k, v|
          @request_generation[k] = v.gsub('<pwd>', File.expand_path(File.dirname(@filename)))
        end
      end

      @custom_stats = [] unless defined? @custom_stats
      @seeds = {} unless defined? @seeds

      IceNine.deep_freeze(@constraints)
      IceNine.deep_freeze(@customers)
      IceNine.deep_freeze(@custom_stats)
      IceNine.deep_freeze(@data_centers)
      IceNine.deep_freeze(@clusters)
      IceNine.deep_freeze(@federation)
      IceNine.deep_freeze(@duration)
      IceNine.deep_freeze(@evaluation)
      IceNine.deep_freeze(@kpi_customization)
      IceNine.deep_freeze(@latency_models)
      IceNine.deep_freeze(@seeds)
      IceNine.deep_freeze(@warmup_duration)
      IceNine.deep_freeze(@workflow_types)
    end

    def self.load_from_file(filename, validate: true)
      raise ArgumentError, "File #{filename} does not exist!" unless File.exist?(filename)

      conf = Configuration.new(filename)
      conf.instance_eval(File.new(filename, 'r').read)
      conf.validate if validate
      conf
    end

    def set_start(time)
      @start_time = time
    end

    def set_rgen(filename, dist = nil)
      if dist.nil?
        @request_generation[:filename] = filename
      else
        @request_gen = dist
      end
    end
  end
end