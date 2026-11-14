# frozen_string_literal: true

module KUBETWIN
  # How a federation divides a service's replicas among clusters (as
  # Karmada's Divided replica scheduling does with static weights), as a
  # pure function:
  #
  #   ReplicaDivision.divide(5, {rome: 2, milan: 1}, capacity: {rome: 10, milan: 10})
  #   # => #<ReplicaDivision::Result counts={rome: 3, milan: 2}, unschedulable=0>
  #
  # 1. Spread: with max_clusters, only that many clusters (the heaviest)
  #    take part.
  # 2. The total is apportioned by weight with the largest remainder method
  #    (ties to the cluster listed first).
  # 3. With min_clusters, the heaviest min_clusters clusters get at least one
  #    replica each, taken from the clusters with the most.
  # 4. A cluster can't take more than its capacity: the excess goes to the
  #    others with room, by weight. What fits nowhere is unschedulable.
  module ReplicaDivision
    Result = Data.define(:counts, :unschedulable)

    module_function

    # weights: {cluster => weight > 0} (the eligible clusters, in order of
    # preference for ties); capacity: {cluster => replicas it can host},
    # missing = unlimited.
    def divide(total, weights, capacity: {}, min_clusters: nil, max_clusters: nil)
      raise ArgumentError, "total must be a non-negative integer" unless total.is_a?(Integer) && total >= 0
      raise ArgumentError, "weights must be positive" unless weights.values.all? { |w| w.is_a?(Numeric) && w.positive? }

      clusters = weights.keys
      clusters = clusters.sort_by.with_index { |c, i| [-weights[c], i] }.first(max_clusters).sort_by { |c| weights.keys.index(c) } if max_clusters
      return Result.new(counts: {}, unschedulable: total) if clusters.empty?

      counts = apportion(total, clusters.to_h { |c| [c, weights[c]] })
      spread_to(counts, clusters, weights, min_clusters) if min_clusters
      unschedulable = fit(counts, weights, capacity)
      Result.new(counts:, unschedulable:)
    end

    # Largest remainder (Hamilton) apportionment.
    def apportion(total, weights)
      sum = weights.values.sum.to_f
      quotas = weights.transform_values { |w| total * w / sum }
      counts = quotas.transform_values(&:floor)
      left = total - counts.values.sum
      quotas.keys.sort_by.with_index { |c, i| [-(quotas[c] - counts[c]), i] }.first(left).each { |c| counts[c] += 1 }
      counts
    end

    def spread_to(counts, clusters, weights, min_clusters)
      wanted = clusters.sort_by.with_index { |c, i| [-weights[c], i] }.first(min_clusters)
      wanted.each do |cluster|
        next if counts[cluster].positive?

        donor = counts.select { |_, n| n > 1 }.max_by { |c, n| [n, -clusters.index(c)] }&.first
        break unless donor

        counts[donor] -= 1
        counts[cluster] += 1
      end
    end

    # Moves replicas over capacity to clusters with room, by weight.
    # Returns how many fit nowhere.
    def fit(counts, weights, capacity)
      excess = 0
      counts.each_key do |cluster|
        limit = capacity.fetch(cluster, Float::INFINITY)
        next unless counts[cluster] > limit

        excess += counts[cluster] - limit
        counts[cluster] = limit
      end
      while excess.positive?
        room = counts.keys.select { |c| counts[c] < capacity.fetch(c, Float::INFINITY) }
        break if room.empty?

        share = apportion(excess, room.to_h { |c| [c, weights[c]] })
        moved = 0
        share.each do |cluster, n|
          take = [n, capacity.fetch(cluster, Float::INFINITY) - counts[cluster]].min
          counts[cluster] += take
          moved += take
        end
        excess -= moved
        break if moved.zero?
      end
      excess
    end
  end
end
