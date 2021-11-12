# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sisfc/version'

Gem::Specification.new do |spec|
  spec.name          = 'sisfc'
  spec.version       = SISFC::VERSION
  spec.authors       = ['Mauro Tortonesi']
  spec.email         = ['mauro.tortonesi@unife.it']
  spec.description   = %q{KubeTwin, a Kubernetes Simulator}
  spec.summary       = %q{A Kubernetes Simulator written in Ruby}
  spec.homepage      = 'https://https://github.com/DSG-UniFE/KubeTwin'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/).reject{|x| x == '.gitignore' }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'as-duration', '~> 0.1.1'
  spec.add_dependency 'erv', '~> 0.3.5'
  spec.add_dependency 'ice_nine', '~> 0.11.2'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'dotenv', '~> 2.7.6'
  spec.add_development_dependency 'rake', '~> 13.0.1'
  spec.add_development_dependency 'minitest', '~> 5.14.2'
  spec.add_development_dependency 'minitest-reporters', '~> 1.4.2'
  spec.add_development_dependency 'minitest-spec-context', '~> 0.0.4'
  spec.add_development_dependency 'dry-validation', '~> 1.7'
  spec.add_development_dependency 'dry-auto_inject', '~> 0.8.0'
end
