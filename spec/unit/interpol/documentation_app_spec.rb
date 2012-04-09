require 'fast_spec_helper'
require 'interpol/documentation_app'
require 'rack/test'

module Interpol
  describe DocumentationApp do
    include Rack::Test::Methods

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


    let(:endpoint) { Endpoint.new(YAML.load endpoint_definition_yml) }
    attr_accessor :skip_doc_title_config

    let(:app) do
      skip_doc_title_config = self.skip_doc_title_config
      DocumentationApp.build do |config|
        config.endpoints = [endpoint]
        config.documentation_title = "My Cool API" unless skip_doc_title_config
      end.tap do |a|
        a.set :raise_errors, true
        a.set :show_exceptions, false
      end
    end

    it 'renders documentation' do
      get '/'
      last_response.body.should include("project_list", "/users/:user_id/projects")
    end

    it 'includes the configured documentation_title in the markup' do
      get '/'
      last_response.body.should include("My Cool API")
    end

    it 'provides a default title when none is configured' do
      self.skip_doc_title_config = true
      get '/'
      last_response.body.should include("API Documentation Provided by Interpol")
    end

    describe ".render_static_page" do
      let(:static_page) do
        DocumentationApp.render_static_page do |config|
          config.endpoints = [endpoint]
          config.documentation_title = "My Cool API"
        end
      end

      it "renders the documentation" do
        static_page.should include("project_list", "My Cool API")
      end
    end
  end
end

