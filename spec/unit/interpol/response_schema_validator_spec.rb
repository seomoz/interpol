require 'fast_spec_helper'
require 'rack/test'
require 'rack/content_length'
require 'interpol/response_schema_validator'

module Interpol
  RSpec.describe ResponseSchemaValidator do
    include Rack::Test::Methods

    def configuration
      lambda do |config|
        allow(config).to receive(:endpoints).and_return(definition_finder)
        config.response_version '1.0' unless response_version_configured?(config)
        config.validate_response_if(&validate_response_if_block) if validate_response_if_block
        config.validation_mode = validation_mode
      end
    end

    attr_accessor :validation_mode, :validate_response_if_block, :definition_finder

    def set_validation_mode(mode)
      self.validation_mode = mode
    end

    def validate_response_if(&block)
      self.validate_response_if_block = block
    end

    let(:closable_body) do
      double(:close => nil).tap do |s|
        allow(s).to receive(:each).and_yield('{"a":"b"}')
      end
    end

    let(:app) do
      self.definition_finder ||= default_definition_finder
      config = configuration
      _closable_body = closable_body
      Rack::Builder.new do
        use Rack::Lint
        use Interpol::ResponseSchemaValidator, &config
        use Rack::ContentLength

        map("/search/200/overview") do
          run lambda { |env|
            [ 200, {'Content-Type' => 'application/json'}, [%|{"a":"b"}|] ]
          }
        end

        map("/search/204/overview") do
          run lambda { |env|
            [ 204, {}, [] ]
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

        map('/not_json') do
          run lambda { |env|
            [ 200, {'Content-Type' => 'test/plain'}, ["stuff"] ]
          }
        end
      end
    end

    let(:validator) { instance_double("Interpol::EndpointDefinition", :validate_data! => nil) }
    let(:endpoint)  { new_endpoint }
    let(:default_definition_finder) { instance_double("Interpol::DefinitionFinder") }

    def stub_lookup(v = validator)
      allow(default_definition_finder).to receive(:find_definition).and_return(v)
    end

    it 'validates the data against the correct versioned endpoint definition' do
      expect(validator).to receive(:validate_data!).with("a" => "b")

      expect(default_definition_finder).to receive(:find_definition).
        with("GET", "/search/200/overview", "response", 200).
        and_return(validator)

      get '/search/200/overview'
    end

    it 'falls back to the default configuration' do
      default_config_called = false
      Interpol.default_configuration do |c|
        c.validate_response_if do
          default_config_called = true
          false
        end
      end

      get '/search/200/overview'
      expect(default_config_called).to be true
    end

    it 'calls the response_version hook with the rack env, the endpoint and the response triplet' do
      allow(endpoint).to receive(:method).and_return(:get)
      allow(endpoint).to receive(:route_matches?).and_return(true)
      self.definition_finder = [endpoint].extend(Interpol::DefinitionFinder)

      yielded_args = nil
      Interpol.default_configuration do |c|
        c.response_version do |*args|
          yielded_args = args
          '1.0'
        end
      end

      expect { get '/search/200/overview' }.to raise_error(NoEndpointDefinitionFoundError)

      expect(yielded_args[0]).to be_a(Hash) # rack env
      expect(yielded_args[1]).to be_a(Interpol::Endpoint)

      response = yielded_args[2]
      expect(response).to be_an(Array)
      expect(response[0]).to eq(200)
      expect(response[1]).to have_key("Content-Type")
      expect(response[2]).to eq([%|{"a":"b"}|])
    end

    it 'yields the env, status, headers and body from the validate_response_if callback' do
      yielded_args = nil
      validate_response_if { |*args| yielded_args = args; false }

      get '/search/200/overview'

      expect(yielded_args[0]).to have_key('rack.version') # env hash
      expect(yielded_args[1]).to eq(200) # status
      expect(yielded_args[2]).to have_key('Content-Type') # headers
      expect(yielded_args[3]).to eq([%|{"a":"b"}|]) # body
    end

    it 'does not validate if the validate_response_if config returns false' do
      validate_response_if { |*args| false }
      expect(validator).not_to receive(:validate_data!)
      expect(default_definition_finder).not_to receive(:find_definition)
      get '/search/200/overview'
    end

    context 'when no validate_response_if callback has been set' do
      it 'does not validate if the response is not 2xx' do
        expect(validator).not_to receive(:validate_data!)
        expect(default_definition_finder).not_to receive(:find_definition)
        get '/not_found'
      end

      it 'does not validate a 204 no content response' do
        expect(validator).not_to receive(:validate_data!)
        expect(default_definition_finder).not_to receive(:find_definition)
        get '/search/204/overview'
      end

      it 'does not validate a non json response' do
        expect(validator).not_to receive(:validate_data!)
        expect(default_definition_finder).not_to receive(:find_definition)
        get '/not_json'
        expect(last_response.status).to eq(200)
      end
    end

    it 'closes the body when done iterating it as per the rack spec' do
      stub_lookup
      expect(closable_body).to receive(:close).once
      get '/closable/body'
    end

    context 'when configured with :error' do
      before { set_validation_mode :error }

      it 'raises an error when the data fails validation' do
        expect(validator).to receive(:validate_data!).and_raise(ValidationError)
        stub_lookup

        expect { get '/search/200/overview' }.to raise_error(ValidationError)
      end

      it 'raises an error when no endpoint definition can be found' do
        allow(validator).to receive(:validate_data!)
        stub_lookup(DefinitionFinder::NoDefinitionFound)

        expect { get '/search/200/overview' }.to raise_error(NoEndpointDefinitionFoundError)
      end

      it 'does not raise an error when the data passes validation' do
        allow(validator).to receive(:validate_data!)
        stub_lookup

        get '/search/200/overview'
      end
    end

    context 'when configured with :warn' do
      let(:warner) { Kernel }
      before { set_validation_mode :warn }

      it 'prints a warning when the data fails validation' do
        expect(validator).to receive(:validate_data!).and_raise(ValidationError)
        stub_lookup

        expect(warner).to receive(:warn).with(/Found.*error.*when validating/)
        get '/search/200/overview'
      end

      it 'prints a warning when no endpoint definition can be found' do
        allow(validator).to receive(:validate_data!)
        stub_lookup(DefinitionFinder::NoDefinitionFound)

        expect(warner).to receive(:warn).with(/No endpoint definition could be found/)
        get '/search/200/overview'
      end

      it 'does not print a warning when the data passes validation' do
        allow(validator).to receive(:validate_data!)
        stub_lookup

        expect(warner).not_to receive(:warn)
        get '/search/200/overview'
      end
    end
  end
end


