lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kube_twin/version'

Gem::Specification.new do |spec|
  spec.name          = 'kube_twin'
  spec.version       = KUBETWIN::VERSION
  spec.authors       = ['DS@Unife']
  spec.email         = ['ds@unife.it']
  spec.description   = 'KubeTwin, a Digital Twin for large-scale Kubernetes installations'
  spec.summary       = 'KubeTwin is a framework for building accurate Digital Twins of large-scale Kubernetes installations, designed as a tool for spearheading research on smart orchestration in the Compute Continuum and written in the Ruby programming language.'
  spec.homepage      = 'https://https://github.com/DSG-UniFE/KubeTwin'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/).reject { |x| x == '.gitignore' }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'ice_nine', '>= 0.11.2'
  spec.add_dependency 'zeitwerk', '>= 2.6'
  spec.add_dependency 'mhl', '>= 0.3.0'
  spec.add_dependency 'rumale-ensemble', '>= 2.2'
  spec.add_dependency 'torch-rb', '>= 0.26.0'

  spec.add_development_dependency 'dotenv', '>= 3.2'
  spec.add_development_dependency 'dry-auto_inject', '>= 1.2.1'
  spec.add_development_dependency 'dry-validation', '>= 1.11.1'
  spec.add_development_dependency 'minitest', '>= 6.0.6'
  spec.add_development_dependency 'minitest-reporters', '>= 1.8'
  spec.add_development_dependency 'minitest-spec-context', '>= 0.0.5'
  spec.add_development_dependency 'rake', '>= 13.4.2'
end
