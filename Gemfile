source 'https://rubygems.org'

# Specify your gem's dependencies in interpol.gemspec
gemspec

group :extras do
  gem 'debugger' if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby' && RUBY_VERSION == '1.9.3'
  gem 'byebug' if RUBY_VERSION.start_with?('2.')
end

gem 'json-jruby', :platform => 'jruby'
gem 'compass_twitter_bootstrap', :git => 'git://github.com/vwall/compass-twitter-bootstrap.git'

gem 'json', :platform => 'ruby_18'

gem 'cane', '~> 2.6'

# 1.6 won't install on JRuby or 1.8.7 :(.
gem 'nokogiri', '~> 1.5.10'

