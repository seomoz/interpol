require 'interpol/request_params_parser'

module Interpol
  module Sinatra
    module RequestParamsParser
      def self.add_to(app, &block)
        config = Configuration.default.customized_duplicate(&block)

        app.class_eval do
          alias unparsed_params params
          helpers SinatraHelpers
          set :interpol_config, config
          include SinatraOverriddes
        end
      end

      module SinatraHelpers
        # Make the config available at the instance level for convenience.
        def interpol_config
          self.class.interpol_config
        end

        def endpoint_definition
          @endpoint_definition ||= begin
            version = available_versions = nil

            definition = interpol_config.endpoints.find_definition \
              env.fetch('REQUEST_METHOD'), request.path, 'request', nil do |endpoint|
                available_versions ||= endpoint.available_versions
                interpol_config.api_version_for(env, endpoint).tap do |_version|
                  version ||= _version
                end
              end

            if definition == DefinitionFinder::NoDefinitionFound
              interpol_config.request_version_unavailable(self, version, available_versions)
            end

            definition
          end
        end

        def params
          @_parsed_params || super
        end

        def validate_params
          @_parsed_params = endpoint_definition.parse_request_params(params_to_parse)
        rescue Interpol::ValidationError => error
          request_params_invalid(error)
        end

        def request_params_invalid(error)
          interpol_config.sinatra_request_params_invalid(self, error)
        end

        # Sinatra includes a couple of "meta" params that are always
        # present in the params hash even though they are not declared
        # as params: splat and captures.
        def params_to_parse
          unparsed_params.dup.tap do |p|
            p.delete('splat')
            p.delete('captures')
          end
        end
      end

      module SinatraOverriddes
        # We cannot access the full params (w/ path params) in a before hook,
        # due to the order that sinatra runs the hooks in relation to route
        # matching.
        def process_route(*method_args)
          super do |*block_args|
            validate_params
            yield *block_args
          end
        end
      end
    end
  end
end

