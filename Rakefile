#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = %w[--profile --format progress]
  t.ruby_opts  = "-Ispec -rsimplecov_setup"
end

if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby' # MRI only
  require 'cane/rake_task'

  desc "Run cane to check quality metrics"
  Cane::RakeTask.new(:quality) do |cane|
    cane.abc_max = 13
    cane.add_threshold 'coverage/coverage_percent.txt', :==, 100
    cane.style_measure = 100

    cane.abc_exclude = %w[
      Interpol::Endpoint#definitions
    ]
  end
else
  task(:quality) { } # no-op
end

task :default => [:spec, :quality]

desc "Watch Documentation App Compass Files"
task :compass_watch do
  Dir.chdir("lib/interpol/documentation_app") do
    sh "bundle exec compass watch"
  end
end

desc "Import the twitter bootstrap assets from the compass_twitter_bootstrap gem"
task :import_bootstrap_assets do
  require 'bundler'
  Bundler.setup

  # when the gem installed as a :git gem, it has "-" as a separator;
  # when it's installed as a released rubygem, it has "_" as a separator.
  gem_lib_path = $LOAD_PATH.grep(/compass[-_]twitter[-_]bootstrap/).first
  assets = Dir[File.join(gem_lib_path, '..', 'vendor', 'assets', '**')]

  destination_path = File.expand_path("../lib/interpol/documentation_app/public", __FILE__)
  FileUtils.cp_r(assets, destination_path)
end

