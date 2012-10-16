require 'interpol/endpoint'
require 'interpol/errors'
require 'yaml'
require 'interpol/configuration_ruby_18_extensions'  if RUBY_VERSION.to_f < 1.9

module Interpol
  module DefinitionFinder
    include HashFetcher
    NoDefinitionFound = Class.new

    def find_definition(method, path, message_type, status_code = nil)
      with_endpoint_matching(method, path) do |endpoint|
        version = yield endpoint
        find_definitions_for(endpoint, version, message_type).find do |definition|
          definition.matches_status_code?(status_code)
        end
      end
    end

  private

    def find_definitions_for(endpoint, version, message_type)
      endpoint.find_definition(version, message_type) { [] }
    end

    def with_endpoint_matching(method, path)
      method = method.downcase.to_sym
      endpoint = find { |e| e.method == method && e.route_matches?(path) }
      (yield endpoint if endpoint) || NoDefinitionFound
    end
  end

  # Public: Defines interpol configuration.
  class Configuration
    attr_reader :endpoint_definition_files, :endpoints, :filter_example_data_blocks
    attr_accessor :validation_mode, :documentation_title, :endpoint_definition_merge_key_files

    def initialize
      self.endpoint_definition_files = []
      self.endpoint_definition_merge_key_files = []
      self.documentation_title = "API Documentation Provided by Interpol"
      register_default_callbacks
      @filter_example_data_blocks = []

      yield self if block_given?
    end

    def endpoint_definition_files=(files)
      self.endpoints = files.map do |file|
        Endpoint.new(deserialized_hash_from file)
      end
      @endpoint_definition_files = files
    end

    def endpoints=(endpoints)
      @endpoints = endpoints.extend(DefinitionFinder)
    end

    [:request, :response].each do |type|
      class_eval <<-EOEVAL, __FILE__, __LINE__ + 1
        def #{type}_version(version = nil, &block)
          if [version, block].compact.size.even?
            raise ConfigurationError.new("#{type}_version requires a static version " +
                                         "or a dynamic block, but not both")
          end

          @#{type}_version_block = block || lambda { |*a| version }
        end

        def #{type}_version_for(rack_env, *extra_args)
          @#{type}_version_block.call(rack_env, *extra_args).to_s
        end
      EOEVAL
    end

    def api_version(version=nil, &block)
      warn "WARNING: Interpol's #api_version config option is deprecated. " +
           "Instead, use separate #request_version and #response_version " +
           "config options."

      request_version(version, &block)
      response_version(version, &block)
    end

    def validate_if(&block)
      @validate_if_block = block
    end

    def validate?(*args)
      @validate_if_block.call(*args)
    end

    def on_unavailable_request_version(&block)
      @unavailable_request_version_block = block
    end

    def request_version_unavailable(execution_context, *args)
      execution_context.instance_exec(*args, &@unavailable_request_version_block)
    end

    def on_invalid_sinatra_request_params(&block)
      @invalid_sinatra_request_params_block = block
    end

    def sinatra_request_params_invalid(execution_context, *args)
      execution_context.instance_exec(*args, &@invalid_sinatra_request_params_block)
    end

    def filter_example_data(&block)
      filter_example_data_blocks << block
    end

    def self.default
      @default ||= Configuration.new
    end

    def customized_duplicate(&block)
      block ||= lambda { |c| }
      dup.tap(&block)
    end

  private

    # 1.9 version
    include Module.new {
      BAD_ALIAS_ERROR = defined?(::Psych::BadAlias) ?
                          ::Psych::BadAlias : TypeError
      def deserialized_hash_from(file)
        YAML.load(yaml_content_for file)
      rescue BAD_ALIAS_ERROR => e
        raise ConfigurationError.new \
          "Received an error while loading YAML from #{file}: \"" +
          "#{e.class}: #{e.message}\" If you are using YAML merge keys " +
          "to declare shared types, you must configure endpoint_definition_merge_key_files " +
          "before endpoint_definition_files.", e
      end
    }

    # Needed to override deserialized_hash_from for Ruby 1.8
    include Interpol::ConfigurationRuby18Extensions  if RUBY_VERSION.to_f < 1.9

    def yaml_content_for(file)
      File.read(file).gsub(/\A---\n/, "---\n" + endpoint_merge_keys + "\n\n")
    end

    def endpoint_merge_keys
      @endpoint_merge_keys ||= endpoint_definition_merge_key_files.map { |f|
        File.read(f).gsub(/\A---\n/, '')
      }.join("\n\n")
    end

    def register_default_callbacks
      request_version do
        raise ConfigurationError, "request_version has not been configured"
      end

      response_version do
        raise ConfigurationError, "response_version has not been configured"
      end

      validate_if do |env, status, headers, body|
        headers['Content-Type'].to_s.include?('json') &&
        status >= 200 && status <= 299 && status != 204 # No Content
      end

      on_unavailable_request_version do |requested, available|
        message = "The requested API version is invalid. " +
                  "Requested: #{requested}. " +
                  "Available: #{available}"
        halt 406, JSON.dump(:error => message)
      end

      on_invalid_sinatra_request_params do |error|
        halt 400, JSON.dump(:error => error.message)
      end
    end
  end
end

