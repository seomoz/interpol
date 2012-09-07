module Interpol
  # 1.9 has Object#define_singleton_method but 1.8 does not.
  # This provides 1.8 compatibility for the places we need it.
  module DefineSingletonMethod
    def define_singleton_method(name, &block)
      (class << self; self; end).send(:define_method, name, &block)
    end
  end
end

