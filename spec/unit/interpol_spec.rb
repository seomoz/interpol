require 'fast_spec_helper'
require 'interpol'

describe Interpol do
  describe ".default_configuration" do
    it 'returns Configuration.default' do
      Interpol.default_configuration.should be(Interpol::Configuration.default)
    end

    it 'yields the configuration instance if a block is given' do
      yielded1 = nil
      Interpol.default_configuration { |c| yielded1 = c }
      yielded1.should be(Interpol.default_configuration)

      yielded2 = nil
      Interpol.default_configuration { |c| yielded2 = c }
      yielded2.should be(Interpol.default_configuration)
    end
  end
end

