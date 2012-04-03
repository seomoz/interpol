require 'interpol/configuration'

module Interpol
  module TestHelper
    module Common
      def each_example_from(endpoints)
        endpoints.each do |endpoint|
          endpoint.definitions.each do |definition|
            definition.examples.each_with_index do |example, index|
              yield endpoint, definition, example, index
            end
          end
        end
      end

      def define_interpol_example_tests
        config = Configuration.new
        yield config

        each_example_from(config.endpoints) do |endpoint, definition, example, example_index|
          description = "#{endpoint.name} (v #{definition.version}) has " +
                        "valid data for example #{example_index + 1}"
          define_test(description) { example.validate! }
        end
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

