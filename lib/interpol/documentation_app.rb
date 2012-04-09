require 'interpol'
require 'interpol/documentation'
require 'sinatra/base'

module Interpol
  module DocumentationApp
    extend self

    def build(&block)
      config = Configuration.default.customized_duplicate(&block)
      Builder.new(config).app
    end

    def render_static_page(&block)
      require 'rack/mock'
      app = build(&block)
      status, headers, body = app.call(Rack::MockRequest.env_for "/", method: "GET")
      body.join
    end

    module Helpers
      def interpol_config
        self.class.interpol_config
      end

      def endpoints
        interpol_config.endpoints
      end

      def current_endpoint
        endpoints.first
      end

      def title
        interpol_config.documentation_title
      end
    end

    # Private: Builds a stub sinatra app for the given interpol
    # configuration.
    class Builder
      attr_reader :app

      def initialize(config)
        @app = Sinatra.new do
          dir = File.dirname(File.expand_path(__FILE__))
          set :views, "#{dir}/documentation_app/views"
          set :public_folder, "#{dir}/documentation_app/public"
          set :interpol_config, config
          helpers Helpers

          get('/') do
            erb :layout, locals: { endpoints: endpoints, current_endpoint: current_endpoint }
          end
        end
      end
    end
  end
end

