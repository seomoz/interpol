require 'interpol/endpoint'
require 'yaml'

module Interpol
  # Public: Defines interpol configuration.
  class Configuration
    attr_reader :endpoint_definition_files, :endpoints

    def endpoint_definition_files=(files)
      @endpoints = files.map do |file|
        Endpoint.new(YAML.load_file file)
      end
      @endpoint_definition_files = files
    end
  end
end

