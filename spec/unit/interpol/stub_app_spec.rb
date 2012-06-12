require 'fast_spec_helper'
require 'interpol/stub_app'
require 'rack/test'

module Interpol
  describe StubApp do
    include Rack::Test::Methods

    let_without_indentation(:endpoint_definition_yml) do <<-EOF
      ---
      name: project_list
      route: /users/:user_id/projects
      method: GET
      definitions:
        - versions: ["1.0"]
          schema:
            type: object
            properties:
              name:
                type: string
          examples:
            - name: "some project"
      EOF
    end

    let(:endpoint) { Endpoint.new(YAML.load endpoint_definition_yml) }

    let(:app) do
      StubApp.build do |config|
        config.stub(:endpoints => [endpoint])

        unless api_version_configured?(config) # allow default config to take precedence
          config.api_version { |env, _| env.fetch('HTTP_API_VERSION') }
        end
      end.tap do |a|
        a.set :raise_errors, true
        a.set :show_exceptions, false
      end
    end

    def parsed_body
      JSON.parse(last_response.body)
    end

    it 'falls back to the default configuration' do
      Interpol.default_configuration { |c| c.api_version '1.0' }

      header 'API-Version', '2.0'
      get '/users/3/projects'
      parsed_body.should include('name' => 'some project')
    end

    it 'calls the api_version callback with the rack env and the endpoint' do
      yielded_args = nil
      Interpol.default_configuration do |c|
        c.api_version do |*args|
          yielded_args = args
          '1.0'
        end
      end

      get '/users/3/projects'

      yielded_args.map(&:class).should eq([Hash, Interpol::Endpoint])
    end

    it 'renders the example data' do
      header 'API-Version', '1.0'
      get '/users/3/projects'
      parsed_body.should include('name' => 'some project')
      last_response.should be_ok
    end

    it 'uses the unavailable_request_version hook when an invalid version is requested' do
      app.interpol_config.on_unavailable_request_version do |requested_version, available_versions|
        halt 405, JSON.dump(:requested => requested_version, :available => available_versions)
      end

      header 'API-Version', '2.0'
      get '/users/3/projects'
      last_response.status.should eq(405)
      parsed_body.should eq("requested" => "2.0", "available" => ["1.0"])
    end

    it 'renders a 405 when an invalid version is requested and there is no configured callback' do
      header 'API-Version', '2.0'
      get '/users/3/projects'
      last_response.status.should eq(406)
    end

    it 'responds with a 404 for an undefined endpoint' do
      header 'API-Version', '1.0'
      get '/some/undefined/endpoint'
      last_response.should be_not_found
      last_response.status.should eq(404)
      parsed_body.should eq("error" => "The requested resource could not be found")

      pending "sinatra bug: https://github.com/sinatra/sinatra/issues/500" do
        last_response.headers['Content-Type'].should eq('application/json;charset=utf-8')
      end
    end

    let(:endpoint_example) do
      endpoint.find_example_for!('1.0', 'response')
    end

    it 'performs validations by default' do
      endpoint_example.should respond_to(:validate!).with(0).arguments
      endpoint_example.should_receive(:validate!).with(no_args)
      header 'API-Version', '1.0'
      get '/users/3/projects'
      last_response.should be_ok
    end

    it 'responds to a ping' do
      get '/__ping'
      parsed_body.should eq("message" => "Interpol stub app running.")
    end
  end
end

