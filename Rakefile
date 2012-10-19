#!/usr/bin/env rake
require File.expand_path('../config/setup_load_paths', __FILE__)
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
    cane.style_measure = 100

    cane.abc_exclude = %w[
      Interpol::Configuration#register_default_callbacks
      Interpol::StubApp::Builder#initialize
      Interpol::Configuration#register_built_in_param_parsers
    ]

    cane.style_exclude = %w[
      spec/unit/interpol/sinatra/request_params_parser_spec.rb
    ]
  end

  desc "Checks the spec coverage and fails if it is less than 100%"
  task :check_coverage do
    puts "Checking code coverage..."
    percent = File.read("coverage/coverage_percent.txt").to_f

    if percent < 100
      raise "Failed to achieve 100% code coverage: #{percent}"
    else
      puts "Nice work! Code coverage is still 100%"
    end
  end
else
  task(:quality) { } # no-op
  task(:check_coverage) { } # no-op
end

task :default => [:spec, :quality, :check_coverage]

desc "Watch Documentation App Compass Files"
task :compass_watch do
  Dir.chdir("lib/interpol/documentation_app") do
    sh "bundle exec compass watch"
  end
end

desc "Import the twitter bootstrap assets from the compass_twitter_bootstrap gem"
task :import_bootstrap_assets do
  # when the gem installed as a :git gem, it has "-" as a separator;
  # when it's installed as a released rubygem, it has "_" as a separator.
  gem_lib_path = $LOAD_PATH.grep(/compass[-_]twitter[-_]bootstrap/).first
  assets = Dir[File.join(gem_lib_path, '..', 'vendor', 'assets', '**')]

  destination_path = File.expand_path("../lib/interpol/documentation_app/public", __FILE__)
  FileUtils.cp_r(assets, destination_path)
end

