# frozen_string_literal: true

module KUBETWIN
  # Shared pure encoding/decoding helpers used by the KOptimizer* family
  # (koptimizer.rb, koptimizer_acm.rb, koptimizer_acm2.rb,
  # koptimizer_acm2_surrogate.rb, koptimizer_acm2_surrogate_rf2.rb,
  # koptimizer_multiobjective.rb). Before this extraction each class carried
  # its own copy-pasted version of these four methods; one of the copies
  # (koptimizer_acm.rb) had silently drifted and mutated its caller's rss
  # hash instead of working on a deep copy of it. Pulling them out into one
  # place means there is exactly one implementation to test and keep in
  # sync, instead of six.
  #
  # Every method here is a pure function: no instance state, no simulation,
  # no I/O. Callers pass in whatever state they hold as instance variables;
  # each KOptimizer* class's own method of the same name is now a thin
  # wrapper delegating to the version here.
  module VectorCodec
    module_function

    # Deep-copies +rss+ (a replica-set-name => attributes hash) and applies
    # the first +n_ms+ elements of +x+ as replica counts, in the key order
    # +rss+ already has. Returns [updated_rss, replicas_per_ms_hash].
    #
    # The deep copy matters: rss's values are themselves hashes, and the
    # caller's original replica_sets must not be mutated by this call.
    def encode_replicas_set(rss, n_ms, x)
      rss = rss.each_with_object({}) { |(k, v), h| h[k] = v.dup }
      ra = rss.keys.to_a
      replicas_per_ms = {}
      (0...n_ms).each do |sj|
        rss[ra[sj]][:replicas] = x[sj]
        replicas_per_ms[ra[sj]] = x[sj]
      end
      [rss, replicas_per_ms]
    end

    # Decodes the cluster-assignment section of a fixed-size PSO/NSGA-II
    # vector into a flat replicas_mapping array (index = global pod_id,
    # value = cluster_id). Vector layout:
    #   [rep_ms0, ..., rep_ms(n_ms-1),
    #    c_ms0_r0, ..., c_ms0_r(max_replicas-1),
    #    c_ms1_r0, ..., c_ms1_r(max_replicas-1), ...]
    # For each microservice, only the first replica_count[i] cluster
    # assignments in its block of max_replicas are used; the rest is
    # padding and is ignored.
    def decode_cluster_mapping(vector, n_ms, max_replicas)
      replica_counts = vector[0...n_ms]
      cluster_section = vector[n_ms..]
      replicas_mapping = []

      (0...n_ms).each do |ms_idx|
        n_reps = replica_counts[ms_idx]
        block_start = ms_idx * max_replicas
        n_reps.times do |r|
          replicas_mapping << cluster_section[block_start + r]
        end
      end

      replicas_mapping
    end

    # Human-readable label for each dimension of a search vector: n_ms
    # replica-count labels followed by n_ms * max_replicas cluster-
    # assignment labels (see #decode_cluster_mapping for the layout).
    def build_feature_labels(ms_names, max_replicas)
      labels = ms_names.map { |name| "replicas_#{name}" }
      ms_names.each do |name|
        max_replicas.times { |r| labels << "cluster_#{name}_r#{r}" }
      end
      labels
    end

    # Generates +n_candidates+ vectors near +base_vec+ by perturbing each
    # dimension by a small random delta drawn from +rng+ (+/-2), clamped to
    # [mins[i], maxs[i]].
    def generate_nearby_candidates(base_vec, n_candidates, mins, maxs, rng)
      candidates = []

      n_candidates.times do
        perturbed = base_vec.each_with_index.map do |val, i|
          delta = rng.rand(-2..2)
          (val + delta).clamp(mins[i], maxs[i])
        end
        candidates << perturbed
      end

      candidates
    end
  end
end
