require 'interpol/request_params_parser'
require 'forwardable'

module Interpol
  module Sinatra
    # Parses and validates a sinatra params hash based on the
    # endpoint definitions.
    # Note that you use this like a sinatra middleware
    # (using a `use` directive in the body of the sinatra class), but
    # it hooks into sinatra differently so that it has access to the params.
    # It's more like a mix-in, honestly, but we piggyback on `use` so that
    # it can take a config block.
    class RequestParamsParser
      def initialize(app, &block)
        @original_app_instance = app
        @config = Configuration.default.customized_duplicate(&block)
        hook_into_app(&block)
      end

      def call(env)
        @original_app_instance.call(env)
      end

      ConfigurationError = Class.new(StandardError)

      # Sinatra dups the app before each request, so we need to
      # receive the app instance as an argument here.
      def validate_and_parse_params(app)
        return unless app.settings.parse_params?
        SingleRequestParamsParser.parse_params(config, app)
      end

    private

      attr_reader :config, :original_app_instance

      def hook_into_app(&block)
        return if original_app_instance.respond_to?(:unparsed_params)
        check_configuration_validity
        parser = self

        original_app_instance.class.class_eval do
          alias unparsed_params params
          set :request_params_parser, parser
          enable :parse_params unless settings.respond_to?(:parse_params)
          include SinatraOverriddes
        end
      end

      def check_configuration_validity
        return if original_app_instance.class.ancestors.include?(::Sinatra::Base)

        raise ConfigurationError, "#{self.class} must come last in the Sinatra " +
                                  "middleware list but #{original_app_instance.class} " +
                                  "currently comes after."
      end

      # Handles finding parsing request params for a single request.
      class SingleRequestParamsParser
        def self.parse_params(config, app)
          new(config, app).parse_params
        end

        def initialize(config, app)
          @config = config
          @app = app
        end

        def parse_params
          endpoint_definition.parse_request_params(params_to_parse)
        rescue Interpol::ValidationError => error
          request_params_invalid(error)
        end

      private

        attr_reader :app, :config
        extend Forwardable
        def_delegators :app, :request

        def endpoint_definition
          version = available_versions = nil

          definition = config.endpoints.find_definition \
            request.env.fetch('REQUEST_METHOD'), request.path, 'request', nil do |endpoint|
              available_versions ||= endpoint.available_versions
              config.request_version_for(request.env, endpoint).tap do |_version|
                version ||= _version
              end
            end

          if definition == DefinitionFinder::NoDefinitionFound
            config.request_version_unavailable(app, version, available_versions)
          end

          definition
        end

        # Sinatra includes a couple of "meta" params that are always
        # present in the params hash even though they are not declared
        # as params: splat and captures.
        def params_to_parse
          app.unparsed_params.dup.tap do |p|
            p.delete('splat')
            p.delete('captures')
          end
        end

        def request_params_invalid(error)
          config.sinatra_request_params_invalid(app, error)
        end
      end

      module SinatraOverriddes
        extend Forwardable
        def_delegators :settings, :request_params_parser

        # We cannot access the full params (w/ path params) in a before hook,
        # due to the order that sinatra runs the hooks in relation to route
        # matching.
        def process_route(*method_args, &block)
          return super unless SinatraOverriddes.being_processed_by_sinatra?(block)

          super do |*block_args|
            with_parsed_params do
              yield *block_args
            end
          end
        end

        def self.being_processed_by_sinatra?(block)
          # In case the block is nil or we're on 1.8 w/o #source_location...
          # Just assume the route is being processed by sinatra.
          # It's an exceptional case for it to not be (e.g. NewRelic's
          # Sinatra hook).
          return true unless block.respond_to?(:source_location)
          block.source_location.first.end_with?('sinatra/base.rb')
        end

        def params
          @_parsed_params || super
        end

        def with_parsed_params
          unless @_skip_param_parsing
            @_parsed_params = request_params_parser.validate_and_parse_params(self)
          end

          yield
        ensure
          @_parsed_params = nil
        end

        def skip_param_parsing!
          @_skip_param_parsing = true
        end
      end
    end
  end
end

