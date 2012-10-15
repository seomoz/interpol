require 'interpol'

Interpol.default_configuration do |config|
  definitions_dir = File.expand_path("../definitions", __FILE__)
  config.endpoint_definition_files = Dir["#{definitions_dir}/*.yml"]
  config.response_version '1.0'
  config.documentation_title = 'Contacts API Documentation'
end
