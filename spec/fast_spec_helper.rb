# Note: this file is purposefully minimal. Load as little as possible here.
require 'rspec/fire'

module TestHelpers
  def without_indentation(heredoc)
    leading_whitespace = heredoc.split("\n").first[/\A\s+/]
    heredoc.gsub(/^#{leading_whitespace}/, '')
  end

  def write_file(filename, contents)
    File.open(filename, 'w') { |f| f.write(contents) }
  end

  module ClassMethods
    def let_without_indentation(name, &block)
      let(name) { without_indentation(block.call) }
    end
  end
end

RSpec.configure do |c|
  c.include RSpec::Fire
  c.treat_symbols_as_metadata_keys_with_true_values = true
  c.filter_run :f
  c.run_all_when_everything_filtered = true
  c.debug = (RUBY_ENGINE == 'ruby' && RUBY_VERSION == '1.9.3')
  c.include TestHelpers
  c.extend TestHelpers::ClassMethods
end

shared_context "clean endpoint directory", :clean_endpoint_dir do
  let(:dir) { './spec/fixtures/tmp' }

  before(:each) do
    # ensure the directory is empty
    FileUtils.rm_rf dir
    FileUtils.mkdir_p dir
  end
end
