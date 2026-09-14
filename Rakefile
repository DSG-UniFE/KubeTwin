require 'bundler/gem_tasks'

require 'rake/testtask'
require 'standard/rake'

Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList['spec/**/*_spec.rb']
  # t.verbose = true
  t.warning = false
end

# task(default: :test)
