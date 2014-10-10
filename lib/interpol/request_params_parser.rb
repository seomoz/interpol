require 'interpol'
require 'interpol/dynamic_struct'
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
    def initialize(endpoint_definition, configuration)
      @validator = ParamValidator.new(endpoint_definition, configuration)
      @validator.validate_path_params_valid_for_route!
      @converter = ParamConverter.new(@validator.param_definitions, configuration)
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
      def initialize(endpoint_definition, configuration)
        @endpoint_definition = endpoint_definition
        @configuration = configuration
        @params_schema = build_params_schema
      end

      def validate_path_params_valid_for_route!
        route = @endpoint_definition.route
        invalid_params = property_defs_from(:path_params).keys.reject do |param|
          route =~ %r</:#{Regexp.escape(param)}(/|$)>
        end

        return if invalid_params.none?
        raise InvalidPathParamsError.new(*invalid_params)
      end

      def validate!(params)
        errors = ::JSON::Validator.fully_validate(@params_schema, params, :version => :draft3)
        raise ValidationError.new(errors, params, description) if errors.any?
      end

      def param_definitions
        @param_definitions ||= property_defs_from(:path_params).merge \
          property_defs_from(:query_params)
      end

    private

      def description
        @description ||= "#{@endpoint_definition.description} - request params"
      end

      def property_defs_from(meth)
        schema = @endpoint_definition.send(meth)

        unless schema['type'] == 'object'
          raise InvalidParamsDefinitionError,
            "The #{meth} of #{@endpoint_definition.description} " +
            "is not typed as an object expected."
        end

        schema.fetch('properties') do
          raise InvalidParamsDefinitionError,
            "The #{meth} of #{@endpoint_definition.description} " +
            "does not contain 'properties' as required."
        end
      end

      def build_params_schema
        path_params = @endpoint_definition.path_params
        query_params = @endpoint_definition.query_params

        query_params.merge(path_params).tap do |schema|
          schema['properties'] = adjusted_definitions
          schema['additionalProperties'] = false if no_additional_properties?
        end
      end

      def adjusted_definitions
        param_definitions.each_with_object({}) do |(name, schema), hash|
          hash[name] = adjusted_schema(schema)
        end
      end

      def no_additional_properties?
        [
          @endpoint_definition.path_params,
          @endpoint_definition.query_params
        ].none? { |params| params['additionalProperties'] }
      end

      def adjusted_schema(schema)
        adjusted_types = Array(schema['type']).inject([]) do |type_list, type|
          type_string, options = if type.is_a?(Hash)
            [type.fetch('type'), type]
          else
            [type, schema]
          end

          @configuration.param_parser_for(type_string, options).
                         type_validation_options_for([type] + type_list, options)
        end

        schema.merge('type' => adjusted_types).tap do |adjusted|
          adjusted['required'] = true unless adjusted['optional']
        end
      end
    end

    # Private: This takes care of the parameter conversions.
    class ParamConverter
      attr_reader :param_definitions

      def initialize(param_definitions, configuration)
        @param_definitions = param_definitions
        @configuration = configuration
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
          parser = parser_for(type, definition)

          begin
            return parser.parse_value(value)
          rescue ArgumentError => e
            # Try the next unioned type...
          end
        end

        raise CannotBeParsedError, "The #{name} #{value.inspect} cannot be parsed"
      end

      def parser_for(type, options)
        if type.is_a?(Hash)
          return parser_for(type.fetch('type'), type)
        end

        @configuration.param_parser_for(type, options)
      end
    end
  end
end

