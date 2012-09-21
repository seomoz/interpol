require 'fast_spec_helper'
require 'sinatra/base'
require 'interpol/sinatra/request_params_parser'
require 'support/request_params_parser_definition'
require 'rack/test'

module Interpol
  module Sinatra
    describe RequestParamsParser, :uses_request_params_parser_definition do
      include Rack::Test::Methods

      def on_get(&block)
        @endpoint_logic = block
      end

      def configure_parser(&block)
        @parser_configuration = block
      end

      let(:raw_endpoint_definition) { YAML.load endpoint_definition_yml }
      let(:endpoint) { Endpoint.new(raw_endpoint_definition) }

      let(:app) do
        endpoint_logic = @endpoint_logic || Proc.new { }
        parser_configuration = @parser_configuration || Proc.new { }
        _endpoint = endpoint

        ::Sinatra.new do
          use RequestParamsParser do |config|
            config.endpoints = [_endpoint]
            config.api_version '1.0'
            parser_configuration.call(config)
          end

          set :raise_errors,    true
          set :show_exceptions, false

          get('/users/:user_id/projects/:project_language', &endpoint_logic)
          get('/no/definition') { 'OK' }
        end
      end

      it 'makes the endpoint definition available as `endpoint_definition`' do
        on_get { endpoint_definition.endpoint_name }

        get '/users/23.12/projects/ruby'
        last_response.status.should eq(200)
        last_response.body.should eq(endpoint.name)
      end

      it 'makes the original unparsed params available as `unparsed_params`' do
        on_get { JSON.dump(unparsed_params) }

        get '/users/23.12/projects/ruby?integer=3'
        last_response.status.should eq(200)

        expected = { 'user_id' => '23.12',
                     'project_language' => 'ruby',
                     'integer' => '3' }
        JSON.load(last_response.body).should include(expected)
      end

      it 'adds automatic request params validation to every request' do
        on_get { 'OK' } # don't use the params

        get '/users/foo/projects/ruby'
        last_response.status.should eq(400)
        last_response.body.should include('user_id')

        get '/users/12.23/projects/ruby'
        last_response.status.should eq(200)
        last_response.body.should eq("OK")
      end

      it 'makes the parsed params object available as `params`' do
        on_get { params.methods.join(',') }

        get '/users/12.23/projects/ruby?integer=3'
        last_response.status.should eq(200)
        last_response.body.split(',').should include(*%w[ user_id project_language integer ])
      end

      it 'allows the host app to define what action should be taken when validation fails' do
        configure_parser do |config|
          config.on_invalid_sinatra_request_params do |error|
            halt 422, error.message
          end
        end

        get '/users/foo/projects/ruby'
        last_response.status.should eq(422)
      end

      it 'responds appropriately when no definition is found' do
        get '/no/definition'
        last_response.status.should eq(406) # the default response
      end

      it 'allows users to configure how to respond when no definition is found' do
        configure_parser do |config|
          config.on_unavailable_request_version do
            halt 412
          end
        end

        get '/no/definition'
        last_response.status.should eq(412)
      end

      it 'passes the version args to the on_unavailable_request_version hook when available' do
        version, available_versions = nil, nil

        configure_parser do |config|
          config.api_version '2.0'
          config.on_unavailable_request_version do |_v, _av|
            version, available_versions = _v, _av
            halt 406
          end
        end

        get '/users/12.23/projects/ruby'
        last_response.status.should eq(406)
        version.should eq('2.0')
        available_versions.should eq(['1.0'])
      end

      it 'provides a means to add additional validations' do
        configure_parser do |config|
          config.on_invalid_sinatra_request_params do |error|
            halt 412, error
          end
        end

        on_get { request_params_invalid("bad") }

        get '/users/12.23/projects/ruby'
        last_response.status.should eq(412)
        last_response.body.should eq("bad")
      end

      it 'allows unmatched routes to 404 as normal' do
        get '/some/invalid/route'
        last_response.status.should eq(404)
      end

      it 'provides a means to disable param parsing' do
        on_get { 'OK' } # don't use the params

        app.disable :parse_params

        get '/users/foo/projects/ruby'
        last_response.status.should eq(200)
        last_response.body.should eq("OK")
      end

      context 'when the sinatra app is mounted using Rack::Builder' do
        alias sinatra_app app

        let(:app) do
          _sinatra_app = sinatra_app

          Rack::Builder.new do
            map('/mounted_path') { run _sinatra_app.new }
          end
        end

        it 'works properly' do
          endpoint_definition_yml.gsub!('route: /', 'route: /mounted_path/')

          get '/mounted_path/users/foo/projects/ruby'
          last_response.status.should eq(400)

          get '/mounted_path/users/12.23/projects/ruby'
          last_response.status.should eq(200)
        end
      end
    end
  end
end

