# frozen_string_literal: true

require 'minitest_helper'
require 'kube_twin/latency_manager'

# Locations: 0 = hub (cluster1), 1 and 2 = edges. Values are one-way latencies
# in seconds, as KSimulation passes them (half the configured RTT).
describe KUBETWIN::LatencyManagerFederation do
  let(:models) { [{ src: 0, dst: 1, value: 0.015 }, { src: 0, dst: 2, value: 0.025 }] }
  let(:intra) { { mean: 0.002, sd: 0.0 } }

  def manager(models, **opts)
    KUBETWIN::LatencyManagerFederation.new(models, seed: 1, intra_cluster: intra, jitter_sd: 0.0,
                                                   min_latency: 1E-4, **opts)
  end

  it 'uses the configured value between clusters by default' do
    _(manager(models).sample_latency_between(0, 1)).must_be_close_to 0.015, 1E-9
    _(manager(models).sample_latency_between(2, 0)).must_be_close_to 0.025, 1E-9
  end

  it 'routes edge to edge through the hub' do
    _(manager(models).sample_latency_between(1, 2)).must_be_close_to 0.040, 1E-9
  end

  it 'uses the intra-cluster latency inside a cluster' do
    _(manager(models).sample_latency_between(1, 1)).must_be_close_to 0.002, 1E-9
    _(manager([]).sample_latency_between(0, 0)).must_be_close_to 0.002, 1E-9
  end

  it 'charges round_trips_per_call times the one-way latency plus the local hop' do
    m = manager(models, round_trips_per_call: 2)
    _(m.sample_latency_between(0, 1)).must_be_close_to 2 * 0.015 + 0.002, 1E-9
    _(m.sample_latency_between(1, 2)).must_be_close_to 2 * 0.040 + 0.002, 1E-9
    _(m.sample_latency_between(2, 2)).must_be_close_to 0.002, 1E-9
  end

  it 'raises when a link to the hub is missing' do
    m = manager([{ src: 0, dst: 1, value: 0.015 }])
    _(-> { m.sample_latency_between(0, 2) }).must_raise RuntimeError
    _(-> { m.sample_latency_between(1, 2) }).must_raise RuntimeError
  end
end
