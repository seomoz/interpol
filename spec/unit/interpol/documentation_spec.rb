require 'fast_spec_helper'
require 'interpol/documentation'

module Interpol
  describe Documentation do
    let(:address_schema) do
      {"first_name"=>
        {"description"=>"The person's first name.",
         "type"=>"string",
         "additionalProperties"=>false,
         "required"=>true},
       "last_name"=>
        {"description"=>"The person's last name.",
         "type"=>"string",
         "additionalProperties"=>false,
         "required"=>true},
       "date_of_birth"=>
        {"description"=>"The person's birthday.",
         "type"=>"date",
         "additionalProperties"=>false,
         "required"=>true},
       "gender"=>
        {"description"=>"Male or Female",
         "type"=>"string",
         "enum"=>["male", "female"],
         "additionalProperties"=>false,
         "required"=>true},
       "address"=>
        {"description"=>"The person's mailing address",
         "type"=>"object",
         "properties"=>
          {"street"=>
            {"description"=>"Street address",
             "type"=>"string",
             "additionalProperties"=>false,
             "required"=>true},
           "city"=>
            {"type"=>"string", "additionalProperties"=>false, "required"=>true},
           "state"=>
            {"type"=>"string", "additionalProperties"=>false, "required"=>true},
           "zip"=>
            {"description"=>"Zip code",
             "type"=>"string",
             "additionalProperties"=>false,
             "required"=>true}},
         "additionalProperties"=>false,
         "required"=>true}}
    end

    shared_examples_for "schema rendering" do |root_properties_dom|
      let(:html) { Documentation.html_for_schema(schema) }
      let(:parsed_html) { Nokogiri::HTML::DocumentFragment.parse(html) }

      it 'includes the schema description if it is present' do
        parsed_html.css('h3.description').first.content.should eq(schema.fetch('description'))
      end

      it 'does not include a description element if there is no description' do
        schema.delete('description')
        parsed_html.css('h3.description').first.should be_nil
      end

      it 'renders properties' do
        parsed_html.css("#{root_properties_dom} > .name").map(&:content).should =~ [
          "first_name (string)",
          "last_name (string)",
          "date_of_birth (date)",
          "gender (string)",
          "address (object)"
        ]
      end

      it 'renders nested properties' do
        parsed_html.css('.properties .properties .name').map(&:content).should =~ [
          "street (string)",
          "city (string)",
          "state (string)",
          "zip (string)"
        ]
      end
    end

    describe ".html_for_schema" do
      context "for an array schema" do
        let(:schema) do
          {"description"=>"Returns information about a contact.",
           "type"=>"array",
           "items"=>
            {"properties"=>address_schema,
             "additionalProperties"=>false,
             "description" => "One contact",
             "required"=>true} }
        end

        it_behaves_like "schema rendering", ".schema-definition > .items > .properties"
      end

      context "for an object schema" do
        let(:schema) do
          {"description"=>"Returns information about a contact.",
           "type"=>"object",
           "properties"=>address_schema,
           "additionalProperties"=>false,
           "required"=>true}
        end

        it_behaves_like "schema rendering", '.schema-definition > .properties'
      end
    end
  end
end

