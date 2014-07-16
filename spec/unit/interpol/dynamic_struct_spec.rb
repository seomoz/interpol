require 'fast_spec_helper'
require 'interpol/dynamic_struct'

module Interpol
  RSpec.describe DynamicStruct do
    it 'defines methods for each hash entry' do
      ds = DynamicStruct.new("a" => 5, "b" => 3)
      expect(ds.a).to eq(5)
      expect(ds.b).to eq(3)
    end

    it 'provides predicates' do
      ds = DynamicStruct.new("a" => 3, "b" => false)
      expect(ds.a?).to be true
      expect(ds.b?).to be false
    end

    it 'raises a NoMethodError for messages that are not in the hash' do
      ds = DynamicStruct.new("a" => 3)
      expect { ds.foo }.to raise_error(NoMethodError)
    end

    it 'recursively defines a DynamicStruct for nested hashes' do
      ds = DynamicStruct.new("a" => { "b" => { "c" => 3 } })
      expect(ds.a.b.c).to eq(3)
    end

    it 'handles arrays properly' do
      ds = DynamicStruct.new \
        :a => [1, 2, 3],
        :b => [{ :c => 5 }, { :c => 4 }]

      expect(ds.a).to eq([1, 2, 3])
      expect(ds.b.map(&:c)).to eq([5, 4])
    end

    it 'returns nil when #[] is passed an undefined key' do
      ds = DynamicStruct.new("a" => { "b" => { "c" => 3 } })
      expect(ds["b"]).to eq(nil)
    end

    hash_methods_allowed_as_params = [:sort]

    hash_methods_allowed_as_params.each do |meth|
      it "delegates ##{meth} to the hash entry even though it is a hash method" do
        expect({}).to respond_to(meth)
        ds = DynamicStruct.new(meth.to_s => "v1", "inner" => {
          meth.to_s => "v2" })
        expect(ds.send(meth)).to eq("v1")
        expect(ds.inner.send(meth)).to eq("v2")
      end
    end
  end
end

