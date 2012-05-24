begin
  # use `bundle install --standalone' to get this...
  require File.expand_path('../../bundle/bundler/setup', __FILE__)
rescue LoadError
  # fall back to regular bundler if the person hasn't bundled standalone
  require 'bundler'
  Bundler.setup
end

