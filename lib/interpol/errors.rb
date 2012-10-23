module Interpol
  # Base class that interpol errors should subclass.
  class Error < StandardError; end

  # Error raised when the configuration is invalid.
  class ConfigurationError < Error
    attr_reader :original_error

    def initialize(message=nil, original_error=nil)
      @original_error = original_error
      super(message)
    end
  end

  # Error raised when data fails to validate against the schema
  # for an endpoint.
  class ValidationError < Error
    attr_reader :errors

    def initialize(errors = [], data = nil, endpoint_description = '')
      @errors = errors
      error_bullet_points = errors.map { |e| "\n  - #{e}" }.join
      message = "Found #{errors.size} error(s) when validating " +
                "against endpoint #{endpoint_description}. " +
                "Errors: #{error_bullet_points}.\n\nData:\n#{data.inspect}"

      super(message)
    end
  end

  # Error raised when the schema validator cannot find a matching
  # endpoint definition for the request.
  class NoEndpointDefinitionFoundError < Error; end

  # Error raised when multiple endpoint definitions are found
  # for a given criteria.
  class MultipleEndpointDefinitionsFoundError < Error; end

  # Raised when an invalid status code is found during validate_codes!
  class StatusCodeMatcherArgumentError < ArgumentError; end

  # Raised when an unsupported parameter type is defined.
  class UnsupportedTypeError < ArgumentError
    attr_reader :type, :options

    def initialize(type, options = {})
      @type = type
      @options = options

      description = type.inspect
      description << " (#{options.inspect})" if options.any?
      super("No param parser can be found for #{description}")
    end
  end

  # Raised when the path_params are not part of the endpoint route.
  class InvalidPathParamsError < ArgumentError
    attr_reader :invalid_params

    def initialize(*invalid_params)
      @invalid_params = invalid_params
      super("The path params #{invalid_params.join(', ')} are not in the route")
    end
  end

  # Raised when a parameter value cannot be parsed.
  CannotBeParsedError = Class.new(ArgumentError)

  # Raised when a params definition is invalid.
  InvalidParamsDefinitionError = Class.new(ArgumentError)
end

