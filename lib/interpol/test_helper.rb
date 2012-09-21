require 'interpol'
require 'rack/mock'
require 'interpol/request_params_parser'

module Interpol
  module TestHelper
    module Common
      def define_interpol_example_tests(&block)
        config = Configuration.default.customized_duplicate(&block)

        each_definition_from(config.endpoints) do |endpoint, definition|
          define_definition_test(endpoint, definition)

          each_example_from(definition) do |example, example_index|
            define_example_test(config, endpoint, definition, example, example_index)
          end
        end
      end

    private

      def each_definition_from(endpoints)
        endpoints.each do |endpoint|
          endpoint.definitions.each do |definition|
            yield endpoint, definition
          end
        end
      end

      def each_example_from(definition)
        definition.examples.each_with_index do |example, index|
          yield example, index
        end
      end

      def define_example_test(config, endpoint, definition, example, example_index)
        description = "#{endpoint.name} (v #{definition.version}) has " +
                      "valid data for example #{example_index + 1}"
        example = filtered_example(config, endpoint, example)
        define_test(description) { example.validate! }
      end

      def define_definition_test(endpoint, definition)
        return unless definition.request?

        description = "#{endpoint.name} (v #{definition.version}) request " +
                      "definition has valid params schema"
        define_test description do
          definition.request_params_parser # it will raise an error if it is invalid
        end
      end

      def filtered_example(config, endpoint, example)
        path = endpoint.route.gsub(':', '') # turn path params into static segments
        rack_env = ::Rack::MockRequest.env_for(path)
        example.apply_filters(config.filter_example_data_blocks, rack_env)
      end
    end

    module RSpec
      include Common

      def define_test(name, &block)
        it(name, &block)
      end
    end

    module TestUnit
      include Common

      def define_test(name, &block)
        define_method("test_#{name.gsub(/\W+/, '_')}", &block)
      end
    end
  end
end

