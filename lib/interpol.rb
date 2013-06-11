require "interpol/configuration"
require "interpol/version"

# The Interpol namespace. Provides only the default configuration.
# Each of the tools is self-contained and should be required independently.
module Interpol
  extend self

  def default_configuration(&block)
    block ||= lambda { |c| }
    Configuration.default.tap(&block)
  end
end

