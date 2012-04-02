require 'fast_spec_helper'
require 'interpol/configuration'

module Interpol
  describe Configuration do
    let(:config) { Configuration.new }

    describe "#endpoint_definition_files" do
      it 'allows files to be set as a glob' do
        config.endpoint_definition_files = Dir["spec/fixtures/dir_with_two_yaml_files/*.yml"]
        files = config.endpoint_definition_files
        files.map { |f| f.split('/').last }.should =~ %w[ one.yml two.yml ]
      end
    end
  end
end

