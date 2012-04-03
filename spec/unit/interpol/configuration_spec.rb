require 'fast_spec_helper'
require 'interpol/configuration'

module Interpol
  describe Configuration do
    let(:config) { Configuration.new }

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
          config.api_version_for({}).should eq('1.2')
        end

        it 'always returns a string, even when configured as an integer' do
          config.api_version 3
          config.api_version_for({}).should eq('3')
        end
      end

      context 'when configured with a block' do
        it "returns the blocks's return value" do
          config.api_version { |e| e[:path][%r|/api/v(\d+)/|, 1] }
          config.api_version_for(path: "/api/v2/foo").should eq('2')
        end

        it 'always returns a string, even when configured as a string' do
          config.api_version { |e| 3 }
          config.api_version_for({}).should eq('3')
        end
      end

      it 'raises a helpful error when api_version has not been configured' do
        expect {
          config.api_version_for({})
        }.to raise_error(ConfigurationError)
      end
    end
  end
end

