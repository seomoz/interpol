#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = %w[--profile --format progress]
  t.ruby_opts  = "-Ispec -rsimplecov_setup"
end

if RUBY_ENGINE == 'ruby' # MRI only
  require 'cane/rake_task'

  desc "Run cane to check quality metrics"
  Cane::RakeTask.new(:quality) do |cane|
    cane.abc_max = 12
    cane.add_threshold 'coverage/coverage_percent.txt', :==, 100
    cane.style_measure = 100
  end
else
  task(:quality) { } # no-op
end

task default: [:spec, :quality]
