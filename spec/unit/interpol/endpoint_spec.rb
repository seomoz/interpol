require 'fast_spec_helper'
require 'interpol/endpoint'

module Interpol
  describe Endpoint do
    def build_hash(hash = {})
      {
        'name' => "the-name",
        'route' => nil,
        'method' => 'GET',
        'definitions' => []
      }.merge(hash)
    end

    %w[ name route ].each do |attr|
      it "initializes the #{attr}" do
        Endpoint.new(build_hash attr => 'value').send(attr).should eq('value')
      end
    end

    it 'initializes the HTTP method' do
      Endpoint.new(build_hash 'method' => 'PUT').method.should be(:put)
    end

    %w[ name route definitions method ].each do |attr|
      it "raises an error if not initialized with '#{attr}'" do
        hash = build_hash.reject { |k, v| k == attr }
        expect {
          Endpoint.new(hash)
        }.to raise_error(/key not found.*#{attr}/)
      end
    end

    it 'raises an error if the name contains invalid HTML element attribute characters' do
      expect {
        Endpoint.new(build_hash 'name' => "two words")
      }.to raise_error(ArgumentError)
    end

    it 'allows letters, digits, underscores and dashes in the name' do
      name = "abyz0123456789-_"
      Endpoint.new(build_hash 'name' => name) # should not raise an error
    end

    it 'raises an error if any definition lack versions' do
      expect {
        Endpoint.new(build_hash 'definitions' => [{}])
      }.to raise_error(/key not found.*versions/)
    end

    let(:definitions_array) do [{
      'versions' => ['3.2', '1.2'],
      'schema'   => {'the' => 'schema'},
      'examples' => ['e1', 'e2']
    }] end

    describe "#definitions" do
      it 'returns each definition object, ordered by version' do
        endpoint = Endpoint.new(build_hash('definitions' => definitions_array))
        endpoint.definitions.map(&:version).should eq(%w[ 1.2 3.2 ])
      end
    end

    describe "#available_versions" do
      it 'returns the list of available version strings, ordered by version' do
        endpoint = Endpoint.new(build_hash('definitions' => definitions_array))
        endpoint.available_versions.should eq(%w[ 1.2 3.2 ])
      end
    end

    describe "#find_definition!" do
      let(:hash) { build_hash('definitions' => definitions_array) }
      let(:endpoint) { Endpoint.new(hash) }

      it 'finds the definition matching the given version' do
        endpoint.find_definition!('1.2').version.should eq('1.2')
      end

      it 'raises an error when given a version that matches no definition' do
        expect {
          endpoint.find_definition!('2.1')
        }.to raise_error(ArgumentError)
      end
    end

    describe "#find_example_for!" do
      let(:hash) { build_hash('definitions' => definitions_array) }
      let(:endpoint) { Endpoint.new(hash) }

      it 'returns an example for the requested version' do
        endpoint.find_example_for!('1.2').data.should eq('e1')
      end

      it 'raises an error when given a version it does not have' do
        expect {
          endpoint.find_example_for!('2.1')
        }.to raise_error(ArgumentError)
      end
    end

    describe '#route_matches?' do
      def endpoint(route)
        hash = build_hash('route' => route)
        Endpoint.new(hash)
      end

      it 'correctly identifies an exact match' do
        endpoint('/foo/bar').route_matches?('/foo/bar').should be_true
      end

      it 'correctly identifies a non match' do
        endpoint('/foo/bar').route_matches?('/goo/bar').should be_false
      end

      it 'handles route params' do
        endpoint('/foo/:var/bar').route_matches?('/foo/17/bar').should be_true
      end

      it 'handles special regex chars in the route' do
        endpoint('/foo.bar').route_matches?('/foo.bar').should be_true
        endpoint('/foo.bar').route_matches?('/foo-bar').should be_false
      end

      it 'does not match a path with an extra prefix' do
        endpoint('/foo/bar').route_matches?('/bazz/foo/bar').should be_false
      end

      it 'does not match a path with an extra postfix' do
        endpoint('/foo/bar').route_matches?('/foo/bar/bazz').should be_false
      end
    end
  end

  describe EndpointDefinition do
    def build_hash(hash = {})
      {
        'schema'   => {'the' => 'schema'},
        'examples' => []
      }.merge(hash)
    end

    let(:version)  { '1.0' }

    it 'initializes the endpoint_name' do
      EndpointDefinition.new("e-name", version, build_hash).endpoint_name.should eq("e-name")
    end

    it 'initializes the version' do
      EndpointDefinition.new("name", '2.3', build_hash).version.should eq('2.3')
    end

    it 'initializes the example data' do
      v = EndpointDefinition.new("name", version, build_hash('examples' => [{'a' => 5}]))
      v.examples.map(&:data).should eq([{ 'a' => 5 }])
    end

    it 'initializes the schema' do
      v = EndpointDefinition.new("name", version, build_hash('schema' => {'the' => 'schema'}))
      v.schema['the'].should eq('schema')
    end

    %w[ examples schema ].each do |attr|
      it "raises an error if not initialized with '#{attr}'" do
        hash = build_hash.reject { |k, v| k == attr }
        expect {
          EndpointDefinition.new("name", version, hash)
        }.to raise_error(/key not found.*#{attr}/)
      end
    end

    describe "#validate_data" do
      let(:schema) do {
        'type'       => 'object',
        'properties' => {'foo' => { 'type' => 'integer' } }
      } end

      subject { EndpointDefinition.new("e-name", version, build_hash('schema' => schema)) }

      it 'raises a validation error when given data of the wrong type' do
        expect {
          subject.validate_data!('foo' => 'a string')
        }.to raise_error(ValidationError)
      end

      it 'does not raise an error when given valid data' do
        subject.validate_data!('foo' => 17)
      end

      it 'raises an error when the schema itself is invalid' do
        schema['properties']['foo']['minItems'] = 'foo'
        expect {
          subject.validate_data!('foo' => 17)
        }.to raise_error(ValidationError)
      end

      it 'requires all properties' do
        expect {
          subject.validate_data!({})
        }.to raise_error(ValidationError)
      end

      it 'does not require properties marked as optional' do
        schema['properties']['foo']['optional'] = true
        subject.validate_data!({})
      end

      it 'does not allow additional properties' do
        expect {
          subject.validate_data!('bar' => 3)
        }.to raise_error(ValidationError)
      end

      context 'a schema with nested objects' do
        before do
          schema['properties']['foo'] = {
            'type' => 'object',
            'properties' => { 'name' => { 'type' => 'integer' } }
          }
        end

        it 'requires all properties on nested objects' do
          expect {
            subject.validate_data!('foo' => {})
          }.to raise_error(ValidationError)
        end

        it 'does not raise an error when the data is valid' do
          subject.validate_data!('foo' => { 'name' => 3 })
        end

        it 'does not require nested properties marked as optional' do
          schema['properties']['foo']['properties']['name']['optional'] = true
          subject.validate_data!('foo' => {})
        end

        it 'does not allow additional properties on nested objects' do
          expect {
            subject.validate_data!('foo' => {'name' => 3, 'bar' => 7})
          }.to raise_error(ValidationError)
        end

        it 'allows additional properties if the additionalProperties property is set to true' do
          schema['properties']['foo']['additionalProperties'] = true
          subject.validate_data!('foo' => {'name' => 3, 'bar' => 7})
        end
      end

      context 'a schema with a nested array of nested objects' do
        before do
          schema['properties']['foo'] = {
            'type' => 'array',
            'items' => { 'type' => 'object',
              'properties' => { 'name' => { 'type' => 'integer' } }
            }
          }
        end

        it 'requires all properties on nested objects' do
          expect {
            subject.validate_data!('foo' => [{}])
          }.to raise_error(ValidationError)
        end

        it 'does not raise an error when the data is valid' do
          subject.validate_data!('foo' => [{ 'name' => 3 }])
        end

        it 'does not require nested properties marked as optional' do
          schema['properties']['foo']['items']['properties']['name']['optional'] = true
          subject.validate_data!('foo' => [{}])
        end

        it 'does not allow additional properties on nested objects' do
          expect {
            subject.validate_data!('foo' => [{'name' => 3, 'bar' => 7}])
          }.to raise_error(ValidationError)
        end
      end
    end
  end

  describe EndpointExample do
    describe "#validate!" do
      let(:definition) { fire_double("Interpol::EndpointDefinition") }
      let(:data)       { { "the" => "data" } }

      it 'validates against the schema' do
        definition.should_receive(:validate_data!).with(data)
        EndpointExample.new(data, definition).validate!
      end
    end
  end
end

