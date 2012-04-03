require 'interpol/configuration'
require 'interpol/endpoint'
require 'interpol/errors'
require 'json'

module Interpol
  # Rack middleware that validates response data against the schema
  # definition for the endpoint. Can be configured to raise an
  # error or warn in this condition. Intended for development and
  # test use.
  class ResponseSchemaValidator
    module ConfigurationExtras
      attr_accessor :validation_mode

      def validate_if(&block)
        @validate_if_block = block
      end

      def validate?(*args)
        @validate_if_block ||= lambda do |env, status, headers, body|
          (200..299).cover?(status)
        end
        @validate_if_block.call(*args)
      end
    end

    def initialize(app)
      @config = Configuration.new.extend(ConfigurationExtras)
      yield @config
      @app = app
      @handler_class = @config.validation_mode == :warn ? HandlerWithWarnings : Handler
    end

    def call(env)
      status, headers, body = @app.call(env)
      return status, headers, body unless @config.validate?(env, status, headers, body)

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
        return validator.validate_data!(data) if validator
        raise NoEndpointDefinitionFoundError,
          "No endpoint definition could be found for: #{request_method} '#{path}' (#{version})"
      end

      # The only interface we can count on from the body is that it
      # implements #each. It may not be re-windable. To preserve this
      # interface while reading the whole thing, we need to extract
      # it into our own array.
      def extracted_body
        @extracted_body ||= [].tap do |extracted_body|
          body.each { |str| extracted_body << str }
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
        env.fetch('PATH_INFO')
      end

      def version
        @version ||= @config.api_version_for(@env)
      end

      def validator
        @validator ||= @config.endpoints.find_definition \
          method: request_method, path: path, version: version
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

