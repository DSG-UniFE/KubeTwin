source "https://rubygems.org"

# Specify your gem's dependencies in sisfc.gemspec
gemspec

# Development pin: torch-rb compiles against exactly one LibTorch version,
# and CI downloads the LibTorch matching this series (see
# .github/workflows/ci.yml). Gemfile.lock is not committed, so without this
# pin every torch-rb release would break CI. The gemspec's own requirement
# stays open-ended.
gem "torch-rb", "~> 0.27.0"
