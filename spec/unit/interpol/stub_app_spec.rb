require 'interpol/stub_app'
require 'interpol/sinatra/request_params_parser'
require 'rack/test'

module Interpol
  RSpec.describe StubApp do
    include Rack::Test::Methods

    let_without_indentation(:endpoint_definition_yml) do <<-EOF
      ---
      name: project_list
      route: /users/:user_id/projects
      method: GET
      definitions:
        - versions: ["1.0"]
          status_codes: ['200']
          message_type: response
          schema:
            type: object
            properties:
              name:
                type: string
          examples:
            - name: "some project"
            - name: "some other project"
        - versions: ["1.0"]
          message_type: request
          path_params:
            type: object
            properties:
              user_id:
                type: integer
          schema: {}
          examples: []
      EOF
    end

    let_without_indentation(:another_definition_yml) do <<-EOF
      ---
      name: another_endpoint
      route: /another-endpoint
      method: GET
      definitions:
        - versions: ["1.0"]
          status_codes: ['200']
          message_type: response
          schema:
            type: object
            properties:
              example_num: { type: integer }
          examples:
            - example_num: 0
            - example_num: 1
        - versions: ["1.0"]
          message_type: request
          schema: {}
          examples: []
      EOF
    end

    let(:endpoint) { Endpoint.new(YAML.load endpoint_definition_yml) }
    let(:another_endpoint) { Endpoint.new(YAML.load another_definition_yml) }

    let(:default_config) do
      lambda do |config|
        config.endpoints = [endpoint, another_endpoint]

        unless response_version_configured?(config) # allow default config to take precedence
          config.response_version { |env, _| env.fetch('HTTP_RESPONSE_VERSION') }
          config.request_version { |env, _| env.fetch('HTTP_REQUEST_VERSION') }
        end
      end
    end

    let(:config) { app.stub_app_builder.config }

    let(:app) do
      StubApp.build(&default_config).tap do |a|
        a.use Rack::Lint
        a.set :raise_errors, true
        a.set :show_exceptions, false
      end
    end

    def parsed_body
      JSON.parse(last_response.body)
    end

    it 'has a name since some tools except all classes to have a name' do
      expect(app).to be_a(Class)
      expect(app.name).to include("Interpol", "StubApp", "anon")
    end

    it 'falls back to the default configuration' do
      Interpol.default_configuration { |c| c.response_version '1.0' }

      header 'Response-Version', '2.0'
      get '/users/3/projects'
      expect(parsed_body).to include('name' => 'some project')
    end

    it 'calls the response_version callback with the rack env and the endpoint' do
      yielded_args = nil
      Interpol.default_configuration do |c|
        c.response_version do |*args|
          yielded_args = args
          '1.0'
        end
      end

      get '/users/3/projects'

      expect(yielded_args.map(&:class)).to eq([Hash, Interpol::Endpoint])
    end

    it 'renders the example data' do
      header 'Response-Version', '1.0'
      get '/users/3/projects'
      expect(parsed_body).to include('name' => 'some project')
      expect(last_response).to be_ok
    end

    it 'uses the select_example_response callback to select which example gets returned' do
      Interpol.default_configuration do |c|
        c.select_example_response do |endpoint_def, request|
          endpoint_def.examples.last
        end
      end

      header 'Response-Version', '1.0'
      get '/users/3/projects'
      expect(parsed_body).to include('name' => 'some other project')
    end

    it 'can select an example based on the request' do
      Interpol.default_configuration do |c|
        c.select_example_response do |endpoint_def, env|
          index = Integer(env.fetch('HTTP_INDEX'))
          endpoint_def.examples[index]
        end
      end

      header 'Response-Version', '1.0'

      header 'Index', '0'
      get '/another-endpoint'
      expect(parsed_body).to include('example_num' => 0)

      header 'Index', '1'
      get '/another-endpoint'
      expect(parsed_body).to include('example_num' => 1)
    end

    it 'can have different example selection logic for a particular endpoint' do
      Interpol.default_configuration do |c|
        c.select_example_response do |endpoint_def, request|
          endpoint_def.examples.last
        end

        c.select_example_response 'another_endpoint' do |endpoint_def, request|
          endpoint_def.examples.first
        end
      end

      header 'Response-Version', '1.0'
      get '/users/3/projects'
      expect(parsed_body).to include('name' => 'some other project')

      get '/another-endpoint'
      expect(parsed_body).to include('example_num' => 0)
    end

    it 'uses any provided filters to modify the example data' do
      app.settings.stub_app_builder.config.filter_example_data do |example, request_env|
        example.data["name"] += " for #{request_env["REQUEST_METHOD"]}"
      end

      header 'Response-Version', '1.0'
      get '/users/3/projects'

      expect(parsed_body).to include('name' => 'some project for GET')
      expect(last_response).to be_ok
    end

    it 'allows errors in filters to bubble up' do
      config.filter_example_data { raise ArgumentError }

      header 'Response-Version', '1.0'
      expect { get '/users/3/projects' }.to raise_error(ArgumentError)
    end

    it 'uses the unavailable_sinatra_request_version hook when an invalid version is requested' do
      config.on_unavailable_sinatra_request_version do |requested_version, available_versions|
        halt 405, JSON.dump(:requested => requested_version, :available => available_versions)
      end

      header 'Response-Version', '2.0'
      get '/users/3/projects'
      expect(last_response.status).to eq(405)
      expect(parsed_body).to eq("requested" => "2.0", "available" => ["1.0"])
    end

    it 'renders a 405 when an invalid version is requested and there is no configured callback' do
      header 'Response-Version', '2.0'
      get '/users/3/projects'
      expect(last_response.status).to eq(406)
    end

    it 'responds with a 404 for an undefined endpoint' do
      header 'Response-Version', '1.0'
      get '/some/undefined/endpoint'
      expect(last_response).to be_not_found
      expect(last_response.status).to eq(404)
      expect(parsed_body).to eq("error" => "The requested resource could not be found")

      expect(last_response.headers['Content-Type']).to eq('application/json;charset=utf-8')
    end

    let(:endpoint_example) do
      endpoint.find_definition!('1.0', 'response').examples.first
    end

    it 'performs validations by default' do
      allow(endpoint_example).to receive(:apply_filters) { endpoint_example }
      expect(endpoint_example).to respond_to(:validate!).with(0).arguments
      expect(endpoint_example).to receive(:validate!).with(no_args)
      header 'Response-Version', '1.0'
      get '/users/3/projects'
      expect(last_response).to be_ok
    end

    it 'does not perform validates if validations are disabled' do
      app.disable :perform_validations

      allow(endpoint_example).to receive(:apply_filters) { endpoint_example }
      expect(endpoint_example).to respond_to(:validate!).with(0).arguments
      expect(endpoint_example).not_to receive(:validate!)

      header 'Response-Version', '1.0'
      get '/users/3/projects'
      expect(last_response).to be_ok
    end

    it 'responds to a ping' do
      get '/__ping'
      expect(parsed_body).to eq("message" => "Interpol stub app running.")
    end

    it 'assigns the status code based on the endpoint definition' do
      endpoint_definition_yml.gsub!("status_codes: ['200']", "status_codes: ['214']")

      header 'Response-Version', '1.0'
      get '/users/3/projects'
      expect(last_response.status).to eq(214)
    end

    it 'can be used together with the RequestParamsParser' do
      app.use Interpol::Sinatra::RequestParamsParser, &default_config

      header 'Response-Version', '1.0'
      header 'Request-Version', '1.0'

      get '/users/3/projects'
      expect(last_response.status).to eq(200)

      get '/users/not-a-number/projects'
      expect(last_response.body).to include('user_id')
      expect(last_response.status).to eq(400)

      get '/__ping'
      expect(parsed_body).to eq("message" => "Interpol stub app running.")
    end
  end
end

