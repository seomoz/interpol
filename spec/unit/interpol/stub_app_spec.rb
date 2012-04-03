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
        config.stub(endpoints: [endpoint])
        config.api_version { |req| req.env['HTTP_API_VERSION'] }
      end
    end

    def parsed_body
      JSON.parse(last_response.body)
    end

    it 'renders the example data' do
      header 'API-Version', '1.0'
      get '/users/3/projects'
      parsed_body.should include('name' => 'some project')
      last_response.should be_ok
    end

    it 'uses the configured invalid_request_version hook when an invalid version is requested' do
      app.interpol_config.on_invalid_request_version do |requested_version, available_versions|
        halt 405, JSON.dump(requested: requested_version, available: available_versions)
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
      last_response.headers['Content-Type'].should eq('application/json;charset=utf-8')
    end

    let(:endpoint_example) do
      endpoint.find_example_for!('1.0')
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

