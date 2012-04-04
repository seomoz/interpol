require 'test/unit'
require_relative 'interpol_config'
require 'interpol/test_helper'

class APIExamplesTest < Test::Unit::TestCase
  extend Interpol::TestHelper::TestUnit
  define_interpol_example_tests
end

