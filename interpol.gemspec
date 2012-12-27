# -*- encoding: utf-8 -*-
require File.expand_path('../lib/interpol/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Myron Marston"]
  gem.email         = ["myron.marston@gmail.com"]
  gem.description   = %q{Interpol is a toolkit for working with API endpoint definition files, giving you a stub app, a schema validation middleware, and browsable documentation.}
  gem.summary       = %q{Interpol is a toolkit for policing your HTTP JSON interface.}
  gem.homepage      = ""

  gem.files         = %w(README.md LICENSE Gemfile Rakefile) +
                      Dir.glob("lib/**/*.rb") + Dir.glob("lib/interpol/documentation_app/**/*")

  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})

  gem.name          = "interpol"
  gem.require_paths = ["lib"]
  gem.version       = Interpol::VERSION

  gem.add_dependency 'rack'
  gem.add_dependency 'json-schema', '~> 1.0.10'
  gem.add_dependency 'nokogiri', '~> 1.5'

  gem.add_development_dependency 'rspec', '~> 2.11'
  gem.add_development_dependency 'rspec-fire', '~> 0.4'
  gem.add_development_dependency 'simplecov', '~> 0.6'
  gem.add_development_dependency 'tailor', '~> 0'
  gem.add_development_dependency 'rake', '~> 0.9.2.2'
  gem.add_development_dependency 'rack-test', '0.6.1'
  gem.add_development_dependency 'hashie', '~> 1.2'
end

