require 'interpol'
require 'rack/mock'

module Interpol
  module TestHelper
    module Common
      def define_interpol_example_tests(&block)
        config = Configuration.default.customized_duplicate(&block)

        each_example_from(config.endpoints) do |endpoint, definition, example, example_index|
          description = "#{endpoint.name} (v #{definition.version}) has " +
                        "valid data for example #{example_index + 1}"
          example = filtered_example(config, endpoint, example)
          define_test(description) { example.validate! }
        end
      end

    private

      def each_example_from(endpoints)
        endpoints.each do |endpoint|
          endpoint.definitions.each do |definitions|
            definitions.each do |definition|
              definition.examples.each_with_index do |example, index|
                yield endpoint, definition, example, index
              end
            end
          end
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

