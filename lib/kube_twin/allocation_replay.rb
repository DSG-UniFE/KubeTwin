# frozen_string_literal: true

require 'json'

module KUBETWIN
  class AllocationReplay
    def initialize(configuration)
      @configuration = configuration
      @cluster_names = KUBETWIN::KSimulation.create_cluster_configuration(configuration).keys.map(&:to_s)
      @replica_sets = configuration.replica_sets
    end

    def load_from_file(path, solution_id: nil)
      data = JSON.parse(File.read(path))
      allocation = extract_allocation(data, solution_id)
      build_simulation_inputs(allocation)
    end

    private

    def extract_allocation(data, solution_id)
      if data.is_a?(Array)
        solution = if solution_id.nil?
                     data.first
                   else
                     data.find { |entry| entry['solution_id'].to_i == solution_id.to_i }
                   end
        raise ArgumentError, "Solution #{solution_id} not found" if solution.nil?

        allocation = solution['microservice_allocation']
      else
        allocation = data['microservice_allocation'] || data
      end

      raise ArgumentError, 'Allocation file does not contain microservice_allocation' unless allocation.is_a?(Hash)

      allocation
    end

    def build_simulation_inputs(allocation)
      rss = deep_dup_replica_sets
      replicas_by_selector = Hash.new(0)
      replicas_mapping = []

      selector_order.each do |selector|
        cluster_counts = allocation.fetch(selector) do
          raise ArgumentError, "Missing allocation for microservice #{selector}"
        end

        ordered_cluster_ids = []
        @cluster_names.each_with_index do |cluster_name, cluster_idx|
          count = cluster_counts.fetch(cluster_name, cluster_counts.fetch(cluster_name.to_sym, 0)).to_i
          count.times { ordered_cluster_ids << cluster_idx }
        end

        replicas_by_selector[selector] = ordered_cluster_ids.length
        replicas_mapping.concat(ordered_cluster_ids)
      end

      apply_replica_counts!(rss, replicas_by_selector)
      [rss, replicas_mapping]
    end

    def selector_order
      @selector_order ||= @replica_sets.values.map { |conf| conf[:selector].to_s }
    end

    def deep_dup_replica_sets
      @replica_sets.each_with_object({}) do |(name, conf), duped|
        duped[name] = conf.dup
      end
    end

    def apply_replica_counts!(rss, replicas_by_selector)
      selector_counts = Hash.new(0)
      rss.each do |_name, conf|
        selector = conf[:selector].to_s
        selector_counts[selector] += 1
      end

      selector_counts.each do |selector, count|
        next if count == 1

        raise ArgumentError, "Multiple replica sets found for selector #{selector}; allocation replay supports one replica set per microservice"
      end

      rss.each do |_name, conf|
        selector = conf[:selector].to_s
        conf[:replicas] = replicas_by_selector.fetch(selector, 0)
      end
    end
  end
end
