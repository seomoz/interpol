require 'interpol/endpoint'
require 'interpol/errors'
require 'yaml'

module Interpol
  module DefinitionFinder
    include HashFetcher
    NoDefinitionFound = Class.new

    def find_definition(options)
      method, path, version = extract_search_options_from(options)
      endpoint = find { |e| e.method == method && e.route_matches?(path) }
      return NoDefinitionFound if endpoint.nil?
      endpoint.definitions.find { |d| d.version == version } || NoDefinitionFound
    end

  private

    def extract_search_options_from(options)
      method  = fetch_from(options, :method).downcase.to_sym
      path    = fetch_from(options, :path)
      version = fetch_from(options, :version)

      return method, path, version
    end
  end

  # Public: Defines interpol configuration.
  class Configuration
    attr_reader :endpoint_definition_files, :endpoints

    def initialize
      api_version do
        raise ConfigurationError, "api_version has not been configured"
      end
      self.endpoint_definition_files = []
      yield self if block_given?
    end

    def endpoint_definition_files=(files)
      @endpoints = files.map do |file|
        Endpoint.new(YAML.load_file file)
      end.extend(DefinitionFinder)
      @endpoint_definition_files = files
    end

    def api_version(version=nil, &block)
      if [version, block].compact.size.even?
        raise ConfigurationError.new("api_version requires a static version " +
                                     "or a dynamic block, but not both")
      end

      @api_version_block = block || lambda { |env| version }
    end

    def api_version_for(rack_env_hash)
      @api_version_block.call(rack_env_hash).to_s
    end
  end
end

