require 'fast_spec_helper'
require 'interpol/configuration'

module Interpol
  describe DefinitionFinder do
    describe '#find_definition' do
      def endpoint_def(message_type, status_codes, *versions)
        {
          'versions' => versions,
          'message_type' => message_type,
          'status_codes' => status_codes,
          'schema' => {},
          'examples' => {}
        }
      end

      def endpoint(name, method, route, *endpoint_defs)
        Endpoint.new \
          'name' => name,
          'route' => route,
          'method' => method,
          'definitions' => endpoint_defs
      end

      let(:endpoint_def_1a) { endpoint_def('response', ['2xx'], '1.3') }
      let(:endpoint_def_1b) { endpoint_def('response', nil, '1.3') }
      let(:endpoint_def_2a) { endpoint_def('request', nil, '2.3', '2.7') }

      let(:endpoint_1) do
        endpoint 'e1', 'GET', '/users/:user_id/overview', endpoint_def_1a, endpoint_def_1b
      end
      let(:endpoint_2)    { endpoint 'e2', 'POST', '/foo/bar', endpoint_def_2a}
      let(:all_endpoints) { [endpoint_1, endpoint_2].extend(DefinitionFinder) }

      def find(options)
        find_with_status_code(nil, options)
      end

      def find_with_status_code(status_code, options)
        all_endpoints.find_definition(options[:method], options[:path],
          options[:message_type], status_code) { |e| options[:version] }
      end

      it 'finds a matching endpoint definition' do
        found = find(:method => 'POST', :path => '/foo/bar',
          :version => '2.3', :message_type => 'request')
        found.endpoint_name.should eq(endpoint_2.name)
        found.version.should eq('2.3')
      end

      it 'finds the correct versioned definition of the endpoint' do
        found = find(:method => 'POST', :path => '/foo/bar',
          :version => '2.7', :message_type => 'request')
        found.version.should eq('2.7')
      end

      it 'calls the version block with the endpoint' do
        endpoint = nil
        all_endpoints.find_definition('POST', '/foo/bar', 'request') do |e|
          endpoint = e
        end

        endpoint.should be(endpoint_2)
      end

      it 'returns NoDefinitionFound if it cannot find a matching route' do
        result = find(:method => 'POST', :path => '/goo/bar',
          :version => '2.7', :message_type => 'request')
        result.should be(DefinitionFinder::NoDefinitionFound)
      end

      it 'returns nil if the endpoint does not have a matching version' do
        result = find(:method => 'POST', :path => '/foo/bar',
          :version => '13.7', :message_type => 'request')
        result.should be(DefinitionFinder::NoDefinitionFound)
      end

      it 'handles route params properly' do
        found = find_with_status_code('200', :method => 'GET', :path => '/users/17/overview',
          :version => '1.3', :message_type => 'response')
        found.endpoint_name.should be(endpoint_1.name)
        found.status_codes.should eq('2xx')
      end

      it 'handles status code params properly' do
        found = find_with_status_code('403', :method => 'GET', :path => '/users/17/overview',
          :version => '1.3', :message_type => 'response')
        found.endpoint_name.should be(endpoint_1.name)
        found.status_codes.should eq('xxx')
      end
    end
  end

  describe Configuration do
    let(:config) { Configuration.new }

    it 'yields itself on initialization if a block is provided' do
      yielded_object = nil
      config = Configuration.new { |c| yielded_object = c }
      yielded_object.should be(config)
    end

    describe "#endpoint_definition_files" do
      it 'allows files to be set as a glob' do
        config.endpoint_definition_files = Dir["spec/fixtures/dir_with_two_yaml_files/*.yml"]
        files = config.endpoint_definition_files
        files.map { |f| f.split('/').last }.should =~ %w[ one.yml two.yml ]
      end
    end

    describe "#endpoints", :clean_endpoint_dir do
      let_without_indentation(:endpoint_definition_yml) do <<-EOF
        ---
        name: project_list
        route: /users/:user_id/projects
        method: GET
        definitions:
          - versions: ["1.0"]
            schema:
              type: object
              properties:
                name:
                  type: string
            examples:
              - name: "some project"
        EOF
      end

      it 'returns the endpoint definitions from the configured files' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml
        write_file "#{dir}/e2.yml", endpoint_definition_yml.gsub("project", "task")

        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        config.should have(2).endpoints
        config.endpoints.map(&:name).should =~ %w[ project_list task_list ]
      end

      context "when YAML merge keys are used" do
        let_without_indentation(:types) do <<-EOF
          ---
          project_schema: &project_schema
            type: object
            properties:
              name:
                type: string
          EOF
        end

        let_without_indentation(:endpoint_definition_yml_with_merge_keys) do <<-EOF
          ---
          name: project_list
          route: /users/:user_id/projects
          method: GET
          definitions:
            - versions: ["1.0"]
              schema:
                <<: *project_schema
              examples:
                - name: "some project"
          EOF
        end

        before do
          write_file "#{dir}/e1.yml", endpoint_definition_yml_with_merge_keys
          write_file "#{dir}/merge_keys.yml", types
        end

        def assert_expected_endpoint
          config.endpoints.size.should eq(1)
          endpoint = config.endpoints.first
          defs = endpoint.definitions
          defs.should have_at_least(1).entry
          defs.each do |definitions|
            definitions.schema.fetch("properties").should have_key("name")
          end
        end

        it 'supports the merge keys when configured before the endpoint definition files' do
          config.endpoint_definition_merge_key_files = Dir["#{dir}/merge_keys.yml"]
          config.endpoint_definition_files = Dir["#{dir}/e1.yml"]
          assert_expected_endpoint
        end

        it 'works when the merge key YAML file lacks the leading `---`' do
          write_file "#{dir}/merge_keys.yml", types.gsub(/\A---\n/, '')
          config.endpoint_definition_merge_key_files = Dir["#{dir}/merge_keys.yml"]
          config.endpoint_definition_files = Dir["#{dir}/e1.yml"]
          assert_expected_endpoint
        end

        it 'raises a helpful error when endpoint_definition_files is configured first' do
          expect {
            config.endpoint_definition_files = Dir["#{dir}/e1.yml"]
          }.to raise_error(/endpoint_definition_merge_key_files/)
        end
      end

      it 'is memoized' do
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        config.endpoints.should equal(config.endpoints)
      end

      it 'is cleared when endpoint_definition_files is set' do
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        endpoints1 = config.endpoints
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        endpoints1.should_not equal(config.endpoints)
      end

      it 'returns a blank array if no definition files have been set' do
        config.endpoints.should eq([])
      end

      it 'provides a method to easily find an endpoint definition' do
        config.endpoints.should respond_to(:find_definition)
      end

      it 'can be assigned directly' do
        endpoints_array = [stub.as_null_object]
        config.endpoints = endpoints_array
        config.endpoints.should respond_to(:find_definition)
      end
    end

    [:request, :response].each do |version_type|
      set_method = "#{version_type}_version"

      describe "##{set_method}" do
        it 'raises an error when given a static version and a dynamic block' do
          expect {
            config.send(set_method, '1.0') { }
          }.to raise_error(ConfigurationError)
        end

        it 'raises an error when given neither a static version or dynamic block' do
          expect {
            config.send(set_method)
          }.to raise_error(ConfigurationError)
        end
      end

      get_method = "#{version_type}_version_for"

      describe "##{get_method}" do
        context 'when configured with a static version' do
          it 'returns the configured static api version number' do
            config.send(set_method, '1.2')
            config.send(get_method, {}, stub.as_null_object).should eq('1.2')
          end

          it 'always returns a string, even when configured as an integer' do
            config.send(set_method, 3)
            config.send(get_method, {}, stub.as_null_object).should eq('3')
          end
        end

        context 'when configured with a block' do
          it "returns the blocks's return value" do
            config.send(set_method) { |e, _| e[:path][%r|/api/v(\d+)/|, 1] }
            config.send(get_method, { :path => "/api/v2/foo" }, stub.as_null_object).should eq('2')
          end

          it 'always returns a string, even when configured as an integer' do
            config.send(set_method) { |*a| 3 }
            config.send(get_method, {}, stub.as_null_object).should eq('3')
          end
        end

        it "raises a helpful error when ##{set_method} has not been configured" do
          expect {
            config.send(get_method, {}, stub.as_null_object)
          }.to raise_error(ConfigurationError)
        end
      end
    end

    describe "#api_version" do
      before { config.stub(:warn) }

      it 'configures both request_version and response_version' do
        config.api_version '23.14'
        config.request_version_for({}, stub.as_null_object).should eq('23.14')
        config.response_version_for({}, stub.as_null_object).should eq('23.14')
      end

      it 'prints a warning' do
        config.should_receive(:warn).with(/api_version.*request_version.*response_version/)
        config.api_version '1.0'
      end
    end

    describe "#validate_if" do
      before { config.stub(:warn) }

      it 'configures validate_response_if' do
        config.validate_if { |a| a }
        config.validate_response?(true).should be_true
        config.validate_response?(false).should be_false
      end

      it 'prints a warning' do
        config.should_receive(:warn).with(/validate_if.*validate_response_if/)
        config.validate_if { true }
      end
    end

    describe "#filter_example_data" do
      it 'adds the block to the #filter_example_data_blocks list' do
        block_1 = lambda { }
        block_2 = lambda { }

        config.filter_example_data(&block_1)
        config.filter_example_data(&block_2)

        config.filter_example_data_blocks.should eq([block_1, block_2])
      end
    end

    describe "#customized_duplicate" do
      it 'yields a configuration instance' do
        cd = nil
        config.customized_duplicate { |c| cd = c }
        cd.should be_a(Configuration)
      end

      it 'uses a duplicate so as not to affect the original instance' do
        config.validation_mode = :warn
        cd = nil
        config.customized_duplicate do |c|
          c.validation_mode = :error
          cd = c
        end

        config.validation_mode.should be(:warn)
        cd.validation_mode.should be(:error)
      end
    end

    describe "#param_parser_for" do
      let!(:simple1) { config.define_request_param_parser('simple1') { } }
      let!(:simple2) { config.define_request_param_parser('simple2') { } }

      let!(:complex1_2) { config.define_request_param_parser('complex1', 'foo' => 2) { } }
      let!(:complex1_3) { config.define_request_param_parser('complex1', 'foo' => 3) { } }
      let!(:complex1_nil) { config.define_request_param_parser('complex1', 'foo' => nil) { } }

      let!(:complex2_4) { config.define_request_param_parser('complex2', 'foo' => 4) { } }
      let!(:complex2_5) { config.define_request_param_parser('complex2', 'foo' => 5,
                                                             'bar' => 'a') { } }

      it 'raises an error if no matching definition can be found' do
        expect {
          config.param_parser_for('blah', {})
        }.to raise_error(UnsupportedTypeError)
      end

      it 'returns the last matching definition (to allow user overrides)' do
        new_def = config.define_request_param_parser('simple1') { }
        config.param_parser_for('simple1', {}).should be(new_def)
      end

      context 'when only a type is given' do
        it 'returns the matching definition' do
          config.param_parser_for('simple1', {}).should be(simple1)
          config.param_parser_for('simple2', {}).should be(simple2)
        end
      end

      context 'when options are given' do
        it 'returns the matching definition' do
          config.param_parser_for('complex1', 'foo' => 2).should eq(complex1_2)
          config.param_parser_for('complex1', 'foo' => 3).should eq(complex1_3)
        end

        it 'ignores extra options that do not apply' do
          config.param_parser_for('complex1', 'foo' => 2, 'a' => 1).should eq(complex1_2)
          config.param_parser_for('complex1', 'foo' => 3, 'b' => 2).should eq(complex1_3)
          config.param_parser_for('simple1', 'a' => 2).should be(simple1)
        end

        it 'only matches nil values if the matching key is included in the provided hash' do
          config.param_parser_for('complex1', 'foo' => nil).should eq(complex1_nil)
          expect {
            config.param_parser_for('complex1', 'bar' => 4)
          }.to raise_error(UnsupportedTypeError)
        end
      end
    end
  end

  describe ParamParser do
    let(:config) { Configuration.new }

    describe "#parse_value" do
      it 'raises a useful error if no parse callback has been set' do
        definition = ParamParser.new("foo", "bar" => 3) { }
        expect {
          definition.parse_value("blah")
        }.to raise_error(/parse/)
      end
    end

    it 'allows a block to be passed for string_validation_options' do
      parser = ParamParser.new("foo", "bar" => 3) do |p|
        p.string_validation_options do |opts|
          opts.merge("a" => 2)
        end
      end

      options = parser.type_validation_options_for('foo', 'b' => 3)
      options.last.should eq("type" => "string", "b" => 3, "a" => 2)
    end

    RSpec::Matchers.define :have_errors_for do |value|
      match do |schema|
        validate(schema)
      end

      failure_message_for_should_not do |schema|
        ValidationError.new(@errors, params).message
      end

      def validate(schema)
        @errors = ::JSON::Validator.fully_validate(schema, params)
        @errors.any?
      end

      define_method :params do
        { 'some_param' => value }
      end
    end

    RSpec::Matchers.define :convert do |old_value|
      chain :to do |new_value|
        @new_value = new_value
      end

      match_for_should do |converter|
        raise "Must specify the expected value with .to" unless defined?(@new_value)
        @converter = converter
        @old_value = old_value
        converted_value == @new_value
      end

      match_for_should_not do |converter|
        @converter = converter
        @old_value = old_value
        raised_argument_error = false

        begin
          converted_value
        rescue ArgumentError
          raised_argument_error = true
        end

        raised_argument_error
      end

      failure_message_for_should do |converter|
        "expected #{old_value.inspect} to convert to #{@new_value.inspect}, " +
        "but converted to #{converted_value.inspect}"
      end

      failure_message_for_should_not do |converter|
        "expected #{old_value.inspect} to trigger an ArgumentError when " +
        "conversion was attempted, but did not"
      end

      def converted_value
        @converted_value ||= @converter.call(@old_value)
      end
    end

    def self.for_type(type, options = {}, &block)
      description = type.inspect
      description << " (with options: #{options.inspect})" if options.any?

      context "for type: #{description}" do
        let(:parser) { config.param_parser_for(type, options) }
        let(:type) { type }

        let(:schema) do {
          'type'       => 'object',
          'properties' => {
            'some_param' => options.merge(
              'type' => parser.type_validation_options_for(type, options)
            )
          }
        } end

        let(:converter) { parser.method(:parse_value) }

        module_exec(type, &block)
      end
    end

    for_type 'integer' do
      it 'allows a string integer to pass validation' do
        schema.should_not have_errors_for("23")
        schema.should_not have_errors_for("-2")
      end

      it 'allows an integer to pass validation' do
        schema.should_not have_errors_for(-12)
      end

      it 'fails a string that is not formatted like an integer' do
        schema.should have_errors_for("not an int")
      end

      it 'fails a string that is formatted like a float' do
        schema.should have_errors_for("0.5")
        schema.should have_errors_for(0.5)
      end

      it 'converts string ints to fixnums' do
        converter.should convert("23").to(23)
        converter.should convert(17).to(17)
      end

      it 'does not convert invalid values' do
        converter.should_not convert("0.5")
        converter.should_not convert("not a fixnum")
        converter.should_not convert(nil)
      end
    end

    for_type 'number' do
      it 'allows a string int or float to pass validation' do
        schema.should_not have_errors_for("23")
        schema.should_not have_errors_for("-2.5")
      end

      it 'allows an integer or float to pass validation' do
        schema.should_not have_errors_for(-12)
        schema.should_not have_errors_for(2.17)
      end

      it 'fails a string that is not formatted like an integer or float' do
        schema.should have_errors_for("not a num")
      end

      it 'converts string numbers to floats' do
        converter.should convert("23.3").to(23.3)
        converter.should convert(-5).to(-5.0)
      end

      it 'does not convert invalid values' do
        converter.should_not convert("not a num")
        converter.should_not convert(nil)
      end
    end

    for_type "boolean" do
      it 'allows "true" or "false" to pass validation' do
        schema.should_not have_errors_for("true")
        schema.should_not have_errors_for("false")
      end

      it 'allows actual boolean values to pass validation' do
        schema.should_not have_errors_for(true)
        schema.should_not have_errors_for(false)
      end

      it 'fails other values' do
        schema.should have_errors_for("tru")
        schema.should have_errors_for("flse")
        schema.should have_errors_for("23")
      end

      it 'converts boolean strings to boolean values' do
        converter.should convert("false").to(false)
        converter.should convert(false).to(false)
        converter.should convert("true").to(true)
        converter.should convert(true).to(true)
      end

      it 'does not convert invalid values' do
        converter.should_not convert("tru")
        converter.should_not convert(nil)
      end
    end

    for_type "null" do
      it 'allows nil or "" to pass validation' do
        schema.should_not have_errors_for(nil)
        schema.should_not have_errors_for("")
      end

      it 'fails other values' do
        schema.should have_errors_for(" ")
        schema.should have_errors_for(3)
      end

      it 'converts "" to nil' do
        converter.should convert("").to(nil)
        converter.should convert(nil).to(nil)
      end

      it 'does not convert invalid values' do
        converter.should_not convert(" ")
        converter.should_not convert(3)
      end
    end

    for_type "string" do
      it 'allows strings to pass validation' do
        schema.should_not have_errors_for("a string")
        schema.should_not have_errors_for("")
      end

      it 'fails non-string values' do
        schema.should have_errors_for(nil)
        schema.should have_errors_for(3)
      end

      it 'does not change a given string during conversion' do
        converter.should convert("a").to("a")
      end

      it "does not convert invalid values" do
        converter.should_not convert(nil)
        converter.should_not convert(3)
      end
    end

    for_type "string", 'format' => "date" do
      it 'allows date formatted strings' do
        schema.should_not have_errors_for("2012-04-28")
      end

      it 'fails mis-formatted dates' do
        schema.should have_errors_for("04-28-2012")
      end

      it 'fails other strings' do
        schema.should have_errors_for("not a date")
      end

      it 'converts date strings to date values' do
        converter.should convert("2012-08-12").to(Date.new(2012, 8, 12))
      end

      it 'does not convert invalid values' do
        converter.should_not convert("04-28-2012")
        converter.should_not convert("not a date")
        converter.should_not convert(nil)
      end
    end

    for_type 'string', 'format' => 'date-time' do
      let(:time) { Time.utc(2012, 8, 15, 12, 30) }

      it 'allows date-time formatted strings' do
        schema.should_not have_errors_for(time.iso8601)
      end

      it 'fails mis-formatted date-times' do
        schema.should have_errors_for(time.iso8601.gsub('-', '~'))
      end

      it 'fails other strings' do
        schema.should have_errors_for("foo")
      end

      it 'converts date-time strings to time values' do
        converter.should convert(time.iso8601).to(time)
      end

      it 'does not convert invalid values' do
        converter.should_not convert(time.iso8601.gsub('-', '~'))
        converter.should_not convert(nil)
      end
    end

    for_type 'string', 'format' => 'uri' do
      let(:uri) { URI('http://foo.com/bar') }

      it 'allows URI strings' do
        schema.should_not have_errors_for(uri.to_s)
      end

      it 'fails invalid URI strings' do
        pending "json-schema doesn't validate URIs yet, unfortunately" do
          schema.should have_errors_for('not a URI')
        end
      end

      it 'converts URI strings to a URI object' do
        converter.should convert(uri.to_s).to (uri)
      end

      it 'does not convert invalid URIs' do
        converter.should_not convert('2012-08-12')
        converter.should_not convert(' ')
        converter.should_not convert(nil)
        converter.should_not convert("@*&^^^@")
      end
    end
  end
end

