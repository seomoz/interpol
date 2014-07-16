require 'interpol/request_params_parser'
require 'support/request_params_parser_definition'

module Interpol
  RSpec.describe RequestParamsParser, :uses_request_params_parser_definition do
    let(:raw_endpoint_definition) { YAML.load endpoint_definition_yml }

    def endpoint_definition
      Endpoint.new(raw_endpoint_definition).definitions.first
    end

    let(:config) { Configuration.new }
    let(:parser) { RequestParamsParser.new(endpoint_definition, config) }

    let(:valid_params) do
      { 'user_id' => '11.22', 'project_language' => 'ruby' }
    end

    context 'when instantiated' do
      it 'validates that all path_params are part of the route' do
        properties = endpoint_definition.path_params.fetch("properties")
        properties['foo'] = { :type => 'string' }
        expect { parser }.to raise_error(/foo/)
      end

      %w[ array object ].each do |type|
        it "raises an error for a #{type} param definition since it does not yet support it" do
          endpoint_definition_yml.gsub!('boolean', type)
          expect { parser }.to raise_error(/no param parser/i)
        end
      end

      %w[ path_params query_params ].each do |param_type|
        it "raises an error if #{param_type} does not have 'type: object'" do
          endpoint_definition.send(param_type)['type'] = 'array'
          expect { parser }.to raise_error { |error|
            expect(error.message).to include(param_type)
            expect(error.message).to include(endpoint_definition.endpoint_name)
            expect(error.message).to include("object")
          }
        end

        it "raises an error if #{param_type} lacks property definitions" do
          endpoint_definition.send(param_type).delete('properties')
          expect { parser }.to raise_error { |error|
            expect(error.message).to include(param_type)
            expect(error.message).to include(endpoint_definition.endpoint_name)
            expect(error.message).to include("properties")
          }
        end
      end
    end

    # Note: these specs were originally written when RequestParamsParser had explicit
    #       logic to handle each type of a parameter. They are pretty exhaustive.
    #       Now that we have the ParamParser abstraction (and corresponding specs),
    #       we could get by with fewer, simpler specs here, but they helped me prevent
    #       regressions when doing my refactoring. I'm leaving them for now, but feel
    #       free to delete some of these and/or simplify in the future.
    describe '#validate!' do
      it 'passes when all params are valid' do
        parser.validate!(valid_params) # should not raise an error
      end

      it 'fails when a param does not match a specified pattern' do
        params = valid_params.merge('user_id' => 'abc')
        expect { parser.validate!(params) }.to raise_error(/user_id/)
      end

      it 'fails when a param does not match a specified integer' do
        params = valid_params.merge('project_language' => 'C++')
        expect { parser.validate!(params) }.to raise_error(/project_language/)
      end

      it 'allows integer params to be passed as a string representation ' +
         'since it came from a request URL' do
        parser.validate!(valid_params.merge 'integer' => 23)
        parser.validate!(valid_params.merge 'integer' => '23')
        parser.validate!(valid_params.merge 'integer' => '-123')

        expect {
          parser.validate!(valid_params.merge 'integer' => 'ab')
        }.to raise_error(/integer/)

        expect {
          parser.validate!(valid_params.merge 'integer' => '0.5')
        }.to raise_error(/integer/)
      end

      it 'allows number params to be passed as a number representation ' +
         'since it came from a request URL' do
        parser.validate!(valid_params.merge 'number' => 3.7)
        parser.validate!(valid_params.merge 'number' => '3.7')
        parser.validate!(valid_params.merge 'number' => '3')
        parser.validate!(valid_params.merge 'number' => '-3.34')

        expect {
          parser.validate!(valid_params.merge 'number' => 'ab')
        }.to raise_error(/number/)
      end

      it 'allows boolean params to be passed as "true" or "false" strings' do
        parser.validate!(valid_params.merge 'boolean' => true)
        parser.validate!(valid_params.merge 'boolean' => false)
        parser.validate!(valid_params.merge 'boolean' => 'true')
        parser.validate!(valid_params.merge 'boolean' => 'false')

        expect {
          parser.validate!(valid_params.merge 'boolean' => 'not-true')
        }.to raise_error(/boolean/)
      end

      it "allows null params to be passed as '' or nil" do
        parser.validate!(valid_params.merge 'null_param' => '')
        parser.validate!(valid_params.merge 'null_param' => nil)

        expect {
          parser.validate!(valid_params.merge 'null_param' => '3')
        }.to raise_error(/null/)
      end

      it 'supports union types' do
        parser.validate!(valid_params.merge 'union' => 'true')
        parser.validate!(valid_params.merge 'union' => false)
        parser.validate!(valid_params.merge 'union' => '3')
        parser.validate!(valid_params.merge 'union' => 3)
        parser.validate!(valid_params.merge 'union' => '2012-08-03')

        expect {
          parser.validate!(valid_params.merge 'union' => [])
        }.to raise_error(/union/)
      end

      def get_entry(entry)
        raw_endpoint_definition.fetch('definitions').first.fetch(entry)
      end

      def dup_of(entry)
        Marshal.load(Marshal.dump(get_entry entry))
      end

      it 'does not modify the original path_params or query_params' do
        query_params = dup_of('query_params')
        path_params = dup_of('path_params')

        parser.validate!(valid_params)

        expect(get_entry('query_params')).to eq(query_params)
        expect(get_entry('path_params')).to eq(path_params)
      end

      it 'requires all params except those with `optional: true`' do
        without_user_id = valid_params.dup.tap { |p| p.delete('user_id') }

        expect {
          parser.validate!(without_user_id)
        }.to raise_error(/user_id/)

        endpoint_definition.path_params.
                            fetch('properties').
                            fetch('user_id')['optional'] = true

        new_parser = RequestParamsParser.new(endpoint_definition, config)
        new_parser.validate!(without_user_id)
      end

      it 'does not allow additional undefined params' do
        expect {
          parser.validate!(valid_params.merge 'something_else' => 'a')
        }.to raise_error(/something_else/)
      end

      it 'allows additional properties if path_params has additionalProperties: true' do
        endpoint_definition.path_params['additionalProperties'] = true
        parser.validate!(valid_params.merge 'something_else' => 'a')
      end

      it 'allows additional properties if query_params has additionalProperties: true' do
        endpoint_definition.query_params['additionalProperties'] = true
        parser.validate!(valid_params.merge 'something_else' => 'a')
      end

      it 'supports top-level schema declarations like patternProperties' do
        endpoint_definition.path_params['patternProperties'] = {
          '\\d+ Feet' => { 'type' => 'integer' }
        }

        parser.validate!(valid_params.merge '23 Feet' => 18)

        expect {
          parser.validate!(valid_params.merge '23 Feet' => 'string')
        }.to raise_error(/23 Feet/)
      end
    end

    describe "#parse" do
      def parse_with(hash_to_merge = {})
        parser.parse(valid_params.merge hash_to_merge)
      end
      alias parse parse_with

      it 'validates the given params' do
        expect {
          parse_with 'user_id' => ''
        }.to raise_error(/user_id/)
      end

      it 'returns a "strongly typed" object that allows dot-syntax to be used' do
        params = parse
        expect(params).to respond_to(:user_id, :project_language)
        expect(params).not_to respond_to(:some_undefined_param)
      end

      it 'converts string integers to fixnums' do
        expect(parse_with('integer' => '3').integer).to eq(3)
        expect(parse_with('integer' => 4).integer).to eq(4)
      end

      it 'converts string numbers to floats' do
        expect(parse_with('number' => '2.3').number).to eq(2.3)
        expect(parse_with('number' => Math::PI).number).to eq(Math::PI)
      end

      it 'converts "true" and "false" strings to their boolean equivalents' do
        expect(parse_with('boolean' => 'true').boolean).to eq(true)
        expect(parse_with('boolean' => true).boolean).to eq(true)
        expect(parse_with('boolean' => 'false').boolean).to eq(false)
        expect(parse_with('boolean' => false).boolean).to eq(false)
      end

      if Date.method_defined?(:iso8601)
        def iso8601(date)
          date.iso8601
        end
      else
        def iso8601(date)
          date.to_s
        end
      end

      let(:date) { Date.new(2012, 8, 3) }

      it 'converts date strings to a date object' do
        expect(parse_with('date' => iso8601(date)).date).to eq(date)
      end

      let(:time) { Time.utc(2012, 8, 3, 5, 23, 15) }

      it 'converts date-time strings to a time object' do
        expect(parse_with('date_time' => time.iso8601).date_time).to eq(time)
      end

      let(:uri) { URI('http://foo.com/bar') }

      it 'converts URI strings to a URI object' do
        expect(parse_with('uri' => uri.to_s).uri).to eq(uri)
      end

      it "converts '' to nil" do
        expect(parse_with('null_param' => '').null_param).to be(nil)
        expect(parse_with('null_param' => nil).null_param).to be(nil)
      end

      it 'preserves raw string params' do
        expect(parse_with('project_language' => 'ruby').project_language).to eq('ruby')
      end

      it 'supports unioned types'  do
        expect(parse_with('union' => '3').union).to eq(3)
        expect(parse_with('union' => '2.3').union).to eq(2.3)
        expect(parse_with('union' => '').union).to eq(nil)
        expect(parse_with('union' => 'false').union).to eq(false)
        expect(parse_with('union' => iso8601(date)).union).to eq(date)
        expect(parse_with('union' => time.iso8601).union).to eq(time)
        expect(parse_with('union' => uri.to_s).union).to eq(uri)
      end

      def ordered_formats_for(name)
        param = endpoint_definition.query_params.fetch('properties').fetch(name)
        param.fetch('type').map { |t| t.fetch('format') }
      end

      it 'does not convert date strings to URIs even when the URI type comes first in a union' do
        # The logic this test exercises is only needed when URI comes before date in the union
        expect(ordered_formats_for('uri_or_date')).to eq(['uri', 'date'])
        expect(parse_with('uri_or_date' => iso8601(date)).uri_or_date).to eq(date)
        expect(parse_with('uri_or_date' => uri.to_s).uri_or_date).to eq(uri)
      end

      def prevent_validation_failure
        # Ensure it gets past the validation so we can get to a case where
        # the parser cannot parse the value.
        allow(parser.instance_variable_get(:@validator)).to receive(:validate!)
      end

      it 'raises an error if none of the unioned types can parse the given value' do
        # Ensure it gets past the validation so we can get to a case where
        # the parser cannot parse the value.
        # Note that it gets pass the validation anyway, but only due to a code
        # in json-schema: it does not validate URI strings.
        allow(parser.instance_variable_get(:@validator)).to receive(:validate!)

        expect {
          parse_with('union' => 'some string')
        }.to raise_error(/cannot be parsed/)
      end

      it 'raises an error when parsing an unrecognized type' do
        endpoint_definition_yml.gsub!('string', 'bling')
        allow_any_instance_of(
          Interpol::RequestParamsParser::ParamValidator
        ).to receive(:build_params_schema)

        allow_any_instance_of(
          Interpol::RequestParamsParser::ParamValidator
        ).to receive(:validate!)

        expect {
          parse
        }.to raise_error(/no param parser/i)
      end

      it 'ensures all defined params are methods on the returned object, ' +
         'even if not present in the params hash' do
        expect(valid_params.keys).not_to include('date', 'date_time')
        parsed = self.parse
        expect(parsed.date).to be_nil
        expect(parsed.date_time).to be_nil
      end
    end
  end
end

