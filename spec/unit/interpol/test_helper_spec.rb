require 'fast_spec_helper'
require 'interpol/test_helper'

module Interpol
  describe TestHelper, :clean_endpoint_dir do
    shared_examples_for "interpol example test definer" do
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

      it 'generates a test per data example per definition per endpoint' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml.gsub('["1.0"]', '["1.0", "2.0"]')
        write_file "#{dir}/e2.yml", endpoint_definition_yml.gsub("project_list", "project_list_2")
        num_tests_from(test_group).should eq(9)
      end

      it 'generates tests that fail if their example data is invalid' do
        write_file "#{dir}/e1.yml", endpoint_definition_yml
        run(test_group)
        results_from(test_group).should =~ ['passed', 'failed', 'failed']
      end
    end

    describe "RSpec" do
      it_behaves_like "interpol example test definer" do
        def within_group(&block)
          describe "generated examples" do
            extend Interpol::TestHelper::RSpec
            module_eval(&block)
          end
        end

        def run(group)
          group.run(stub.as_null_object)
        end

        def num_tests_from(group)
          group.examples.size
        end

        def results_from(group)
          group.examples.map{ |e| e.execution_result[:status] }
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
            rescue => e
              group.results << "failed"
            else
              group.results << "passed"
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

