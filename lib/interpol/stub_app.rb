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
          example, version = settings.
                             stub_app_builder.
                             example_and_version_for(endpoint, self)
          example.validate!
          status endpoint.find_example_status_code_for!(version)
          JSON.dump(example.data)
        end
      end

      def example_and_version_for(endpoint, app)
        version = config.response_version_for(app.request.env, endpoint)
        example = endpoint.find_example_for!(version, 'response')
      rescue NoEndpointDefinitionFoundError
        config.sinatra_request_version_unavailable(app, version, endpoint.available_versions)
      else
        example = example.apply_filters(config.filter_example_data_blocks, app.request.env)
        return example, version
      end
    end
  end
end

