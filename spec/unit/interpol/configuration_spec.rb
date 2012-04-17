require 'fast_spec_helper'
require 'interpol/configuration'

module Interpol
  describe DefinitionFinder do
    describe '#find_definition' do
      def endpoint(method, route, *versions)
        Endpoint.new \
          'name' => 'endpoint_name',
          'route' => route,
          'method' => method,
          'definitions' => [{
            'versions' => versions,
            'schema' => {},
            'examples' => {}
          }]
      end

      let(:endpoint_1)    { endpoint 'GET', '/users/:user_id/overview', '1.3' }
      let(:endpoint_2)    { endpoint 'POST', '/foo/bar', '2.3', '2.7' }
      let(:all_endpoints) { [endpoint_1, endpoint_2].extend(DefinitionFinder) }

      def find(options)
        all_endpoints.find_definition(options[:method], options[:path]) { |e| options[:version] }
      end

      it 'finds a matching endpoint definition'  do
        found = find(method: 'POST', path: '/foo/bar', version: '2.3')
        found.endpoint.should be(endpoint_2)
        found.version.should eq('2.3')
      end

      it 'finds the correct versioned definition of the endpoint' do
        found = find(method: 'POST', path: '/foo/bar', version: '2.7')
        found.version.should eq('2.7')
      end

      it 'calls the version block with the endpoint' do
        endpoint = nil
        all_endpoints.find_definition('POST', '/foo/bar') do |e|
          endpoint = e
        end

        endpoint.should be(endpoint_2)
      end

      it 'returns NoDefinitionFound if it cannot find a matching route' do
        result = find(method: 'POST', path: '/goo/bar', version: '2.7')
        result.should be(DefinitionFinder::NoDefinitionFound)
      end

      it 'returns nil if the endpoint does not have a matching version' do
        result = find(method: 'POST', path: '/foo/bar', version: '13.7')
        result.should be(DefinitionFinder::NoDefinitionFound)
      end

      it 'handles route params properly' do
        found = find(method: 'GET', path: '/users/17/overview', version: '1.3')
        found.endpoint.should be(endpoint_1)
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
          endpoint.definitions.first.schema.fetch("properties").should have_key("name")
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
          config.api_version { |e| e[:path][%r|/api/v(\d+)/|, 1] }
          config.api_version_for({ path: "/api/v2/foo" }, stub.as_null_object).should eq('2')
        end

        it 'always returns a string, even when configured as a string' do
          config.api_version { |e| 3 }
          config.api_version_for({}, stub.as_null_object).should eq('3')
        end
      end

      it 'raises a helpful error when api_version has not been configured' do
        expect {
          config.api_version_for({}, stub.as_null_object)
        }.to raise_error(ConfigurationError)
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

