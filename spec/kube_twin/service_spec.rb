# frozen_string_literal: true

require "minitest_helper"

# Service only needs a pod's label to group it.
ServiceSpecPod = Struct.new(:label, :id)

describe KUBETWIN::Service do
  def service_with_pods(random: nil)
    service = KUBETWIN::Service.new("reviews", "reviews", :random, random: random)
    10.times { |i| service.assignPod(ServiceSpecPod.new("reviews", i)) }
    service
  end

  it "draws :random load balancing from the generator it was given" do
    picks = Array.new(2) do
      service = service_with_pods(random: Random.new(7))
      Array.new(20) { service.get_pod("reviews").id }
    end

    _(picks.first).must_equal picks.last
    _(picks.first.uniq.size).must_be :>, 1
  end

  it "falls back to Ruby's global generator without one" do
    service = service_with_pods

    _(service_with_pods.get_pod("reviews").label).must_equal "reviews"
    _(service.get_pod("missing")).must_be_nil
  end
end
