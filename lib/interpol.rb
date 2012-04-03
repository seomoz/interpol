require "interpol/configuration"
require "interpol/version"

module Interpol
  extend self

  def default_configuration(&block)
    block ||= lambda { |c| }
    Configuration.default.tap(&block)
  end
end

