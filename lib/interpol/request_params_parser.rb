require 'interpol'
require 'interpol/dynamic_struct'
require 'uri'
require 'interpol/each_with_object' unless Enumerable.method_defined?(:each_with_object)

module Interpol
  # This class is designed to parse and validate a rails or sinatra
  # style params hash based on the path_params/query_params
  # declarations of an endpoint request definition.
  #
  # The path_params and query_params declarations are merged together
  # during validation, since both rails and sinatra give users a single
  # params hash that contains the union of both kinds of params.
  #
  # Note that the validation here takes some liberties; it supports
  # '3' as well as 3 for 'integer' params, for example, because it
  # assumes that the values in a params hash are almost certainly going
  # to be strings since that's how rails and sinatra give them to you.
  #
  # The parsed params object supports dot-syntax for accessing parameters
  # and will convert values where feasible (e.g. '3' = 3, 'true' => true, etc).
  class RequestParamsParser
    def initialize(endpoint_definition)
      @validator = ParamValidator.new(endpoint_definition)
      @validator.validate_path_params_valid_for_route!
      @converter = ParamConverter.new(@validator.param_definitions)
    end

    def parse(params)
      validate!(params)
      DynamicStruct.new(@converter.convert params)
    end

    def validate!(params)
      @validator.validate!(params)
    end

    # Private: This takes care of the validation.
    class ParamValidator
      def initialize(endpoint_definition)
        @endpoint_definition = endpoint_definition
        @params_schema = build_params_schema
      end

      def validate_path_params_valid_for_route!
        route = @endpoint_definition.route
        invalid_params = @endpoint_definition.path_params.keys.reject do |param|
          route =~ %r</:#{Regexp.escape(param)}(/|$)>
        end

        return if invalid_params.none?
        raise InvalidPathParamsError.new(*invalid_params)
      end

      def validate!(params)
        errors = ::JSON::Validator.fully_validate(@params_schema, params)
        raise ValidationError.new(errors, params, description) if errors.any?
      end

      def param_definitions
        @param_definitions ||= @endpoint_definition.path_params.merge \
          @endpoint_definition.query_params
      end

    private

      def description
        @description ||= "#{@endpoint_definition.description} - request params"
      end

      def build_params_schema
        { 'type'                 => 'object',
          'properties'           => adjusted_definitions,
          'additionalProperties' => false }
      end

      def adjusted_definitions
        param_definitions.each_with_object({}) do |(name, schema), hash|
          hash[name] = adjusted_schema(schema)
        end
      end

      STRING_EQUIVALENTS = {
        'string'  => nil,
        'integer' => { 'type' => 'string', 'pattern' => '^\-?\d+$' },
        'number'  => { 'type' => 'string', 'pattern' => '^\-?\d+(\.\d+)?$' },
        'boolean' => { 'type' => 'string', 'enum'    => %w[ true false ] },
        'null'    => { 'type' => 'string', 'enum'    => [''] }
      }

      def adjusted_schema(schema)
        types = Array(schema['type'])

        string_equivalents = types.map do |type|
          STRING_EQUIVALENTS.fetch(type) do
            unless type.is_a?(Hash) # a nested union type
              raise UnsupportedTypeError.new(type)
            end
          end
        end.compact

        schema.merge('type' => (types + string_equivalents)).tap do |adjusted|
          adjusted['required'] = true unless adjusted['optional']
        end
      end
    end

    # Private: This takes care of the parameter conversions.
    class ParamConverter
      attr_reader :param_definitions

      def initialize(param_definitions)
        @param_definitions = param_definitions
      end

      def convert(params)
        @param_definitions.keys.each_with_object({}) do |name, hash|
          hash[name] = if params.has_key?(name)
            convert_param(name, params.fetch(name))
          else
            nil
          end
        end
      end

    private

      def convert_param(name, value)
        definition = param_definitions.fetch(name)

        Array(definition['type']).each do |type|
          converter = converter_for(type, definition)

          begin
            return converter.call(value)
          rescue ArgumentError => e
            # Try the next unioned type...
          end
        end

        raise CannotBeParsedError, "The #{name} #{value.inspect} cannot be parsed"
      end

      BOOLEANS = { 'true'  => true,  true  => true,
                   'false' => false, false => false }
      def self.convert_boolean(value)
        BOOLEANS.fetch(value) do
          raise ArgumentError, "#{value} is not convertable to a boolean"
        end
      end

      NULLS = { '' => nil, nil => nil }
      def self.convert_null(value)
        NULLS.fetch(value) do
          raise ArgumentError, "#{value} is not convertable to null"
        end
      end

      def self.convert_date(value)
        unless value =~ /\A\d{4}\-\d{2}\-\d{2}\z/
          raise ArgumentError, "Not in iso8601 format"
        end

        Date.new(*value.split('-').map(&:to_i))
      end

      def self.convert_uri(value)
        URI(value).tap do |uri|
          unless uri.scheme && uri.host
            raise ArgumentError, "Not a valid full URI"
          end
        end
      rescue URI::InvalidURIError => e
        raise ArgumentError, e.message, e.backtrace
      end

      CONVERTERS = {
        'integer' => method(:Integer),
        'number'  => method(:Float),
        'boolean' => method(:convert_boolean),
        'null'    => method(:convert_null)
      }

      IDENTITY_CONVERTER = lambda { |v| v }

      def converter_for(type, definition)
        CONVERTERS.fetch(type) do
          if Hash === type && type['type']
            converter_for(type['type'], type)
          elsif type == 'string'
            string_converter_for(definition)
          else
            raise CannotBeParsedError, "#{type} cannot be parsed"
          end
        end
      end

      STRING_CONVERTERS = {
        'date'      => method(:convert_date),
        'date-time' => Time.method(:iso8601),
        'uri'       => method(:convert_uri)
      }

      def string_converter_for(definition)
        STRING_CONVERTERS.fetch(definition['format'], IDENTITY_CONVERTER)
      end
    end

    # Raised when an unsupported parameter type is defined.
    class UnsupportedTypeError < ArgumentError
      attr_reader :type

      def initialize(type)
        @type = type
        super("#{type} params are not supported")
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
  end
end

