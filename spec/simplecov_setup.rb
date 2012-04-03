if RUBY_ENGINE == 'ruby' # MRI only
  require 'simplecov'

  SimpleCov.start do
    add_filter "/spec"
  end

  SimpleCov.at_exit do
    File.open(File.join(SimpleCov.coverage_path, 'coverage_percent.txt'), 'w') do |f|
      f.write SimpleCov.result.covered_percent
    end
    SimpleCov.result.format!
  end
end

