require 'fast_spec_helper'
require 'interpol/test_helper'
require 'rack/request'

module Interpol
  RSpec.describe TestHelper, :clean_endpoint_dir do
    shared_examples_for "interpol example test definer" do
      let_without_indentation(:endpoint_definition_yml) do <<-EOF
        ---
        name: project_list
        route: /users/:user_id/projects
        method: GET
        definitions:
          - versions: ["1.0"]
            message_type: response
            schema:
              type: object
              properties:
                name:
                  type: string
            examples:
              - name: "some project"
              - name: 17
              - name: false
        EOF
      end

      let(:test_group) do
        file_glob = Dir["#{dir}/*.yml"]

        within_group do
          define_interpol_example_tests do |ipol|
            ipol.endpoint_definition_files = file_glob
          end
        end
      end

      it 'generates a test per data example per definition per endpoint + a test per definition' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml.gsub('["1.0"]', '["1.0", "2.0"]')
        write_file "#{dir}/e2.yml", endpoint_definition_yml.gsub("project_list", "project_list_2")
        expect(num_tests_from(test_group)).to eq(9)
      end

      it 'generates tests that fail if their example data is invalid' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml
        run(test_group)
        expect(results_from(test_group)).to match_array [:passed, :failed, :failed]
      end

      it 'falls back to default config settings' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml
        Interpol.default_configuration { |c| c.endpoint_definition_files = Dir["#{dir}/*.yml"] }
        group = within_group { define_interpol_example_tests }
        expect(num_tests_from(group)).to eq(3)
      end

      it 'applies any filter_ex_data blocks before validating the examples' do
        Interpol.default_configuration do |c|
          c.filter_example_data do |example, request_env|
            request = Rack::Request.new(request_env)
            example.data["name"] = request.url
          end
        end

        write_file "#{dir}/e1.yml", endpoint_definition_yml
        run(test_group)
        expect(results_from(test_group)).to match_array [:passed, :passed, :passed]
      end

      context 'request path schema validation' do
        let_without_indentation(:endpoint_definition_yml) do <<-EOF
          ---
          name: project_list
          route: /users/:user_id/projects
          method: GET
          definitions:
            - versions: ["1.0"]
              message_type: request
              path_params:
                type: object
                properties:
                  user_id: { type: string }
              schema: {}
              examples: {}
          EOF
        end

        it 'generates a test per endpoint definition' do
          write_file "#{dir}/e1.yml", endpoint_definition_yml.gsub('["1.0"]', '["1.0", "2.0"]')
          write_file "#{dir}/e2.yml", endpoint_definition_yml.gsub("project_list", "project_list_2")
          expect(num_tests_from(test_group)).to eq(3)
        end

        it 'generates tests that pass if the params are declared correctly' do
          write_file "#{dir}/e1.yml", endpoint_definition_yml
          run(test_group)
          expect(results_from(test_group)).to eq [:passed]
        end

        it 'generates tests that fail if the params are declared incorrectly' do
          write_file "#{dir}/e1.yml", endpoint_definition_yml.gsub('object', 'oject')
          run(test_group)
          expect(results_from(test_group)).to eq [:failed]
        end
      end
    end

    describe "RSpec" do
      it_behaves_like "interpol example test definer" do
        def within_group(&block)
          RSpec::Core::ExampleGroup.describe "generated examples" do
            extend Interpol::TestHelper::RSpec
            module_eval(&block)
          end
        end

        def run(group)
          group.run(double.as_null_object)
        end

        def num_tests_from(group)
          group.examples.size
        end

        def results_from(group)
          group.examples.map { |e| e.execution_result.status }
        end
      end
    end

    describe "Test::Unit" do
      it_behaves_like "interpol example test definer" do
        before do
          stub_const("Test::Unit::TestCase", Class.new)
        end

        def within_group(&block)
          Class.new(Test::Unit::TestCase) do
            extend Interpol::TestHelper::TestUnit

            def self.results
              @results ||= []
            end

            module_eval(&block)
          end
        end

        def run(group)
          instance = group.new
          instance.methods.grep(/^test_/).each do |test|
            begin
              instance.send(test)
            rescue
              group.results << :failed
            else
              group.results << :passed
            end
          end
        end

        def num_tests_from(group)
          group.instance_methods.grep(/^test_/).size
        end

        def results_from(group)
          group.results
        end
      end
    end
  end
end

