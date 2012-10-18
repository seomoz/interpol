require 'fast_spec_helper'
require 'interpol/dynamic_struct'

module Interpol
  describe DynamicStruct do
    it 'defines methods for each hash entry' do
      ds = DynamicStruct.new("a" => 5, "b" => 3)
      ds.a.should eq(5)
      ds.b.should eq(3)
    end

    it 'provides predicates' do
      ds = DynamicStruct.new("a" => 3, "b" => false)
      ds.a?.should be_true
      ds.b?.should be_false
    end

    it 'raises a NoMethodError for messages that are not in the hash' do
      ds = DynamicStruct.new("a" => 3)
      expect { ds.foo }.to raise_error(NoMethodError)
    end

    it 'recursively defines a DynamicStruct for nested hashes' do
      ds = DynamicStruct.new("a" => { "b" => { "c" => 3 } })
      ds.a.b.c.should eq(3)
    end

    it 'handles arrays properly' do
      ds = DynamicStruct.new \
        :a => [1, 2, 3],
        :b => [{ :c => 5 }, { :c => 4 }]

      ds.a.should eq([1, 2, 3])
      ds.b.map(&:c).should eq([5, 4])
    end
  end
end

