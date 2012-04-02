# Note: this file is purposefully minimal. Load as little as possible here.
require 'rspec/fire'

RSpec.configure do |c|
  c.include RSpec::Fire
  c.treat_symbols_as_metadata_keys_with_true_values = true
  c.filter_run :f
  c.run_all_when_everything_filtered = true
end

