require 'interpol/configuration'
require 'yaml'

module Interpol
  RSpec.describe DefinitionFinder do
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
        expect(found.endpoint_name).to eq(endpoint_2.name)
        expect(found.version).to eq('2.3')
      end

      it 'finds the correct versioned definition of the endpoint' do
        found = find(:method => 'POST', :path => '/foo/bar',
          :version => '2.7', :message_type => 'request')
        expect(found.version).to eq('2.7')
      end

      it 'calls the version block with the endpoint' do
        endpoint = nil
        all_endpoints.find_definition('POST', '/foo/bar', 'request') do |e|
          endpoint = e
        end

        expect(endpoint).to be(endpoint_2)
      end

      it 'returns NoDefinitionFound if it cannot find a matching route' do
        result = find(:method => 'POST', :path => '/goo/bar',
          :version => '2.7', :message_type => 'request')
        expect(result).to be(DefinitionFinder::NoDefinitionFound)
      end

      it 'returns nil if the endpoint does not have a matching version' do
        result = find(:method => 'POST', :path => '/foo/bar',
          :version => '13.7', :message_type => 'request')
        expect(result).to be(DefinitionFinder::NoDefinitionFound)
      end

      it 'handles route params properly' do
        found = find_with_status_code('200', :method => 'GET', :path => '/users/17/overview',
          :version => '1.3', :message_type => 'response')
        expect(found.endpoint_name).to be(endpoint_1.name)
        expect(found.status_codes).to eq('2xx')
      end

      it 'handles status code params properly' do
        found = find_with_status_code('403', :method => 'GET', :path => '/users/17/overview',
          :version => '1.3', :message_type => 'response')
        expect(found.endpoint_name).to be(endpoint_1.name)
        expect(found.status_codes).to eq('xxx')
      end
    end
  end

  RSpec.describe Configuration do
    let(:config) { Configuration.new }

    if defined?(::YAML::ENGINE.yamler)
      require 'psych'
      old_yamler = nil

      before(:context) do
        old_yamler = ::YAML::ENGINE.yamler
        ::YAML::ENGINE.yamler = 'psych'
      end

      after(:context) do
        ::YAML::ENGINE.yamler = old_yamler
      end
    end

    it 'yields itself on initialization if a block is provided' do
      yielded_object = nil
      config = Configuration.new { |c| yielded_object = c }
      expect(yielded_object).to be(config)
    end

    describe "#endpoint_definition_files" do
      it 'allows files to be set as a glob' do
        config.endpoint_definition_files = Dir["spec/fixtures/dir_with_two_yaml_files/*.yml"]
        files = config.endpoint_definition_files
        expect(files.map { |f| f.split('/').last }).to match_array %w[ one.yml two.yml ]
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
        expect(config.endpoints.size).to eq(2)
        expect(config.endpoints.map(&:name)).to match_array %w[ project_list task_list ]
      end

      it 'passes itself to the endpoints as the configuration' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        endpoint_config = config.endpoints.first.configuration
        expect(endpoint_config).to be(config)
      end

      it 'allows `scalars_nullable_by_default` to be configured after ' +
         '`endpoint_definition_files`' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml

        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        config.endpoints # to force it to load
        config.scalars_nullable_by_default = true

        endpoint_def = config.endpoints.first.definitions.first

        expect {
          endpoint_def.validate_data!('name' => nil)
        }.not_to raise_error
      end

      it 'is not prone to being reloaded when the configuration is customized' do
        expect(Endpoint).to receive(:new).once.and_call_original

        write_file "#{dir}/e1.yml", endpoint_definition_yml
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]

        config.customized_duplicate { |c| c.endpoints }
        config.customized_duplicate { |c| c.endpoints }
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
          expect(config.endpoints.size).to eq(1)
          endpoint = config.endpoints.first
          defs = endpoint.definitions
          expect(defs.size).to be >= 1
          defs.each do |definitions|
            expect(definitions.schema.fetch("properties")).to have_key("name")
          end
        end

        it 'supports the merge keys when configured before the endpoint definition files' do
          config.endpoint_definition_merge_key_files = Dir["#{dir}/merge_keys.yml"]
          config.endpoint_definition_files = Dir["#{dir}/e1.yml"]
          assert_expected_endpoint
        end

        it 'supports the merge keys when configured after the endpoint definition files' do
          config.endpoint_definition_files = Dir["#{dir}/e1.yml"]
          config.endpoint_definition_merge_key_files = Dir["#{dir}/merge_keys.yml"]
          assert_expected_endpoint
        end

        it 'works when the merge key YAML file lacks the leading `---`' do
          write_file "#{dir}/merge_keys.yml", types.gsub(/\A---\n/, '')
          config.endpoint_definition_merge_key_files = Dir["#{dir}/merge_keys.yml"]
          config.endpoint_definition_files = Dir["#{dir}/e1.yml"]
          assert_expected_endpoint
        end
      end

      it 'is memoized' do
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        expect(config.endpoints).to equal(config.endpoints)
      end

      it 'is cleared when endpoint_definition_files is set' do
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        endpoints1 = config.endpoints
        config.endpoint_definition_files = Dir["#{dir}/*.yml"]
        expect(endpoints1).not_to equal(config.endpoints)
      end

      it 'returns a blank array if no definition files have been set' do
        expect(config.endpoints).to eq([])
      end

      it 'provides a method to easily find an endpoint definition' do
        expect(config.endpoints).to respond_to(:find_definition)
      end

      it 'can be assigned directly' do
        endpoints_array = [double.as_null_object]
        config.endpoints = endpoints_array
        expect(config.endpoints).to respond_to(:find_definition)
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
            expect(config.send(get_method, {}, double.as_null_object)).to eq('1.2')
          end

          it 'always returns a string, even when configured as an integer' do
            config.send(set_method, 3)
            expect(config.send(get_method, {}, double.as_null_object)).to eq('3')
          end
        end

        context 'when configured with a block' do
          it "returns the blocks's return value" do
            config.send(set_method) { |e, _| e[:path][%r|/api/v(\d+)/|, 1] }
            expect(
              config.send(get_method, { :path => "/api/v2/foo" }, double.as_null_object)
            ).to eq('2')
          end

          it 'always returns a string, even when configured as an integer' do
            config.send(set_method) { |*a| 3 }
            expect(config.send(get_method, {}, double.as_null_object)).to eq('3')
          end
        end

        it "raises a helpful error when ##{set_method} has not been configured" do
          expect {
            config.send(get_method, {}, double.as_null_object)
          }.to raise_error(ConfigurationError)
        end
      end
    end

    describe "#scalars_nullable_by_default?" do
      it 'defaults to false' do
        expect(config.scalars_nullable_by_default?).to be false
      end

      it 'can be set to true' do
        config.scalars_nullable_by_default = true
        expect(config.scalars_nullable_by_default?).to be true
      end
    end

    describe "#api_version" do
      before { allow(config).to receive(:warn) }

      it 'configures both request_version and response_version' do
        config.api_version '23.14'
        expect(config.request_version_for({}, double.as_null_object)).to eq('23.14')
        expect(config.response_version_for({}, double.as_null_object)).to eq('23.14')
      end

      it 'prints a warning' do
        expect(config).to receive(:warn).with(/api_version.*request_version.*response_version/)
        config.api_version '1.0'
      end
    end

    describe "#validate_if" do
      before { allow(config).to receive(:warn) }

      it 'configures validate_response_if' do
        config.validate_if { |a| a }
        expect(config.validate_response?(true)).to be true
        expect(config.validate_response?(false)).to be false
      end

      it 'prints a warning' do
        expect(config).to receive(:warn).with(/validate_if.*validate_response_if/)
        config.validate_if { true }
      end
    end

    describe "#filter_example_data" do
      it 'adds the block to the #filter_example_data_blocks list' do
        block_1 = lambda { }
        block_2 = lambda { }

        config.filter_example_data(&block_1)
        config.filter_example_data(&block_2)

        expect(config.filter_example_data_blocks).to eq([block_1, block_2])
      end
    end

    describe "#customized_duplicate" do
      it 'yields a configuration instance' do
        cd = nil
        config.customized_duplicate { |c| cd = c }
        expect(cd).to be_a(Configuration)
      end

      it 'uses a duplicate so as not to affect the original instance' do
        config.validation_mode = :warn
        cd = nil
        config.customized_duplicate do |c|
          c.validation_mode = :error
          cd = c
        end

        expect(config.validation_mode).to be(:warn)
        expect(cd.validation_mode).to be(:error)
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
        expect(config.param_parser_for('simple1', {})).to be(new_def)
      end

      context 'when only a type is given' do
        it 'returns the matching definition' do
          expect(config.param_parser_for('simple1', {})).to be(simple1)
          expect(config.param_parser_for('simple2', {})).to be(simple2)
        end
      end

      context 'when options are given' do
        it 'returns the matching definition' do
          expect(config.param_parser_for('complex1', 'foo' => 2)).to eq(complex1_2)
          expect(config.param_parser_for('complex1', 'foo' => 3)).to eq(complex1_3)
        end

        it 'ignores extra options that do not apply' do
          expect(config.param_parser_for('complex1', 'foo' => 2, 'a' => 1)).to eq(complex1_2)
          expect(config.param_parser_for('complex1', 'foo' => 3, 'b' => 2)).to eq(complex1_3)
          expect(config.param_parser_for('simple1', 'a' => 2)).to be(simple1)
        end

        it 'only matches nil values if the matching key is included in the provided hash' do
          expect(config.param_parser_for('complex1', 'foo' => nil)).to eq(complex1_nil)
          expect {
            config.param_parser_for('complex1', 'bar' => 4)
          }.to raise_error(UnsupportedTypeError)
        end
      end
    end
  end

  RSpec.describe ParamParser do
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
      expect(options.last).to eq("type" => "string", "b" => 3, "a" => 2)
    end

    RSpec::Matchers.define :have_errors_for do |value|
      match do |schema|
        validate(schema)
      end

      failure_message_when_negated do |schema|
        ValidationError.new(@errors, params).message
      end

      def validate(schema)
        @errors = ::JSON::Validator.fully_validate(schema, params, :version => :draft3)
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

      match do |converter|
        raise "Must specify the expected value with .to" unless defined?(@new_value)
        @converter = converter
        @old_value = old_value
        converted_value == @new_value
      end

      match_when_negated do |converter|
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

      failure_message do |converter|
        "expected #{old_value.inspect} to convert to #{@new_value.inspect}, " +
        "but converted to #{converted_value.inspect}"
      end

      failure_message_when_negated do |converter|
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
        expect(schema).not_to have_errors_for("23")
        expect(schema).not_to have_errors_for("-2")
      end

      it 'allows an integer to pass validation' do
        expect(schema).not_to have_errors_for(-12)
      end

      it 'fails a string that is not formatted like an integer' do
        expect(schema).to have_errors_for("not an int")
      end

      it 'fails a string that is formatted like a float' do
        expect(schema).to have_errors_for("0.5")
        expect(schema).to have_errors_for(0.5)
      end

      it 'converts string ints to fixnums' do
        expect(converter).to convert("23").to(23)
        expect(converter).to convert(17).to(17)
      end

      it 'does not convert invalid values' do
        expect(converter).not_to convert("0.5")
        expect(converter).not_to convert("not a fixnum")
        expect(converter).not_to convert(nil)
      end
    end

    for_type 'number' do
      it 'allows a string int or float to pass validation' do
        expect(schema).not_to have_errors_for("23")
        expect(schema).not_to have_errors_for("-2.5")
      end

      it 'allows an integer or float to pass validation' do
        expect(schema).not_to have_errors_for(-12)
        expect(schema).not_to have_errors_for(2.17)
      end

      it 'fails a string that is not formatted like an integer or float' do
        expect(schema).to have_errors_for("not a num")
      end

      it 'converts string numbers to floats' do
        expect(converter).to convert("23.3").to(23.3)
        expect(converter).to convert(-5).to(-5.0)
      end

      it 'does not convert invalid values' do
        expect(converter).not_to convert("not a num")
        expect(converter).not_to convert(nil)
      end
    end

    for_type "boolean" do
      it 'allows "true" or "false" to pass validation' do
        expect(schema).not_to have_errors_for("true")
        expect(schema).not_to have_errors_for("false")
      end

      it 'allows actual boolean values to pass validation' do
        expect(schema).not_to have_errors_for(true)
        expect(schema).not_to have_errors_for(false)
      end

      it 'fails other values' do
        expect(schema).to have_errors_for("tru")
        expect(schema).to have_errors_for("flse")
        expect(schema).to have_errors_for("23")
      end

      it 'converts boolean strings to boolean values' do
        expect(converter).to convert("false").to(false)
        expect(converter).to convert(false).to(false)
        expect(converter).to convert("true").to(true)
        expect(converter).to convert(true).to(true)
      end

      it 'does not convert invalid values' do
        expect(converter).not_to convert("tru")
        expect(converter).not_to convert(nil)
      end
    end

    for_type "null" do
      it 'allows nil or "" to pass validation' do
        expect(schema).not_to have_errors_for(nil)
        expect(schema).not_to have_errors_for("")
      end

      it 'fails other values' do
        expect(schema).to have_errors_for(" ")
        expect(schema).to have_errors_for(3)
      end

      it 'converts "" to nil' do
        expect(converter).to convert("").to(nil)
        expect(converter).to convert(nil).to(nil)
      end

      it 'does not convert invalid values' do
        expect(converter).not_to convert(" ")
        expect(converter).not_to convert(3)
      end
    end

    for_type "string" do
      it 'allows strings to pass validation' do
        expect(schema).not_to have_errors_for("a string")
        expect(schema).not_to have_errors_for("")
      end

      it 'fails non-string values' do
        expect(schema).to have_errors_for(nil)
        expect(schema).to have_errors_for(3)
      end

      it 'does not change a given string during conversion' do
        expect(converter).to convert("a").to("a")
      end

      it "does not convert invalid values" do
        expect(converter).not_to convert(nil)
        expect(converter).not_to convert(3)
      end
    end

    for_type "string", 'format' => "date" do
      it 'allows date formatted strings' do
        expect(schema).not_to have_errors_for("2012-04-28")
      end

      it 'fails mis-formatted dates' do
        expect(schema).to have_errors_for("04-28-2012")
      end

      it 'fails other strings' do
        expect(schema).to have_errors_for("not a date")
      end

      it 'converts date strings to date values' do
        expect(converter).to convert("2012-08-12").to(Date.new(2012, 8, 12))
      end

      it 'does not convert invalid values' do
        expect(converter).not_to convert("04-28-2012")
        expect(converter).not_to convert("not a date")
        expect(converter).not_to convert(nil)
      end
    end

    for_type 'string', 'format' => 'date-time' do
      let(:time) { Time.utc(2012, 8, 15, 12, 30) }

      it 'allows date-time formatted strings' do
        expect(schema).not_to have_errors_for(time.iso8601)
      end

      it 'fails mis-formatted date-times' do
        expect(schema).to have_errors_for(time.iso8601.gsub('-', '~'))
      end

      it 'fails other strings' do
        expect(schema).to have_errors_for("foo")
      end

      it 'converts date-time strings to time values' do
        expect(converter).to convert(time.iso8601).to(time)
      end

      it 'does not convert invalid values' do
        expect(converter).not_to convert(time.iso8601.gsub('-', '~'))
        expect(converter).not_to convert(nil)
      end
    end

    for_type 'string', 'format' => 'uri' do
      let(:uri) { URI('http://foo.com/bar') }

      it 'allows URI strings' do
        expect(schema).not_to have_errors_for(uri.to_s)
      end

      it 'fails invalid URI strings' do
        pending "json-schema doesn't validate URIs yet, unfortunately"
        expect(schema).to have_errors_for('not a URI')
      end

      it 'converts URI strings to a URI object' do
        expect(converter).to convert(uri.to_s).to (uri)
      end

      it 'does not convert invalid URIs' do
        expect(converter).not_to convert('2012-08-12')
        expect(converter).not_to convert(' ')
        expect(converter).not_to convert(nil)
        expect(converter).not_to convert("@*&^^^@")
      end
    end
  end
end

