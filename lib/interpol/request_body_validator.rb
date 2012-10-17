require 'interpol'
require 'interpol/dynamic_struct'

module Interpol
  # Validates and parses a request body according to the endpoint
  # schema definitions.
  class RequestBodyValidator
    def initialize(app, &block)
      @config = Configuration.default.customized_duplicate(&block)
      @app = app
    end

    def call(env)
      if @config.validate_request?(env)
        handler = Handler.new(env, @config)

        handler.validate do |error_response|
          return error_response
        end

        env['interpol.parsed_body'] = handler.parse
      end

      @app.call(env)
    end

    # Handles request body validation for a single request.
    class Handler
      attr_reader :env, :config

      def initialize(env, config)
        @env = env
        @config = config
      end

      def parse
        DynamicStruct.new(parsed_body)
      end

      def validate(&block)
        endpoint_definition(&block).validate_data!(parsed_body)
      rescue Interpol::ValidationError => e
        yield @config.request_body_invalid(env, e)
      end

    private

      def request_method
        env.fetch('REQUEST_METHOD')
      end

      def path
        env.fetch('PATH_INFO')
      end

      def parsed_body
        @parsed_body ||= JSON.parse(unparsed_body)
      end

      def unparsed_body
        @unparsed_body ||= begin
          input = env.fetch('rack.input')
          input.read.tap { input.rewind }
        end
      end

      def endpoint_definition(&block)
        config.endpoints.find_definition(request_method, path, 'request', nil) do |endpoint|
          available = endpoint.available_request_versions

          @config.request_version_for(env, endpoint).tap do |requested|
            unless available.include?(requested)
              yield @config.request_version_unavailable(env, requested, available)
            end
          end
        end
      end

    end
  end
end

