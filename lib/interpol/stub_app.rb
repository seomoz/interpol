require 'interpol/configuration'
require 'interpol/endpoint'
require 'sinatra/base'
require 'json'

module Interpol
  module StubApp
    extend self

    module ConfigurationExtras
      def on_invalid_request_version(&block)
        @invalid_request_version_block = block
      end

      def request_version_invalid(execution_context, *args)
        @invalid_request_version_block ||= lambda do |requested, available|
          message = "The requested API version is invalid. " +
                    "Requested: #{requested}. " +
                    "Available: #{available}"
          halt 406, JSON.dump(error: message)
        end

        execution_context.instance_exec(*args, &@invalid_request_version_block)
      end
    end

    def build
      config = Configuration.new
      config.extend ConfigurationExtras
      yield config

      builder = Builder.new(config)
      builder.build
      builder.app
    end

    module Helpers
      def interpol_config
        self.class.interpol_config
      end

      def example_for(endpoint, version)
        endpoint.find_example_for!(version)
      rescue ArgumentError
        interpol_config.request_version_invalid(self, version, endpoint.available_versions)
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
          not_found      { JSON.dump(error: "The requested resource could not be found") }
          before         { content_type "application/json;charset=utf-8" }
          get('/__ping') { JSON.dump(message: "Interpol stub app running.") }
        end
      end

      def build
        @app.interpol_config.endpoints.each do |endpoint|
          app.send(endpoint.method, endpoint.route, &endpoint_definition(endpoint))
        end
      end

      def endpoint_definition(endpoint)
        lambda do
          version = interpol_config.api_version_for(request)
          example = example_for(endpoint, version)
          example.validate!
          JSON.dump(example.data)
        end
      end
    end
  end
end

