require 'interpol/define_singleton_method' unless Object.method_defined?(:define_singleton_method)

module Interpol
  # Transforms an arbitrarily deeply nested hash into a dot-syntax
  # object. Useful as an alternative to a hash since it is "strongly typed"
  # in the sense that fat-fingered property names result in a NoMethodError,
  # rather than getting a nil as you would with a hash.
  class DynamicStruct
    attr_reader :attribute_names, :to_hash

    def initialize(hash)
      @to_hash = hash
      @attribute_names = hash.keys.map(&:to_sym)

      hash.each do |key, value|
        value = method_value_for(value)
        define_singleton_method(key) { value }
        define_singleton_method("#{key}?") { !!value }
      end
    end

  private

    def method_value_for(hash_value)
      return self.class.new(hash_value) if hash_value.is_a?(Hash)

      if hash_value.is_a?(Array) && hash_value.all? { |v| v.is_a?(Hash) }
        return hash_value.map { |v| self.class.new(v) }
      end

      hash_value
    end

    include DefineSingletonMethod unless method_defined?(:define_singleton_method)
  end
end

