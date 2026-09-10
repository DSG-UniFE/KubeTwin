# frozen_string_literal: true

require 'zeitwerk'

# VERSION is read by kube_twin.gemspec itself (before Bundler/RubyGems are
# necessarily set up), so it's kept outside the autoloader entirely rather
# than folded into the KUBETWIN namespace below.
require_relative './kube_twin/version'

module KUBETWIN
end

# Autoloading setup. Every class under lib/kube_twin/ used to need an
# explicit require_relative from whichever file used it first -- easy to
# get wrong (see git history for more than one "forgot to require the file
# that defines this constant" bug). Zeitwerk removes that whole class of
# bug: reference KUBETWIN::Anything anywhere, and the file that defines it
# loads automatically, in any order, including in spec files that just
# `require 'kube_twin'` and go straight to using a class.
loader = Zeitwerk::Loader.new
loader.tag = 'kube_twin'

# Push lib/kube_twin/ itself (not lib/), and attach it directly to the
# already-open KUBETWIN module above -- lib/ also contains lib/mqtt-clients/,
# a standalone companion toolkit (its own README/Gemfile, non-namespaced
# scripts) that was never part of this gem's require chain and shouldn't be
# swept into it now.
loader.push_dir(File.expand_path('kube_twin', __dir__), namespace: KUBETWIN)

# lib/kube_twin/version.rb is required directly above, and defines VERSION
# (a constant, not a class/module) rather than the Version Zeitwerk would
# expect from the filename -- excluded rather than fought.
loader.ignore(File.expand_path('kube_twin/version.rb', __dir__))

# lib/kube_twin/support/dsl_helper.rb monkeypatches core Module with
# dsl_accessor; it doesn't define a namespaced KUBETWIN::Support::* constant
# at all, and configuration.rb needs it loaded eagerly (dsl_accessor is
# called directly in a module body, not deferred to runtime), so it keeps
# its own explicit require_relative and stays out of the autoloader.
loader.ignore(File.expand_path('kube_twin/support', __dir__))

# lib/kube_twin/test_fix.rb is a leftover code fragment, not a real file
# (it doesn't even define a class/module) -- see the roadmap's "run
# artifacts / leftover files" finding. Excluded so it can't ever be treated
# as an autoload target for a KUBETWIN::TestFix that doesn't exist. Safe to
# delete outright whenever it's convenient; this doesn't depend on that.
loader.ignore(File.expand_path('kube_twin/test_fix.rb', __dir__))

# A handful of filenames don't camelize to their real class/module name --
# mostly acronyms (K-prefixed optimizer classes, MDN, RF2) plus a few files
# named after what they do rather than the single class they define
# (generator.rb, evaluation.rb, logger.rb). Rather than rename files with
# git history and other branches' pending work touching them, tell Zeitwerk
# the real name for each.
loader.inflector.inflect(
  'koptimizer'                    => 'KOptimizer',
  'koptimizer_acm'                => 'KOptimizerACM',
  'koptimizer_acm2'               => 'KOptimizerACM2',
  'koptimizer_acm2_surrogate'     => 'KOptimizerACM2Surrogate',
  'koptimizer_acm2_surrogate_rf2' => 'KOptimizerACM2SurrogateRF2',
  'koptimizer_multiobjective'     => 'KOptimizerMultiobjective',
  'ksimulation'                   => 'KSimulation',
  'mdn'                           => 'MDN',
  'random_forest_surrogate_rf2'   => 'RandomForestSurrogateRF2',
  'generator'                     => 'RequestGeneratorR', # lib/kube_twin/generator.rb
  'evaluation'                    => 'Evaluator',         # lib/kube_twin/evaluation.rb
  'logger'                        => 'Logging'            # lib/kube_twin/logger.rb
)

loader.setup
