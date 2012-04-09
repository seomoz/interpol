require 'nokogiri'

module Interpol
  module Documentation
    extend self

    def html_for_schema(schema)
      ForSchemaDefinition.new(schema).to_html
    end

    # Renders the documentation for a schema definition.
    class ForSchemaDefinition
      def initialize(schema)
        @schema = schema
      end

      def to_html
        build do |doc|
          schema_definition(doc, @schema)
        end.to_html
      end

    private

      def build
        Nokogiri::HTML::DocumentFragment.parse("").tap do |doc|
          Nokogiri::HTML::Builder.with(doc) do |doc|
            yield doc
          end
        end
      end

      def schema_description(doc, schema)
        return unless schema.has_key?('description')
        doc.h3(class: "description") { doc.text(schema['description']) }
      end

      def schema_definition(doc, schema)
        doc.div(class: "schema-definition") do
          schema_description(doc, schema)
          render_properties(doc, Array(schema['properties']))
        end
      end

      def render_properties(doc, properties)
        return if properties.none?

        doc.dl(class: "properties") do
          properties.each do |name, property|
            property_definition(doc, name, property)
          end
        end
      end

      def property_definition(doc, name, property)
        doc.dt(class: "name") { doc.text(property_title name, property) }

        if property.has_key?('description')
          doc.dd { doc.text(property['description']) }
        end

        render_properties(doc, Array(property['properties']))
      end

      def property_title(name, property)
        return name unless property['type']
        "#{name} (#{property['type']})"
      end
    end
  end
end
