require 'fast_spec_helper'
require 'sinatra/base'
require 'interpol/sinatra/request_params_parser'
require 'support/request_params_parser_definition'
require 'rack/test'

module Interpol
  module Sinatra
    RSpec.describe RequestParamsParser, :uses_request_params_parser_definition do
      include Rack::Test::Methods

      def on_get(&block)
        @endpoint_logic = block
      end

      def configure_parser(&block)
        @parser_configuration = block
      end

      def sinatra_overrides(&block)
        @sinatra_overrides = block
      end

      def sinatra_before(&block)
        @sinatra_before = block
      end

      attr_accessor :before_parser_middleware, :after_parser_middleware

      let(:raw_endpoint_definition) { YAML.load endpoint_definition_yml }
      let(:endpoint) { Endpoint.new(raw_endpoint_definition) }

      let(:app) do
        endpoint_logic = @endpoint_logic || Proc.new { }
        parser_configuration = @parser_configuration || Proc.new { }
        sinatra_overrides = @sinatra_overrides || Proc.new { }
        sinatra_before = @sinatra_before || Proc.new { }

        _after_parser_middleware = after_parser_middleware
        _before_parser_middleware = before_parser_middleware

        _endpoint = endpoint

        ::Sinatra.new do
          include Module.new(&sinatra_overrides)

          use Rack::Lint
          use _before_parser_middleware if _before_parser_middleware

          use RequestParamsParser do |config|
            config.endpoints = [_endpoint]
            config.request_version '1.0'
            parser_configuration.call(config)
          end

          use _after_parser_middleware if _after_parser_middleware

          set :raise_errors,    true
          set :show_exceptions, false

          before &sinatra_before

          get('/users/:user_id/projects/:project_language', &endpoint_logic)
          get('/no/definition') { 'OK' }
        end
      end

      def find_sinatra_base_subclass_wrapped_in(app)
        return app if app.class.ancestors.include?(::Sinatra::Base)

        wrapped_app = if app.class.name == "Sinatra::Wrapper"
          app.instance_variable_get(:@instance)
        elsif app.respond_to?(:app)
          app.app
        elsif app.instance_variables.include?(:@app)
          app.instance_variable_get(:@app)
        elsif RUBY_VERSION.to_f < 1.9
          skip "Not sure why we can't get this to work on 1.8.7"
        else
          raise "Unable to find a wrapped app within #{app}"
        end

        find_sinatra_base_subclass_wrapped_in(wrapped_app)
      end

      [:to_s, :inspect].each do |meth|
        it "provides reasonable ##{meth} output" do
          # We have to unwrap the app instance to get the core sinatra instance,
          # as required by RequestParamsParser.
          app = find_sinatra_base_subclass_wrapped_in Class.new(::Sinatra::Base).new
          instance = RequestParamsParser.new(app)
          expect(instance.inspect).to eq("#<Interpol::Sinatra::RequestParamsParser>")
        end
      end

      it 'makes the original unparsed params available as `unparsed_params`' do
        on_get { JSON.dump(unparsed_params) }

        get '/users/23.12/projects/ruby?integer=3'
        expect(last_response.status).to eq(200)

        expected = { 'user_id' => '23.12',
                     'project_language' => 'ruby',
                     'integer' => '3' }
        expect(JSON.load(last_response.body)).to include(expected)
      end

      it 'adds automatic request params validation to every request' do
        on_get { 'OK' } # don't use the params

        get '/users/foo/projects/ruby'
        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('user_id')

        get '/users/12.23/projects/ruby'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("OK")
      end

      it 'makes the parsed params object available as `params`' do
        on_get do
          [params.user_id, params.project_language, params.integer].join(',')
        end

        get '/users/12.23/projects/ruby?integer=3'
        expect(last_response.status).to eq(200)
        expect(last_response.body.split(',')).to eq(%w[ 12.23 ruby 3 ])
      end

      it 'allows the host app to define what action should be taken when validation fails' do
        configure_parser do |config|
          config.on_invalid_sinatra_request_params do |error|
            halt 422, error.message
          end
        end

        get '/users/foo/projects/ruby'
        expect(last_response.status).to eq(422)
      end

      it 'responds appropriately when no definition is found' do
        get '/no/definition'
        expect(last_response.status).to eq(406) # the default response
      end

      it 'allows users to configure how to respond when no definition is found' do
        configure_parser do |config|
          config.on_unavailable_sinatra_request_version do
            halt 412
          end
        end

        get '/no/definition'
        expect(last_response.status).to eq(412)
      end

      it 'passes the version args to the on_unavailable_sinatra_request_version hook when available' do
        version, available_versions = nil, nil

        configure_parser do |config|
          config.request_version '2.0'
          config.on_unavailable_sinatra_request_version do |_v, _av|
            version, available_versions = _v, _av
            halt 406
          end
        end

        get '/users/12.23/projects/ruby'
        expect(last_response.status).to eq(406)
        expect(version).to eq('2.0')
        expect(available_versions).to eq(['1.0'])
      end

      it 'allows unmatched routes to 404 as normal' do
        get '/some/invalid/route'
        expect(last_response.status).to eq(404)
      end

      it 'provides a means to disable param parsing at an app level' do
        on_get { 'OK' } # don't use the params

        app.disable :parse_params

        get '/users/foo/projects/ruby'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("OK")
      end

      it 'provides a means to disable param in a before hook' do
        on_get { 'OK' } # don't use the params

        sinatra_before { skip_param_parsing! }

        get '/users/foo/projects/ruby'
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq("OK")
      end

      context 'when the app class is instantiated multiple times' do
        alias app_class app
        attr_accessor :app

        it 'allows `unparsed_params` to work each time' do
          on_get { unparsed_params.fetch('integer') }

          2.times do
            self.app = app_class.new
            get '/users/23.12/projects/ruby?integer=3'
            expect(last_response.body).to eq('3')
          end
        end
      end

      context 'when the sinatra app is mounted using Rack::Builder' do
        let(:app) do
          sinatra_app = super()

          Rack::Builder.new do
            map('/mounted_path') { run sinatra_app.new }
          end
        end

        it 'works properly' do
          endpoint_definition_yml.gsub!('route: /', 'route: /mounted_path/')

          get '/mounted_path/users/foo/projects/ruby'
          expect(last_response.status).to eq(400)

          get '/mounted_path/users/12.23/projects/ruby'
          expect(last_response.status).to eq(200)
        end
      end

      context 'when the endpoint raises an error and the raise_errors setting is off' do
        before do
          on_get { raise "boom" }
          app.set :raise_errors, false
        end

        it 'does not fail due to double parsing the params (as originally occurred)' do
          get '/users/12.23/projects/ruby'
          expect(last_response.status).to eq(500)
        end
      end

      context 'when other middlewares are used' do
        let(:identity_middleware) do
          Class.new do
            def initialize(app)
              @app = app
            end

            def call(env)
              @app.call(env)
            end
          end
        end

        before do
          stub_const("IdentityMiddleware", identity_middleware)
          on_get { 'OK' }
        end

        it 'works when adding middlewares before the parser' do
          self.before_parser_middleware = IdentityMiddleware

          get '/users/foo/projects/ruby'
          expect(last_response.status).to eq(400)
          expect(last_response.body).to include('user_id')
        end

        it 'raises a helpful error when adding middlewares after the parser' do
          self.after_parser_middleware = IdentityMiddleware

          expect {
            get '/users/foo/projects/ruby'
          }.to raise_error(/RequestParamsParser must come last/)
        end
      end

      context 'when a sinatra extension is loaded that processes routes multiple times (such as NewRelic)' do
        before do
          # This simulates how NewRelic hooks into Sinatra and runs `process_route`
          # once on its own before allowing sinatra to do its normal dispatch.
          # https://github.com/newrelic/rpm/blob/3.4.2.1/lib/new_relic/agent/instrumentation/sinatra.rb#L37
          sinatra_overrides do
            def dispatch!
              process_route(/^\/users\/([^\/?#]+)\/projects\/([^\/?#]+)$/,
                            ["user_id", "project_language"],
                            []) { }

              super
            end
          end
        end

        it 'does not fail due to double parsing the params (as originally occurred)' do
          on_get { 'OK' } # don't use the params

          get '/users/foo/projects/ruby'
          expect(last_response.status).to eq(400)
          expect(last_response.body).to include('user_id')

          get '/users/12.23/projects/ruby'
          expect(last_response.status).to eq(200)
          expect(last_response.body).to eq("OK")
        end
      end
    end
  end
end

