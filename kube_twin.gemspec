lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kube_twin/version"

Gem::Specification.new do |spec|
  spec.name = "kube_twin"
  spec.version = KUBETWIN::VERSION
  spec.authors = ["DS@Unife"]
  spec.email = ["ds@unife.it"]
  spec.description = "KubeTwin, a Digital Twin for large-scale Kubernetes installations"
  spec.summary = "KubeTwin is a framework for building accurate Digital Twins of large-scale Kubernetes installations, designed as a tool for spearheading research on smart orchestration in the Compute Continuum and written in the Ruby programming language."
  spec.homepage = "https://https://github.com/DSG-UniFE/KubeTwin"
  spec.license = "MIT"

  # Floor is 3.3, not the 3.0.2 this used to say. First correction pass
  # (before CI actually ran) only checked zeitwerk's floor (>= 3.2) and
  # missed that torch-rb 0.26.0, dry-configurable 1.4.0, and
  # dry-auto_inject 1.2.1 all independently require >= 3.3 -- the real
  # floor is the max across the whole resolved dependency graph, not just
  # the one gem that happened to get checked first. Confirmed by actually
  # running `bundle lock` in CI on 3.2 and watching it fail to resolve
  # (see .github/workflows/ci.yml and its run history) -- the same mistake
  # the old 3.0.2 claim made (ruby -c syntax-checked, never bundle
  # installed) almost repeated itself here. Ceiling is left open since
  # nothing here is known to break on newer Rubies yet. Bump the floor
  # only after actually testing on the version being dropped -- with a
  # real `bundle install`, not just a syntax check.
  spec.required_ruby_version = ">= 3.3"

  spec.files = `git ls-files`.split($/).reject { |x| x == ".gitignore" }
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ice_nine", ">= 0.11.2"
  spec.add_dependency "zeitwerk", ">= 2.6"
  spec.add_dependency "mhl", ">= 0.3.0"
  spec.add_dependency "rumale-ensemble", ">= 2.2"
  spec.add_dependency "torch-rb", ">= 0.26.0"

  spec.add_development_dependency "dotenv", ">= 3.2"
  spec.add_development_dependency "dry-auto_inject", ">= 1.2.1"
  spec.add_development_dependency "dry-validation", ">= 1.11.1"
  spec.add_development_dependency "minitest", ">= 6.0.6"
  spec.add_development_dependency "minitest-reporters", ">= 1.8"
  spec.add_development_dependency "minitest-spec-context", ">= 0.0.5"
  spec.add_development_dependency "rake", ">= 13.4.2"
  spec.add_development_dependency "standard", ">= 1.40"
end
