# frozen_string_literal: true

require "minitest_helper"
require "characterization_helper"

# Every maintained example must still behave exactly as recorded in
# spec/fixtures/characterization.json -- see spec/characterization_helper.rb.
# Counts, the allocation and the completion digest must match exactly;
# floating-point metrics to a relative 1e-9, since math libraries may differ
# in the last bits across platforms. Examples driven by MDN models
# (Characterization::MDN_EXAMPLES) inherit LibTorch's platform differences:
# their metrics must match to a relative 1e-6, and their completion digest,
# which hashes completion times to the microsecond, isn't compared.
describe "characterization" do
  expected = JSON.parse(File.read(Characterization::FIXTURE))

  # Stepping through a run with KUBETWIN::Twin must not change it either.
  Characterization::EXAMPLES.product([nil, 30.0]).each do |example, step|
    it "#{example} behaves as recorded#{" when run in #{step.to_i} s steps" if step}" do
      actual = Characterization.fingerprint(example, step: step)
      wanted = expected.fetch(example)

      mdn = Characterization::MDN_EXAMPLES.include?(example)
      %w[result mean_ttr replica_spreading].each do |metric|
        _(actual[metric]).must_be_within_epsilon wanted[metric], mdn ? 1e-6 : 1e-9
      end
      _(actual["allocation"]).must_equal wanted["allocation"]
      _(actual["events"]).must_equal wanted["events"]
      _(actual["completions"]).must_equal wanted["completions"]
      _(actual["completions_digest"]).must_equal wanted["completions_digest"] unless mdn
    end
  end
end
