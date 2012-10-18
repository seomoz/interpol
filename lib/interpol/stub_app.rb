require 'interpol'
require 'sinatra/base'
require 'json'

module Interpol
  module StubApp
    extend self

    def build(&block)
      config = Configuration.default.customized_duplicate(&block)
      builder = Builder.new(config)
      builder.build
      builder.app
    end

    # Private: Builds a stub sinatra app for the given interpol
    # configuration.
    class Builder
      attr_reader :app, :config

      def initialize(config)
        builder = self
        @config = config

        @app = ::Sinatra.new do
          set               :stub_app_builder, builder
          not_found         { JSON.dump(:error => "The requested resource could not be found") }
          before            { content_type "application/json;charset=utf-8" }
          before('/__ping') { skip_param_parsing! if respond_to?(:skip_param_parsing!) }
          get('/__ping')    { JSON.dump(:message => "Interpol stub app running.") }
          enable            :perform_validations

          def self.name
            "Interpol::StubApp (anonymous)"
          end
        end
      end

      def build
        config.endpoints.each do |endpoint|
          app.send(endpoint.method, endpoint.route, &endpoint_definition(endpoint))
        end
      end

      def endpoint_definition(endpoint)
        lambda do
          endpoint_def = settings.stub_app_builder.endpoint_def_for(endpoint, self)
          example = settings.stub_app_builder.example_for(endpoint_def, self)
          example.validate! if settings.perform_validations?
          status endpoint_def.example_status_code
          JSON.dump(example.data)
        end
      end

      def endpoint_def_for(endpoint, app)
        version = config.response_version_for(app.request.env, endpoint)
        endpoint_def = endpoint.find_definition!(version, 'response')
      rescue NoEndpointDefinitionFoundError
        config.sinatra_request_version_unavailable \
          app, version, endpoint.available_response_versions
      end

      def example_for(endpoint_def, app)
        example = config.example_response_for(endpoint_def, app.request.env)
        example.apply_filters(config.filter_example_data_blocks, app.request.env)
      end
    end
  end
end

