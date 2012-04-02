# -*- encoding: utf-8 -*-
require File.expand_path('../lib/interpol/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Myron Marston"]
  gem.email         = ["myron.marston@gmail.com"]
  gem.description   = %q{Interpol is a toolkit for working with API endpoint definition files, giving you a stub app, a schema validation middleware, and browsable documentation.}
  gem.summary       = %q{Police your HTTP JSON interface with interpol.}
  gem.homepage      = ""

  gem.files         = %w(README.md) + Dir.glob("lib/**/*.rb")
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})

  gem.name          = "interpol"
  gem.require_paths = ["lib"]
  gem.version       = Interpol::VERSION
end
