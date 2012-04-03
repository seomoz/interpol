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
  end
end

