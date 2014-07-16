require 'fast_spec_helper'
require 'interpol'
require 'interpol/endpoint'

module Interpol
  RSpec.shared_examples_for "custom_metadata" do
    it "initializes custom_metadata from the meta field" do
      instance = new_with('meta' => {'key' => 'value'})
      expect(instance.custom_metadata).to eq('key' => 'value')
    end

    context "when no meta key is provided" do
      it "initializes custom_metadata to an empty hash" do
        expect(new_with({}).custom_metadata).to eq({})
      end
    end
  end

  RSpec.describe Endpoint do
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
        expect(Endpoint.new(build_hash attr => 'value').send(attr)).to eq('value')
      end
    end

    it_behaves_like "custom_metadata" do
      def new_with(hash)
        Endpoint.new(build_hash hash)
      end
    end

    it 'initializes the HTTP method' do
      expect(Endpoint.new(build_hash 'method' => 'PUT').method).to be(:put)
    end

    [:to_s, :inspect].each do |meth|
      it "provides a human-readable ##{meth} output" do
        endpoint = Endpoint.new(build_hash 'route' => '/foo')
        expect(endpoint.send(meth)).to eq("#<Interpol::Endpoint get /foo (the-name)>")
      end
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

    let(:request_definition_array) do [{
      'versions'      => ['1.1'],
      'message_type'  => 'request',
      'schema'        => {'a' => ' request schema'},
      'examples'      => ['e1', 'e2']
    }] end

    describe "#definitions" do
      it 'returns each definition object, ordered by version' do
        endpoint = Endpoint.new(build_hash('definitions' => definitions_array))
        expect(endpoint.definitions.map { |d| d.version }).to eq(%w[ 3.2 1.2 ])
      end

      it 'returns each definition object, ordered by message type' do
        full_definitions_array = (definitions_array + request_definition_array)
        endpoint = Endpoint.new(build_hash('definitions' => full_definitions_array))
        expect(endpoint.definitions.map { |d| d.version }).to eq(%w[ 1.1 3.2 1.2 ])
        message_types = endpoint.definitions.map { |d| d.message_type }
        expect(message_types).to eq(%w[ request response response ])
      end

    end

    describe "#available_request_versions" do
      let(:endpoint) do
        Endpoint.new(build_hash('definitions' => definitions_array + request_definition_array))
      end

      it 'returns the list of available request version strings' do
        expect(endpoint.available_request_versions).to match_array(%w[ 1.1 ])
      end
    end

    describe "#available_response_versions" do
      let(:endpoint) do
        Endpoint.new(build_hash('definitions' => definitions_array + request_definition_array))
      end

      it 'returns the list of available response version strings' do
        expect(endpoint.available_response_versions).to match_array(%w[ 3.2 1.2 ])
      end
    end

    describe "#find_definition!" do
      let(:hash) { build_hash('definitions' => definitions_array) }
      let(:endpoint) { Endpoint.new(hash) }

      it 'finds the definition matching the given version and message_type' do
        definition = endpoint.find_definition!('1.2', 'response')
        expect(definition.version).to eq('1.2')
        expect(definition.message_type).to eq('response')
      end

      it 'raises an error when given a version that matches no definition' do
        expect {
          endpoint.find_definition!('2.1', 'response')
        }.to raise_error(NoEndpointDefinitionFoundError)
      end

      it 'raises an error if multiple definitions match its parameters' do
        hash['definitions'] += definitions_array
        expect {
          endpoint.find_definition!('1.2', 'response')
        }.to raise_error(MultipleEndpointDefinitionsFoundError)
      end
    end

    describe '#route_matches?' do
      def endpoint(route)
        hash = build_hash('route' => route)
        Endpoint.new(hash)
      end

      it 'correctly identifies an exact match' do
        expect(endpoint('/foo/bar').route_matches?('/foo/bar')).to be true
      end

      it 'can match when there is a trailing slash' do
        expect(endpoint('/foo/bar').route_matches?('/foo/bar/')).to be true
      end

      it 'correctly identifies a non match' do
        expect(endpoint('/foo/bar').route_matches?('/goo/bar')).to be false
      end

      it 'handles route params' do
        expect(endpoint('/foo/:var/bar').route_matches?('/foo/17/bar')).to be true
      end

      it 'handles special regex chars in the route' do
        expect(endpoint('/foo.bar').route_matches?('/foo.bar')).to be true
        expect(endpoint('/foo.bar').route_matches?('/foo-bar')).to be false
      end

      it 'does not match a path with an extra prefix' do
        expect(endpoint('/foo/bar').route_matches?('/bazz/foo/bar')).to be false
      end

      it 'does not match a path with an extra postfix' do
        expect(endpoint('/foo/bar').route_matches?('/foo/bar/bazz')).to be false
      end
    end

    describe "#configuration" do
      it 'defaults to the Interpol default config' do
        endpoint = Endpoint.new(build_hash)
        expect(endpoint.configuration).to be(Interpol.default_configuration)
      end

      it 'allows a config instance to be passed' do
        config = Configuration.new
        endpoint = Endpoint.new(build_hash, config)
        expect(endpoint.configuration).to be(config)
      end
    end
  end

  RSpec.describe EndpointDefinition do
    def build_hash(hash = {})
      {
        'schema'   => {'the' => 'schema'},
        'examples' => []
      }.merge(hash)
    end

    let(:version)  { '1.0' }
    let(:config)   { Configuration.new }
    let(:endpoint) do
      instance_double("Interpol::Endpoint", :name => 'my-endpoint',
                  :configuration => config).as_null_object
    end

    it 'initializes the endpoint' do
      endpoint_def = EndpointDefinition.new(endpoint, version, 'response', build_hash)
      expect(endpoint_def.endpoint).to be(endpoint)
    end

    it 'exposes the endpoint name' do
      allow(endpoint).to receive(:name).and_return('e-name')
      endpoint_def = EndpointDefinition.new(endpoint, version, 'response', build_hash)
      expect(endpoint_def.endpoint_name).to eq('e-name')
    end

    it 'initializes the version' do
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'response', build_hash)
      expect(endpoint_def.version).to eq('2.3')
    end

    it 'default initialized the message type' do
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'response', build_hash)
      expect(endpoint_def.message_type).to eq('response')
    end

    it 'initializes the message type' do
      hash = build_hash('message_type' => 'request')
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'request', hash)
      expect(endpoint_def.message_type).to eq('request')
    end

    it 'provides a readable description for a request definition' do
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'request', build_hash)
      expect(endpoint_def.description).to eq("#{endpoint.name} (request v. 2.3)")
    end

    it 'provides a readable description for a response definition' do
      hash = build_hash('status_codes' => ['2xx'])
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'response', hash)
      expect(endpoint_def.description).to eq("#{endpoint.name} (response v. 2.3 for status: 2xx)")
    end

    it 'initializes the example data' do
      hash = build_hash('examples' => [{'a' => 5}])
      v = EndpointDefinition.new(endpoint, version, 'response', hash)
      expect(v.examples.map(&:data)).to eq([{ 'a' => 5 }])
    end

    it 'initializes the schema' do
      hash = build_hash('schema' => {'the' => 'schema'})
      v = EndpointDefinition.new(endpoint, version, 'response', hash)
      expect(v.schema['the']).to eq('schema')
    end

    %w[ examples schema ].each do |attr|
      it "raises an error if not initialized with '#{attr}'" do
        hash = build_hash.reject { |k, v| k == attr }
        expect {
          EndpointDefinition.new(endpoint, version, 'response', hash)
        }.to raise_error(/key not found.*#{attr}/)
      end
    end

    %w[ path_params query_params ].each do |attr|
      it "initializes #{attr} to a default hash if no value is provided" do
        v = EndpointDefinition.new(endpoint, version, 'response', build_hash)
        expect(v.send(attr)).to eq(EndpointDefinition::DEFAULT_PARAM_HASH)
      end
    end

    %w[ path_params query_params ].each do |attr|
      it "initializes #{attr} to the provided value" do
        params = {'key' => 'param'}
        hash = build_hash(attr => params)
        v = EndpointDefinition.new(endpoint, version, 'response', hash)
        expect(v.send(attr)).to eq(params)
      end
    end

    it_behaves_like "custom_metadata" do
      def new_with(hash)
        EndpointDefinition.new(endpoint, version, 'response', build_hash(hash))
      end
    end

    describe "#request?" do
      it 'returns true if message_type == request' do
        ed = EndpointDefinition.new(endpoint, version, 'request', build_hash)
        expect(ed).to be_request
      end

      it 'returns false if message_type == response' do
        ed = EndpointDefinition.new(endpoint, version, 'response', build_hash)
        expect(ed).not_to be_request
      end

      it 'returns false if message_type == something else' do
        ed = EndpointDefinition.new(endpoint, version, 'something_else', build_hash)
        expect(ed).not_to be_request
      end
    end

    it 'does not mutate the given schema when making it strict' do
      new_basic_schema = lambda { {
        'type'       => 'object',
        'properties' => {'foo' => { 'type' => 'integer' } }
      } }

      schema = new_basic_schema.call
      EndpointDefinition.new(endpoint, version, 'response', build_hash('schema' => schema))
      expect(schema).to eq(new_basic_schema.call)
    end

    describe "#validate_data" do
      let(:schema) do {
        'type'       => 'object',
        'properties' => {'foo' => { 'type' => 'integer' } }
      } end

      subject {
        EndpointDefinition.new(endpoint, version, 'response', build_hash('schema' => schema))
      }

      it 'raises a validation error when given data of the wrong type' do
        expect {
          subject.validate_data!('foo' => 'a string')
        }.to raise_error(ValidationError)
      end

      it 'does not raise an error when given valid data' do
        subject.validate_data!('foo' => 17)
      end

      context 'invalid schema' do
        before { schema['properties']['foo']['minItems'] = 'foo' }

        it 'raises an error when the schema itself is invalid' do
          expect {
            subject.validate_data!('foo' => 17)
          }.to raise_error(ValidationError, /Data:\s+{"/m)
        end

        it 'does not raise an invalid schema error if schema validation is disabled' do
          schema['properties']['foo']['minItems'] = 'foo'
          expect {
            subject.validate_data!({ 'foo' => 17 }, false)
          }.to_not raise_error
        end
      end

      it 'rejects unrecognized data types' do
        schema['properties']['foo']['type'] = 'sting'
        expect {
          subject.validate_data!('foo' => 'bar')
        }.to raise_error(ValidationError)
      end

      let(:date_time_string) { "2012-12-12T08:23:12Z" }

      it 'rejects unrecognized format options' do
        schema['properties']['foo']['type'] = 'string'
        schema['properties']['foo']['format'] = 'timestamp' # the valid format is date-time

        expect {
          subject.validate_data!('foo' => date_time_string)
        }.to raise_error(ValidationError, %r|'#/properties/foo/format' value "timestamp"|)
      end

      it 'allows recognized format options' do
        schema['properties']['foo']['type'] = 'string'
        schema['properties']['foo']['format'] = 'date-time'

        expect {
          subject.validate_data!('foo' => date_time_string)
        }.not_to raise_error
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

      it 'does not require optional nullable properties' do
        schema['properties']['foo'].merge!('optional' => true, 'nullable' => true)
        subject.validate_data!({})
      end

      it 'does not allow additional properties' do
        expect {
          subject.validate_data!('bar' => 3)
        }.to raise_error(ValidationError)
      end

      context 'when scalars_nullable_by_default is set to true' do
        before { config.scalars_nullable_by_default = true }

        it 'allows nulls even when the property does not explicitly allow it' do
          expect {
            subject.validate_data!('foo' => nil)
          }.not_to raise_error
        end

        it 'works with existing union types' do
          schema['properties']['foo']['type'] = %w[ integer string ]

          expect { subject.validate_data!('foo' => 123) }.not_to raise_error
          expect { subject.validate_data!('foo' => 'a') }.not_to raise_error
          expect { subject.validate_data!('foo' => nil) }.not_to raise_error
        end

        it 'works with enums' do
          schema['properties']['foo'] = {
            'type' => 'string',
            'enum' => %w[ A B C D F ]
          }

          expect { subject.validate_data!('foo' => nil) }.not_to raise_error
          expect { subject.validate_data!('foo' => 'A') }.not_to raise_error
          expect { subject.validate_data!('foo' => 'F') }.not_to raise_error
          expect { subject.validate_data!('foo' => 'E') }.to raise_error(ValidationError)
        end

        it 'allows enums to be non-nullable' do
          schema['properties']['foo'] = {
            'nullable' => false,
            'type' => 'string',
            'enum' => %w[ A B C D F ]
          }

          expect { subject.validate_data!('foo' => nil) }.to raise_error(ValidationError)
        end

        it 'does not add an extra `null` entry to an existing nullable union type' do
          schema['properties']['foo']['type'] = %w[ integer null ]

          expect(::JSON::Validator).to receive(:fully_validate_schema) do |schema|
            expect(schema['properties']['foo']['type']).to match_array(%w[ integer null ])
            [] # no errors
          end

          subject.validate_data!('foo' => nil)
        end

        it 'does not add an extra `null` entry to an existing nullable scalar type' do
          schema['properties']['foo']['type'] = 'null'

          expect(::JSON::Validator).to receive(:fully_validate_schema) do |schema|
            expect(schema['properties']['foo']['type']).to eq('null')
            [] # no errors
          end

          subject.validate_data!('foo' => nil)
        end

        it 'does not allow nulls when the property has `nullable: false`' do
          schema['properties']['foo']['nullable'] = false

          expect {
            subject.validate_data!('foo' => nil)
          }.to raise_error(ValidationError)
        end

        it 'does not automatically make arrays nullable' do
          schema['properties']['foo']['type'] = 'array'

          expect {
            subject.validate_data!('foo' => [1])
          }.not_to raise_error

          expect {
            subject.validate_data!('foo' => nil)
          }.to raise_error(ValidationError)
        end

        it 'does not automatically make objects nullable' do
          schema['properties']['foo']['type'] = 'object'

          expect {
            subject.validate_data!('foo' => { 'a' => 3 })
          }.not_to raise_error

          expect {
            subject.validate_data!('foo' => nil)
          }.to raise_error(ValidationError)
        end

        it 'does not make unioned types that include non-scalars nullable' do
          schema['properties']['foo']['type'] = %w[ object array integer ]

          expect {
            subject.validate_data!('foo' => { 'a' => 3 })
          }.not_to raise_error

          expect {
            subject.validate_data!('foo' => 3)
          }.not_to raise_error

          expect {
            subject.validate_data!('foo' => [])
          }.not_to raise_error

          expect {
            subject.validate_data!('foo' => nil)
          }.to raise_error(ValidationError)
        end
      end

      context 'when scalars_nullable_by_default is set to false' do
        before { config.scalars_nullable_by_default = false }

        it 'does not allow nulls by default' do
          expect {
            subject.validate_data!('foo' => nil)
          }.to raise_error(ValidationError)
        end

        it 'allow nulls when the property has `nullable: true`' do
          schema['properties']['foo']['nullable'] = true

          expect {
            subject.validate_data!('foo' => nil)
          }.not_to raise_error
        end
      end

      context 'a schema with nested objects' do
        before do
          schema['properties']['foo'] = {
            'type' => 'object',
            'properties' => { 'name' => { 'type' => 'integer' } }
          }
        end

        it 'allows sub-properties to be nullable' do
          schema['properties']['foo']['properties']['name']['nullable'] = true

          expect {
            subject.validate_data!('foo' => { 'name' => nil })
          }.not_to raise_error
        end

        it 'does not make sub-properties nullable by default' do
          expect {
            subject.validate_data!('foo' => { 'name' => nil })
          }.to raise_error(ValidationError)
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

        context 'when scalars_nullable_by_default is set to true' do
          before { config.scalars_nullable_by_default = true }

          it 'allows nulls for nested sub properties' do
            expect {
              subject.validate_data!('foo' => [{ 'name' => nil }])
            }.not_to raise_error
          end

          it 'works when there is actually a type property' do
            schema['properties']['foo']['items']['properties']['type'] = {
              'type' => 'string'
            }

            expect {
              subject.validate_data!('foo' => [{ 'name' => 3, 'type' => 'integer' }])
            }.not_to raise_error

            expect {
              subject.validate_data!('foo' => [{ 'name' => 3, 'type' => nil }])
            }.not_to raise_error
          end
        end
      end

      context 'a schema with an array of union types' do
        before do
          schema['properties']['foo'] = {
            'type' => 'array',
            'items' => {
              'type' => [
                { 'type' => 'object', 'properties' => {
                  'class' => { 'type' => 'string', 'enum' => ['integer'] },
                  'num' => { 'type' => 'integer' } }
                },
                { 'type' => 'object', 'properties' => {
                  'class' => { 'type' => 'string', 'enum' => ['text'] },
                  'text' => { 'type' => 'string' } }
                }
              ]
            }
          }
        end

        it 'does not raise an error when the data is valid' do
          subject.validate_data!('foo' => [
                                 { 'class' => 'integer', 'num' => 3 },
                                 { 'class' => 'text', 'text' => 'blah' } ])
        end

        it 'raises an error when a subtype has an invalid property value' do
          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer', 'num' => 'string' },
                                   { 'class' => 'text', 'text' => 'blah' } ])
          }.to raise_error(ValidationError,
               %r|'#/foo/0/num' of type String did not match the following type: integer|)

          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer', 'num' => 3 },
                                   { 'class' => 'text', 'text' => 4 } ])
          }.to raise_error(ValidationError,
               %r|'#/foo/1/text' of type Fixnum did not match the following type: string|)
        end

        it 'raises an error if a subtype is missing a property' do
          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer' },
                                   { 'class' => 'text', 'text' => 'blah' } ])
          }.to raise_error(ValidationError,
               %r|'#/foo/0' did not contain a required property of 'num'|)

          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer', 'num' => 3 },
                                   { 'class' => 'text' } ])
          }.to raise_error(ValidationError,
               %r|'#/foo/1' did not contain a required property of 'text'|)
        end

        it 'raises an error if a subtype has additional properties' do
          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer', 'num' => 3, 'extra' => 4 },
                                   { 'class' => 'text', 'text' => 'blah' } ])
          }.to raise_error(ValidationError,
               %r|'#/foo/0' contains additional properties \["extra"\] outside of the schema|)

          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer', 'num' => 3 },
                                   { 'class' => 'text', 'text' => 'blah', 'other' => 'a' } ])
          }.to raise_error(ValidationError,
               %r|'#/foo/1' contains additional properties \["other"\] outside of the schema|)
        end

        it 'allows additional properties if the additionalProperties property is set to true' do
          schema['properties']['foo']['items']['type'].first['additionalProperties'] = true

          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer', 'num' => 3, 'extra' => 4 },
                                   { 'class' => 'text', 'text' => 'blah' } ])
          }.not_to raise_error
        end

        it 'does not require nested properties marked as optional' do
          schema['properties']['foo']['items']['type'].first['properties']['num']['optional'] = true

          expect {
            subject.validate_data!('foo' => [
                                   { 'class' => 'integer' },
                                   { 'class' => 'text', 'text' => 'blah' } ])
          }.not_to raise_error
        end
      end
    end
  end

  RSpec.describe StatusCodeMatcher do
    describe "#new" do
      it 'initializes the codes for nil' do
        expect(StatusCodeMatcher.new(nil).code_strings).to eq ['xxx']
      end

      it 'initializs the codes for a single code' do
        expect(StatusCodeMatcher.new(['200']).code_strings).to eq ["200"]
      end

      it 'initializs the codes for a multiple codes' do
        code_strings = StatusCodeMatcher.new(['200', '4xx', 'x0x']).code_strings
        expect(code_strings).to eq ['200', '4xx', 'x0x']
      end

      it 'should raise an error for invalid status code formats' do
        expect {
          StatusCodeMatcher.new(['200', '4y4'])
        }.to raise_error(StatusCodeMatcherArgumentError)

        expect {
          StatusCodeMatcher.new(['2000', '404'])
        }.to raise_error(StatusCodeMatcherArgumentError)
      end
    end

    describe "#matches?" do
      let(:nil_codes_subject) { StatusCodeMatcher.new(nil) }
      it 'returns true when codes is nil' do
        expect(nil_codes_subject.matches?('200')).to be true
      end

      subject { StatusCodeMatcher.new(['200', '4xx', 'x5x']) }
      it 'returns true for an exact match' do
        expect(subject.matches?('200')).to be true
      end

      it 'returns true for a partial matches' do
        expect(subject.matches?('401')).to be true
        expect(subject.matches?('454')).to be true
      end

      it 'returns false for no matches' do
        expect(subject.matches?('202')).to be false
      end
    end

    describe '#example_status_code' do
      it 'returns a valid example status code when a specific status code was given' do
        expect(StatusCodeMatcher.new(['404']).example_status_code).to eq '404'
      end

      it 'returns a valid example status code when no status codes were given' do
        expect(StatusCodeMatcher.new(nil).example_status_code).to eq '200'
      end

      it 'returns a valid example status code based on the first status code' do
        expect(StatusCodeMatcher.new(['4xx', 'x0x']).example_status_code).to eq '400'
      end
    end
  end

  RSpec.describe EndpointExample do

    let(:definition) { instance_double("Interpol::EndpointDefinition") }
    let(:data)       { { "the" => "data" } }
    let(:example)    { EndpointExample.new(data, definition) }

    describe "#validate!" do
      it 'validates against the schema' do
        expect(definition).to receive(:validate_data!).with(data)
        example.validate!
      end
    end

    describe '#apply_filters' do
      let(:filter_1) { lambda { |ex, request_env| ex.data["the"] = "data1" } }
      let(:request_env) { { "a" => "hash" } }

      it 'applies a filter and returns modified data' do
        modified_example = example.apply_filters([filter_1], request_env)
        expect(modified_example.data).to eq("the" => "data1")
      end

      it 'chains multiple filters, passing the modified example onto each' do
        filter_2 = lambda do |ex, request_env|
          expect(ex.data).to eq("the" => "data1")
          ex.data["the"].upcase!
        end

        modified_example = example.apply_filters([filter_1, filter_2], request_env)
        expect(modified_example.data).to eq("the" => "DATA1")
      end

      it 'does not modify the original example hash' do
        data_1 = { "hash" => { "a" => 5 }, "array" => [1, { "b" => 6 }] }
        data_2 = { "hash" => { "a" => 5 }, "array" => [1, { "b" => 6 }] }

        example = EndpointExample.new(data_1, definition)
        filter = lambda do |ex, request_env|
          ex.data["other"] = :foo
          ex.data["hash"]["a"] = 6
          ex.data["array"].last["c"] = 3
          ex.data["array"] << 0
        end

        example.apply_filters([filter], request_env)
        expect(example.data).to eq(data_2)
      end

      it 'does not modify the original example array' do
        data_1 = [1, { "b" => 6 }]
        data_2 = [1, { "b" => 6 }]

        example = EndpointExample.new(data_1, definition)
        filter = lambda do |ex, request_env|
          ex.data.last["c"] = 3
          ex.data << 0
        end

        example.apply_filters([filter], request_env)
        expect(example.data).to eq(data_2)
      end

      it 'returns an unmodified example when given no filters' do
        example.apply_filters([], request_env)
        expect(example.data).to eq(data)
      end

      it 'passes the given request_env onto the filters' do
        passed_request_env = nil
        filter = lambda do |_, req_env|
          passed_request_env = req_env
        end

        example.apply_filters([filter], :the_request_env)
        expect(passed_request_env).to be(:the_request_env)
      end
    end
  end
end

