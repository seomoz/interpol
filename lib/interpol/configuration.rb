require 'interpol/endpoint'
require 'interpol/errors'
require 'yaml'

module Interpol
  # Public: Defines interpol configuration.
  class Configuration
    attr_reader :endpoint_definition_files, :endpoints

    def initialize
      api_version do
        raise ConfigurationError, "api_version has not been configured"
      end
    end

    def endpoint_definition_files=(files)
      @endpoints = files.map do |file|
        Endpoint.new(YAML.load_file file)
      end
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

