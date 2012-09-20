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

    module Helpers
      def interpol_config
        self.class.interpol_config
      end

      def example_for(endpoint, version, message_type)
        example = endpoint.find_example_for!(version, message_type)
      rescue NoEndpointDefinitionFoundError
        interpol_config.request_version_unavailable(self, version, endpoint.available_versions)
      else
        example.apply_filters(interpol_config.filter_example_data_blocks, request.env)
      end
    end

    # Private: Builds a stub sinatra app for the given interpol
    # configuration.
    class Builder
      attr_reader :app

      def initialize(config)
        @app = Sinatra.new do
          set            :interpol_config, config
          helpers        Helpers
          not_found      { JSON.dump(:error => "The requested resource could not be found") }
          before         { content_type "application/json;charset=utf-8" }
          get('/__ping') { JSON.dump(:message => "Interpol stub app running.") }

          def self.name
            "Interpol::StubApp (anonymous)"
          end
        end
      end

      def build
        @app.interpol_config.endpoints.each do |endpoint|
          app.send(endpoint.method, endpoint.route, &endpoint_definition(endpoint))
        end
      end

      def endpoint_definition(endpoint)
        lambda do
          version = interpol_config.api_version_for(request.env, endpoint)
          message_type = 'response'
          example = example_for(endpoint, version, message_type)
          example.validate!
          status endpoint.find_example_status_code_for!(version)
          JSON.dump(example.data)
        end
      end
    end
  end
end

