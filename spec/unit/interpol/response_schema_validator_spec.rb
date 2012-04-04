require 'fast_spec_helper'
require 'rack/test'
require 'rack/content_length'
require 'interpol/response_schema_validator'

module Interpol
  describe ResponseSchemaValidator do
    include Rack::Test::Methods

    def configuration
      lambda do |config|
        config.stub(endpoints: definition_finder)
        config.api_version '1.0' unless api_version_configured?(config)
        config.validate_if(&validate_if_block) if validate_if_block
        config.validation_mode = validation_mode
      end
    end

    attr_accessor :validation_mode, :validate_if_block
    def set_validation_mode(mode)
      self.validation_mode = mode
    end

    def validate_if(&block)
      self.validate_if_block = block
    end

    let(:closable_body) do
      stub(close: nil).tap do |s|
        s.stub(:each).and_yield('{"a":"b"}')
      end
    end

    let(:app) do
      config = configuration
      _closable_body = closable_body
      Rack::Builder.new do
        use Interpol::ResponseSchemaValidator, &config
        use Rack::ContentLength

        map('/search/17/overview') do
          run lambda { |env|
            [ 200, {'Content-Type' => 'application/json'}, [%|{"a":"b"}|] ]
          }
        end

        map('/closable/body') do
          run lambda { |env|
            [ 200, { 'Content-Type' => 'application/json' }, _closable_body ]
          }
        end

        map('/not_found') do
          run lambda { |env|
            [ 404, {'Content-Type' => 'application/json'}, [%|{"message":"Not Found"}|] ]
          }
        end
      end
    end

    let(:validator) { fire_double("Interpol::EndpointDefinition", validate_data!: nil) }
    let(:definition_finder) { fire_double("Interpol::DefinitionFinder") }

    def stub_lookup(v = validator)
      definition_finder.stub(find_definition: v)
    end

    it 'validates the data against the correct versioned endpoint definition' do
      validator.should_receive(:validate_data!).with("a" => "b")

      definition_finder.should_receive(:find_definition).
        with(method: "GET", path: "/search/17/overview", version: "1.0").
        and_return(validator)

      get '/search/17/overview'
    end

    it 'falls back to the default configuration' do
      Interpol.default_configuration { |c| c.api_version '2.4' }

      definition_finder.should_receive(:find_definition).
        with(method: "GET", path: "/search/17/overview", version: "2.4").
        and_return(validator)

      get '/search/17/overview'
    end

    it 'yields the env, status, headers and body from the validate_if callback' do
      yielded_args = nil
      validate_if { |*args| yielded_args = args; false }

      get '/search/17/overview'

      yielded_args[0].should have_key('rack.version') # env hash
      yielded_args[1].should eq(200) # status
      yielded_args[2].should have_key('Content-Type') # headers
      yielded_args[3].should eq([%|{"a":"b"}|]) # body
    end

    it 'does not validate if the validate_if config returns false' do
      validate_if { |*args| false }

      validator.should_not_receive(:validate_data!)
      definition_finder.should_not_receive(:find_definition)
      get '/search/17/overview'
    end

    it 'does not validate if the response is not 2xx when no validate_if callback has been set' do
      validator.should_not_receive(:validate_data!)
      definition_finder.should_not_receive(:find_definition)
      get '/not_found'
    end

    it 'closes the body when done interating it as per the rack spec' do
      stub_lookup
      #validator.stub(:validate_data!)
      closable_body.should_receive(:close).once
      get '/closable/body'
    end

    context 'when configured with :error' do
      before { set_validation_mode :error }

      it 'raises an error when the data fails validation' do
        validator.should_receive(:validate_data!).and_raise(ValidationError)
        stub_lookup

        expect { get '/search/17/overview' }.to raise_error(ValidationError)
      end

      it 'raises an error when no endpoint definition can be found' do
        validator.stub(:validate_data!)
        stub_lookup(nil)

        expect { get '/search/17/overview' }.to raise_error(NoEndpointDefinitionFoundError)
      end

      it 'does not raise an error when the data passes validation' do
        validator.stub(:validate_data!)
        stub_lookup

        get '/search/17/overview'
      end
    end

    context 'when configured with :warn' do
      let(:warner) { Kernel }
      before { set_validation_mode :warn }

      it 'prints a warning when the data fails validation' do
        validator.should_receive(:validate_data!).and_raise(ValidationError)
        stub_lookup

        warner.should_receive(:warn).with(/Found.*error.*when validating/)
        get '/search/17/overview'
      end

      it 'prints a warning when no endpoint definition can be found' do
        validator.stub(:validate_data!)
        stub_lookup(nil)

        warner.should_receive(:warn).with(/No endpoint definition could be found/)
        get '/search/17/overview'
      end

      it 'does not print a warning when the data passes validation' do
        validator.stub(:validate_data!)
        stub_lookup

        warner.should_not_receive(:warn)
        get '/search/17/overview'
      end
    end
  end
end


