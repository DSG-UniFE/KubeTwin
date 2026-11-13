# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

# Every maintained example must still behave exactly as recorded in
# spec/fixtures/characterization.json -- see spec/characterization_helper.rb.
# Counts, the allocation and the completion digest must match exactly;
# floating-point metrics to a relative 1e-9, since math libraries may differ
# in the last bits across platforms.
describe "characterization" do
  expected = JSON.parse(File.read(Characterization::FIXTURE))

  Characterization::EXAMPLES.each do |example|
    it "#{example} behaves as recorded" do
      actual = Characterization.fingerprint(example)
      wanted = expected.fetch(example)

      %w[result mean_ttr replica_spreading].each do |metric|
        _(actual[metric]).must_be_within_epsilon wanted[metric], 1e-9
      end
      _(actual["allocation"]).must_equal wanted["allocation"]
      _(actual["events"]).must_equal wanted["events"]
      _(actual["completions"]).must_equal wanted["completions"]
      _(actual["completions_digest"]).must_equal wanted["completions_digest"]
    end
  end
end
