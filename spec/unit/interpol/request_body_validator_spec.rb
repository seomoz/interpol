require 'rack/test'
require 'interpol/request_body_validator'

module Interpol
  RSpec.describe RequestBodyValidator do
    include Rack::Test::Methods

    let_without_indentation(:endpoint_definition_yml) do <<-EOF
      ---
      name: parsed_body
      route: /parsed_body
      method: POST
      definitions:
        - versions: ["1.0"]
          message_type: request
          schema:
            type: object
            properties:
              id:
                type: integer
              name:
                type: string
          examples: []
      EOF
    end

    before do
      Interpol.default_configuration do |config|
        config.endpoints = [Endpoint.new(YAML.load endpoint_definition_yml)]
        config.request_version '1.0'
      end
    end

    def override_config(&block)
      @override_config = block
    end

    let(:app) do
      _override_config = @override_config || Proc.new { }

      Rack::Builder.new do
        use Rack::Lint
        use(Interpol::RequestBodyValidator, &_override_config)
        use Rack::ContentLength

        map('/parsed_body') do
          run lambda { |env|
            body = if env['HTTP_READ_BODY']
              env.fetch('rack.input').read
            else
              parsed = env.fetch('interpol.parsed_body')
              "id: #{parsed.id}; name: #{parsed.name}"
            end

            [ 200, { 'Content-Type' => 'text/plain' }, [body]]
          }
        end
      end
    end

    let(:valid_json_body)   { JSON.dump("id" => 3, "name" => "foo") }
    let(:invalid_json_body) { JSON.dump("id" => "not a number", "name" => "foo") }

    it 'responds with a 400 by default when it fails validation' do
      header 'Content-Type', 'application/json'
      post '/parsed_body', invalid_json_body
      expect(last_response.status).to eq(400)
      expect(last_response.body).to include("validating", "parsed_body")
    end

    it 'uses the configured on_invalid_request_body hook' do
      Interpol.default_configuration do |config|
        config.on_invalid_request_body do |env, error|
          [412, { 'Content-Type' => 'text/plain' }, ["abc"]]
        end
      end

      header 'Content-Type', 'application/json'
      post '/parsed_body', invalid_json_body
      expect(last_response.status).to eq(412)
      expect(last_response.body).to eq("abc")
    end

    it 'makes the parsed body object available as `interpol.parsed_body`' do
      header 'Content-Type', 'application/json'
      post '/parsed_body', valid_json_body
      expect(last_response.body).to eq("id: 3; name: foo")
    end

    it 'allows the default config to be overriden' do
      Interpol.default_configuration do |config|
        config.request_version '2000.0'
      end

      override_config do |config|
        config.request_version '1.0'
      end

      header 'Content-Type', 'application/json'
      post '/parsed_body', valid_json_body
      expect(last_response.body).to eq("id: 3; name: foo")
    end

    it 'rewinds the input stream after reading it' do
      header 'Read-Body', 'true'
      header 'Content-Type', 'application/json'
      post '/parsed_body', valid_json_body
      expect(last_response.body).to eq(valid_json_body)
    end

    it 'does not attempt to validate a GET or DELETE request by default' do
      header 'Read-Body', 'true'
      header  'Content-Type', 'application/json'
      get '/parsed_body', invalid_json_body
      expect(last_response.status).to eq(200)

      delete '/parsed_body', invalid_json_body
      expect(last_response.status).to eq(200)
    end

    it 'does not blow up if given no content type' do
      header 'Read-Body', 'true'
      get '/parsed_body', invalid_json_body
      expect(last_response.status).to eq(200)
    end

    it 'does not attempt to validate non-JSON by default' do
      header 'Read-Body', 'true'
      header  'Content-Type', 'text/plain'
      post '/parsed_body', "some content"
      expect(last_response.body).to eq("some content")
    end

    it 'allows users to override the validate_request_if config' do
      override_config do |config|
        config.validate_request_if do |env|
          true
        end
      end

      header  'Content-Type', 'text/plain'
      post '/parsed_body', valid_json_body
      expect(last_response.body).to eq("id: 3; name: foo")
    end

    it 'responds with a 406 by default when no matching version can be found' do
      wrong_version_yaml = endpoint_definition_yml.gsub('1.0', '2.0')

      override_config do |config|
        config.endpoints = [Endpoint.new(YAML.load wrong_version_yaml)]
      end

      header 'Content-Type', 'application/json'
      post '/parsed_body', valid_json_body
      expect(last_response.status).to eq(406)
    end

    it 'uses the on_unavailable_request_version hook to respond in ' +
       'cases where no version can be found' do
      wrong_version_yaml = endpoint_definition_yml.gsub('1.0', '2.0')

      override_config do |config|
        config.endpoints = [Endpoint.new(YAML.load wrong_version_yaml)]
        config.on_unavailable_request_version do |env, requested, available|
          [315, { 'Content-Type' => 'text/plain' },
           ["Method: #{env.fetch('REQUEST_METHOD')}; ",
            "Requested: #{requested.inspect}; ",
            "Available: #{available.inspect}"]]
        end
      end

      header 'Content-Type', 'application/json'
      post '/parsed_body', valid_json_body
      expect(last_response.status).to eq(315)
      expect(last_response.body).to eq('Method: POST; Requested: "1.0"; Available: ["2.0"]')
    end

    it 'uses the request_version_for callback to select the version' do
      wrong_version_yaml = endpoint_definition_yml.gsub('1.0', '2.0')

      override_config do |config|
        config.endpoints = [Endpoint.new(YAML.load wrong_version_yaml)]
        config.request_version do |env, endpoint|
          expect(env.fetch('REQUEST_METHOD')).to eq('POST')
          expect(endpoint).to be_a(Interpol::Endpoint)
          '2.0'
        end
      end

      header 'Content-Type', 'application/json'
      post '/parsed_body', valid_json_body
      expect(last_response.status).to eq(200)
    end
  end
end

