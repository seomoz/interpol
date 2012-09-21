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

    let(:request_definition_array) do [{
      'versions'      => ['1.1'],
      'message_type'  => 'request',
      'schema'        => {'a' => ' request schema'},
      'examples'      => ['e1', 'e2']
    }] end

    describe "#definitions" do
      it 'returns each definition object, ordered by version' do
        endpoint = Endpoint.new(build_hash('definitions' => definitions_array))
        endpoint.definitions.map { |d| d.version }.should eq(%w[ 3.2 1.2 ])
      end

      it 'returns each definition object, ordered by message type' do
        full_definitions_array = (definitions_array + request_definition_array)
        endpoint = Endpoint.new(build_hash('definitions' => full_definitions_array))
        endpoint.definitions.map { |d| d.version }.should eq(%w[ 1.1 3.2 1.2 ])
        endpoint.definitions.map { |d| d.message_type }.should eq(%w[ request response response ])
      end

    end

    describe "#available_versions" do
      it 'returns the list of available version strings, ordered by version' do
        endpoint = Endpoint.new(build_hash('definitions' => definitions_array))
        endpoint.available_versions.should eq(%w[ 3.2 1.2 ])
      end
    end

    describe "#find_definition!" do
      let(:hash) { build_hash('definitions' => definitions_array) }
      let(:endpoint) { Endpoint.new(hash) }

      it 'finds the definition matching the given version and message_type' do
        definitions = endpoint.find_definition!('1.2', 'response')
        definitions.first.version.should eq('1.2')
        definitions.first.message_type.should eq('response')
      end

      it 'raises an error when given a version that matches no definition' do
        expect {
          endpoint.find_definition!('2.1', 'response')
        }.to raise_error(NoEndpointDefinitionFoundError)
      end
    end

    describe "#find_example_for!" do
      let(:hash) { build_hash('definitions' => definitions_array) }
      let(:endpoint) { Endpoint.new(hash) }

      it 'returns an example for the requested version' do
        endpoint.find_example_for!('1.2', 'response').data.should eq('e1')
      end

      it 'raises an error when given a version it does not have' do
        expect {
          endpoint.find_example_for!('2.1', 'response')
        }.to raise_error(NoEndpointDefinitionFoundError)
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
    let(:endpoint) { fire_double("Interpol::Endpoint").as_null_object }

    it 'initializes the endpoint' do
      endpoint_def = EndpointDefinition.new(endpoint, version, 'response', build_hash)
      endpoint_def.endpoint.should be(endpoint)
    end

    it 'exposes the endpoint name' do
      endpoint.stub(:name => 'e-name')
      endpoint_def = EndpointDefinition.new(endpoint, version, 'response', build_hash)
      endpoint_def.endpoint_name.should eq('e-name')
    end

    it 'initializes the version' do
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'response', build_hash)
      endpoint_def.version.should eq('2.3')
    end

    it 'default initialized the message type' do
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'response', build_hash)
      endpoint_def.message_type.should eq('response')
    end

    it 'initializes the message type' do
      hash = build_hash('message_type' => 'request')
      endpoint_def = EndpointDefinition.new(endpoint, '2.3', 'request', hash)
      endpoint_def.message_type.should eq('request')
    end

    it 'initializes the example data' do
      hash = build_hash('examples' => [{'a' => 5}])
      v = EndpointDefinition.new(endpoint, version, 'response', hash)
      v.examples.map(&:data).should eq([{ 'a' => 5 }])
    end

    it 'initializes the schema' do
      hash = build_hash('schema' => {'the' => 'schema'})
      v = EndpointDefinition.new(endpoint, version, 'response', hash)
      v.schema['the'].should eq('schema')
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
        v.send(attr).should eq(EndpointDefinition::DEFAULT_PARAM_HASH)
      end
    end

    %w[ path_params query_params ].each do |attr|
      it "initializes #{attr} to the provided value" do
        params = {'key' => 'param'}
        hash = build_hash(attr => params)
        v = EndpointDefinition.new(endpoint, version, 'response', hash)
        v.send(attr).should eq(params)
      end
    end

    describe "#request?" do
      it 'returns true if message_type == request' do
        ed = EndpointDefinition.new(endpoint, version, 'request', build_hash)
        ed.should be_request
      end

      it 'returns false if message_type == response' do
        ed = EndpointDefinition.new(endpoint, version, 'response', build_hash)
        ed.should_not be_request
      end

      it 'returns false if message_type == something else' do
        ed = EndpointDefinition.new(endpoint, version, 'something_else', build_hash)
        ed.should_not be_request
      end
    end

    describe "#parse_request_params" do
      let(:parser_class) { fire_replaced_class_double("Interpol::RequestParamsParser") }
      let(:parser)       { fire_double("Interpol::RequestParamsParser") }
      let(:definition)   { EndpointDefinition.new(endpoint, version, 'response', build_hash) }

      it 'parses the given params using a RequestParamsParser' do
        parser_class.should_receive(:new).
                     with(definition).
                     and_return(parser)

        parser.should_receive(:parse).
               with("the" => "params").
               and_return("parsed" => "params")

        parsed = definition.parse_request_params("the" => "params")
        parsed.should eq("parsed" => "params")
      end
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

      it 'raises an error when the schema itself is invalid' do
        schema['properties']['foo']['minItems'] = 'foo'
        expect {
          subject.validate_data!('foo' => 17)
        }.to raise_error(ValidationError)
      end

      it 'rejects unrecognized data types' do
        schema['properties']['foo']['type'] = 'sting'
        expect {
          subject.validate_data!('foo' => 'bar')
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

  describe StatusCodeMatcher do
    describe "#new" do
      it 'initializes the codes for nil' do
        StatusCodeMatcher.new(nil).code_strings.should == ['xxx']
      end

      it 'initializs the codes for a single code' do
        StatusCodeMatcher.new(['200']).code_strings.should == ["200"]
      end

      it 'initializs the codes for a multiple codes' do
        StatusCodeMatcher.new(['200', '4xx', 'x0x']).code_strings.should == ['200', '4xx', 'x0x']
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
        nil_codes_subject.matches?('200').should be_true
      end

      subject { StatusCodeMatcher.new(['200', '4xx', 'x5x']) }
      it 'returns true for an exact match' do
        subject.matches?('200').should be_true
      end

      it 'returns true for a partial matches' do
        subject.matches?('401').should be_true
        subject.matches?('454').should be_true
      end

      it 'returns false for no matches' do
        subject.matches?('202').should be_false
      end
    end

    describe '#example_status_code' do
      it 'returns a valid example status code when a specific status code was given' do
        StatusCodeMatcher.new(['404']).example_status_code.should == '404'
      end

      it 'returns a valid example status code when no status codes were given' do
        StatusCodeMatcher.new(nil).example_status_code.should == '200'
      end

      it 'returns a valid example status code based on the first status code' do
        StatusCodeMatcher.new(['4xx', 'x0x']).example_status_code.should == '400'
      end
    end
  end

  describe EndpointExample do

    let(:definition) { fire_double("Interpol::EndpointDefinition") }
    let(:data)       { { "the" => "data" } }
    let(:example)    { EndpointExample.new(data, definition) }

    describe "#validate!" do
      it 'validates against the schema' do
        definition.should_receive(:validate_data!).with(data)
        example.validate!
      end
    end

    describe '#apply_filters' do
      let(:filter_1) { lambda { |ex, request_env| ex.data["the"] = "data1" } }
      let(:request_env) { { "a" => "hash" } }

      it 'applies a filter and returns modified data' do
        modified_example = example.apply_filters([filter_1], request_env)
        modified_example.data.should eq("the" => "data1")
      end

      it 'chains multiple filters, passing the modified example onto each' do
        filter_2 = lambda do |ex, request_env|
          ex.data.should eq("the" => "data1")
          ex.data["the"].upcase!
        end

        modified_example = example.apply_filters([filter_1, filter_2], request_env)
        modified_example.data.should eq("the" => "DATA1")
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

        modified_example = example.apply_filters([filter], request_env)
        example.data.should eq(data_2)
      end

      it 'does not modify the original example array' do
        data_1 = [1, { "b" => 6 }]
        data_2 = [1, { "b" => 6 }]

        example = EndpointExample.new(data_1, definition)
        filter = lambda do |ex, request_env|
          ex.data.last["c"] = 3
          ex.data << 0
        end

        modified_example = example.apply_filters([filter], request_env)
        example.data.should eq(data_2)
      end

      it 'returns an unmodified example when given no filters' do
        example.apply_filters([], request_env)
        example.data.should eq(data)
      end

      it 'passes the given request_env onto the filters' do
        passed_request_env = nil
        filter = lambda do |_, req_env|
          passed_request_env = req_env
        end

        example.apply_filters([filter], :the_request_env)
        passed_request_env.should be(:the_request_env)
      end
    end
  end
end

