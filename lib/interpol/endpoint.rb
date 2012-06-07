require 'json-schema'
require 'interpol/errors'

module Interpol
  module HashFetcher
    # Unfortunately, on JRuby 1.9, the error raised from Hash#fetch when
    # the key is not found does not include the key itself :(. So we work
    # around it here.
    def fetch_from(hash, key)
      hash.fetch(key) do
        raise ArgumentError.new("key not found: #{key.inspect}")
      end
    end
  end

  # Represents an endpoint. Instances of this class are constructed
  # based on the endpoint definitions in the YAML files.
  class Endpoint
    include HashFetcher
    attr_reader :name, :route, :method

    def initialize(endpoint_hash)
      @name        = fetch_from(endpoint_hash, 'name')
      @route       = fetch_from(endpoint_hash, 'route')
      @method      = fetch_from(endpoint_hash, 'method').downcase.to_sym
      @definitions = extract_definitions_from(endpoint_hash)
      validate_name!
    end

    def find_definition!(version, message_type)
      @definitions.each do |definition|
        if definition.version == version &&
            definition.message_type == message_type
          return definition
        end
      end
      message = "No definition found for #{name} endpoint for version #{version}"
      message << " and message_type #{message_type}"
      raise ArgumentError.new(message)
    end

    def find_example_for!(version, message_type)
      find_definition!(version, message_type).examples.first
    end

    def available_versions
      definitions.map(&:version)
    end

    def definitions
      # sort all requests before all responses
      # sort higher version numbers before lower version numbers
      @definitions.sort do |x, y|
        if x.message_type == y.message_type
          y.version <=> x.version
        else
          x.message_type <=> y.message_type
        end
      end
    end

    def route_matches?(path)
      path =~ route_regex
    end

  private

    def route_regex
      @route_regex ||= begin
        regex_string = route.split('/').map do |path_part|
          if path_part.start_with?(':')
            '[^\/]+' # it's a parameter; match anything
          else
            Regexp.escape(path_part)
          end
        end.join('\/')

        /\A#{regex_string}\z/
      end
    end

    DEFAULT_MESSAGE_TYPE = 'response'

    def extract_definitions_from(endpoint_hash)
      definitions = []

      fetch_from(endpoint_hash, 'definitions').each do |definition|
        fetch_from(definition, 'versions').each do |version|
          message_type = definition['message_type'] || DEFAULT_MESSAGE_TYPE
          definitions << EndpointDefinition.new(name, version, message_type, definition)
        end
      end

      definitions
    end

    def validate_name!
      unless name =~ /\A[\w\-]+\z/
        raise ArgumentError, "Invalid endpoint name (#{name.inspect}). "+
                             "Only letters, numbers, underscores and dashes are allowed."
      end
    end
  end

  # Wraps a single versioned definition for an endpoint.
  # Provides the means to validate data against that version of the schema.
  class EndpointDefinition
    include HashFetcher
    attr_reader :endpoint_name, :message_type, :version, :schema, :examples

    def initialize(endpoint_name, version, message_type, definition)
      @endpoint_name  = endpoint_name
      @message_type   = message_type
      @status_codes   = StatusCodeMatcher.new(definition['status_codes'])
      @version        = version
      @schema         = fetch_from(definition, 'schema')
      @examples       = fetch_from(definition, 'examples').map { |e| EndpointExample.new(e, self) }
      make_schema_strict!(@schema)
    end

    def validate_data!(data)
      errors = ::JSON::Validator.fully_validate_schema(schema)
      raise ValidationError.new(errors, nil, description) if errors.any?
      errors = ::JSON::Validator.fully_validate(schema, data)
      raise ValidationError.new(errors, data, description) if errors.any?
    end

    def description
      "#{endpoint_name} (v. #{version}, mt. #{message_type}, sc. #{status_codes})"
    end

    def status_codes
      @status_codes.to_codes
    end

    def matches_status_code?(status_code)
      @status_codes.matches?(status_code)
    end

  private

    def make_schema_strict!(raw_schema, modify_object=true)
      return unless Hash === raw_schema

      raw_schema.each do |key, value|
        make_schema_strict!(value, key != 'properties')
      end

      return unless modify_object

      raw_schema['additionalProperties'] ||= false
      raw_schema['required'] = !raw_schema.delete('optional')
    end
  end

  # Holds the acceptable status codes for an enpoint entry
  # Acceptable status code are either exact status codes (200, 404, etc)
  # or partial status codes (2xx, 3xx, 4xx, etc). Currently, partial status
  # codes can only be a digit followed by two lower-case x's.
  class StatusCodeMatcher
    attr_reader :codes

    def initialize(codes)
      @codes = parse_and_validate(codes)
    end

    def matches?(status_code)
      return true if codes.nil?

      status_code = status_code.to_s
      codes.each do |code|
        code_value = code[:value]
        code_type = code[:type]
        if code_type == :exact
          return true if code_value == status_code # exact match
        else # code_type == :partial
          return true if code_value[0] == status_code[0] # 2xx compare to 200 case
        end
      end
      return false
    end

    def to_codes
      return 'all status codes' if codes.nil?
      codes.map {|z| z[:value]}.join(',')
    end

    private
      def parse_and_validate(codes)
        return nil if codes.nil?
        [].tap do |arr|
          codes.each do |code|
            arr << {:value => code, :type => code_type_for(code)}
          end
        end
      end

      def code_type_for(code)
        # http://rubular.com/r/gvx8TztkRE - match either 3-digits or 1 digit then xx
        return :exact if code =~ /\d{3}/ # match 3 digits
        return :partial if code =~ /\dxx/ # match 1 digit then xx
        raise StatusCodeMatcherArgumentError, "#{code} is not a valid format"
      end
  end

  # Wraps an example for a particular endpoint entry.
  class EndpointExample
    attr_reader :data, :definition

    def initialize(data, definition)
      @data, @definition = data, definition
    end

    def validate!
      definition.validate_data!(data)
    end
  end
end
