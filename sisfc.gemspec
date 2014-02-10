# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sisfc/version'

Gem::Specification.new do |spec|
  spec.name          = 'sisfc'
  spec.version       = SISFC::VERSION
  spec.authors       = ['Mauro Tortonesi']
  spec.email         = ['mauro.tortonesi@unife.it']
  spec.description   = %q{Simulator for IT Services in Federated Clouds}
  spec.summary       = %q{A simulator for business-driven IT management research capable of evaluating IT service component placement in federated Cloud environments}
  spec.homepage      = 'https://github.com/mtortonesi/sisfc'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/).reject{|x| x == '.gitignore' }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '~> 3.0.0'
  spec.add_dependency 'erv', '~> 0.0.2'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'
end
