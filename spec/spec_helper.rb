require File.expand_path('../../config/setup_load_paths', __FILE__)

# Sinatra acts a bit different in the test vs dev environments
# in a way that made one of our tests a false positive. We want
# to force the environment to dev here so it's closer to how
# end-users will run stuff.
# Note: this is needed for the build on Travis CI since it has
# RACK_ENV=test by default.
ENV['RACK_ENV'] = 'development'

module TestHelpers
  def without_indentation(heredoc)
    leading_whitespace = heredoc.split("\n").first[/\A\s+/]
    heredoc.gsub(/^#{leading_whitespace}/, '')
  end

  def write_file(filename, contents)
    File.open(filename, 'w') { |f| f.write(contents) }
  end

  def response_version_configured?(config)
    config.response_version_for(nil)
  rescue
    false
  else
    true
  end

  def new_endpoint(hash = {})
    hash = {
      'name' => "the-name",
      'route' => nil,
      'method' => 'GET',
      'definitions' => []
    }.merge(hash)

    Interpol::Endpoint.new(hash)
  end

  module ClassMethods
    def let_without_indentation(name, &block)
      let(name) { without_indentation(block.call) }
    end
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.filter_run :focus
  config.run_all_when_everything_filtered = true

  config.default_formatter = 'doc' if config.files_to_run.one?
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.include TestHelpers
  config.extend TestHelpers::ClassMethods

  config.before do
    if defined?(Interpol::Configuration)
      # clear global state between examples
      Interpol::Configuration.instance_variable_set(:@default, nil)
    end
  end
end

RSpec.shared_context "clean endpoint directory", :clean_endpoint_dir do
  let(:dir) { './spec/fixtures/tmp' }

  before(:example) do
    # ensure the directory is empty
    FileUtils.rm_rf dir
    FileUtils.mkdir_p dir
  end
end
