require 'interpol'
require 'interpol/documentation'
require 'sinatra/base'
require 'nokogiri'

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
      status, headers, body = app.call(Rack::MockRequest.env_for "/", :method => "GET")
      AssetInliner.new(body.enum_for(:each).to_a.join, app.public_folder).standalone_page
    end

    # Inlines the assets so the page can be viewed as a standalone web page.
    class AssetInliner
      def initialize(page, asset_root)
        @page, @asset_root = page, asset_root
        @doc = Nokogiri::HTML(page)
      end

      def standalone_page
        inline_stylesheets
        inline_javascript
        @doc.to_s
      end

    private

      def inline_stylesheets
        @doc.css("link[rel=stylesheet]").map do |link|
          inline_asset link, "style", link['href'], :type => "text/css"
        end
      end

      def inline_javascript
        @doc.css("script[src]").each do |script|
          inline_asset script, "script", script['src'], :type => "text/javascript"
        end
      end

      def contents_for(asset)
        File.read(File.join(@asset_root, asset))
      end

      def inline_asset(tag, tag_type, filename, attributes = {})
        inline_tag = Nokogiri::XML::Node.new(tag_type, @doc)
        attributes.each { |k, v| inline_tag[k] = v }
        inline_tag.content = contents_for(filename)
        tag.add_next_sibling(inline_tag)
        tag.remove
      end
    end

  private

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

      def url_path(*path_parts)
        [ path_prefix, path_parts ].join("/").squeeze('/')
      end
      alias_method :u, :url_path

      def path_prefix
        request.env['SCRIPT_NAME']
      end
    end

    # Private: Builds a stub sinatra app for the given interpol
    # configuration.
    class Builder
      attr_reader :app

      def initialize(config)
        @app = ::Sinatra.new do
          dir = File.dirname(File.expand_path(__FILE__))
          set :views, "#{dir}/documentation_app/views"
          set :public_folder, "#{dir}/documentation_app/public"
          set :interpol_config, config
          helpers Helpers

          get('/') do
            erb :layout, :locals => { :endpoints => endpoints,
                                      :current_endpoint => current_endpoint }
          end

          def self.name
            "Interpol::DocumentationApp (anonymous)"
          end
        end
      end
    end
  end
end

