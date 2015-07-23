require 'interpol'
require 'json'

module Interpol
  # Rack middleware that validates response data against the schema
  # definition for the endpoint. Can be configured to raise an
  # error or warn in this condition. Intended for development and
  # test use.
  class ResponseSchemaValidator
    def initialize(app, &block)
      @config = Configuration.default.customized_duplicate(&block)
      @app = app
      @handler_class = @config.validation_mode == :warn ? HandlerWithWarnings : Handler
    end

    def call(env)
      status, headers, body = @app.call(env)
      unless @config.validate_response?(env, status, headers, body)
        return status, headers, body
      end

      handler = @handler_class.new(status, headers, body, env, @config)
      handler.validate!

      return status, headers, handler.extracted_body
    end

    # Private: handles a responses and validates it. Validation
    # errors will result in an error.
    class Handler
      attr_reader :status, :headers, :body, :env, :config

      def initialize(status, headers, body, env, config)
        @status, @headers, @body, @env, @config = status, headers, body, env, config
      end

      def validate!
        unless validator == Interpol::DefinitionFinder::NoDefinitionFound
          return validator.validate_data!(data)
        end

        raise NoEndpointDefinitionFoundError,
          "No endpoint definition could be found for: #{request_method} '#{path}'"
      end

      # The only interface we can count on from the body is that it
      # implements #each. It may not be re-windable. To preserve this
      # interface while reading the whole thing, we need to extract
      # it into our own array.
      def extracted_body
        @extracted_body ||= [].tap do |extracted_body|
          body.each { |str| extracted_body << str }
          body.close if body.respond_to?(:close)
        end
      end

    private

      def request_method
        env.fetch('REQUEST_METHOD')
      end

      def data
        @data ||= JSON.parse(extracted_body.join)
      end

      def path
        env.fetch('PATH_INFO').gsub(config.base_path, '')
      end

      def validator
        @validator ||= @config.endpoints.
            find_definition(request_method, path, 'response', status) do |endpoint|
          @config.response_version_for(env, endpoint, response_triplet)
        end
      end

      def response_triplet
        [status, headers, extracted_body]
      end
    end

    # Private: Subclasses Handler in order to convert validation errors
    # to warnings instead.
    class HandlerWithWarnings < Handler
      def validate!
        super
      rescue ValidationError, NoEndpointDefinitionFoundError => e
        Kernel.warn e.message
      end
    end
  end
end
