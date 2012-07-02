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
          endpoint.definitions.first.each do |definitions|
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

    describe "#api_version" do
      it 'raises an error when given a static version and a dynamic block' do
        expect {
          config.api_version('1.0') { }
        }.to raise_error(ConfigurationError)
      end

      it 'raises an error when given neither a static version or dynamic block' do
        expect {
          config.api_version
        }.to raise_error(ConfigurationError)
      end
    end

    describe "#api_version_for" do
      context 'when configured with a static version' do
        it 'returns the configured static api version number' do
          config.api_version '1.2'
          config.api_version_for({}, stub.as_null_object).should eq('1.2')
        end

        it 'always returns a string, even when configured as an integer' do
          config.api_version 3
          config.api_version_for({}, stub.as_null_object).should eq('3')
        end
      end

      context 'when configured with a block' do
        it "returns the blocks's return value" do
          config.api_version { |e, _| e[:path][%r|/api/v(\d+)/|, 1] }
          config.api_version_for({ :path => "/api/v2/foo" }, stub.as_null_object).should eq('2')
        end

        it 'always returns a string, even when configured as a string' do
          config.api_version { |_| 3 }
          config.api_version_for({}, stub.as_null_object).should eq('3')
        end
      end

      it 'raises a helpful error when api_version has not been configured' do
        expect {
          config.api_version_for({}, stub.as_null_object)
        }.to raise_error(ConfigurationError)
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
  end
end

