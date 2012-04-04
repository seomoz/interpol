# -*- encoding: utf-8 -*-
require File.expand_path('../lib/interpol/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Myron Marston"]
  gem.email         = ["myron.marston@gmail.com"]
  gem.description   = %q{Interpol is a toolkit for working with API endpoint definition files, giving you a stub app, a schema validation middleware, and browsable documentation.}
  gem.summary       = %q{Interpol is a toolkit for policing your HTTP JSON interface.}
  gem.homepage      = ""

  gem.files         = %w(README.md License Gemfile Rakefile) + Dir.glob("lib/**/*.rb")
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})

  gem.name          = "interpol"
  gem.require_paths = ["lib"]
  gem.version       = Interpol::VERSION

  gem.add_dependency 'sinatra', '>= 1.3.2', '< 2.0.0'
  gem.add_dependency 'json-schema', '~> 1.0.5'

  gem.add_development_dependency 'rspec', '~> 2.9'
  gem.add_development_dependency 'rspec-fire', '~> 0.4'
  gem.add_development_dependency 'simplecov', '~> 0.6'
  gem.add_development_dependency 'cane', '~> 1.2'
  gem.add_development_dependency 'rake', '~> 0.9.2.2'
  gem.add_development_dependency 'rack-test', '0.6.1'
end
