require 'hashie/mash'

module Interpol
  # Hashie::Mash is awesome: it gives us dot/method-call syntax for a hash.
  # This is perfect for dealing with structured JSON data.
  # The downside is that Hashie::Mash responds to anything--it simply
  # creates a new entry in the backing hash.
  #
  # DynamicStruct freezes a Hashie::Mash so that it no longer responds to
  # everything.  This is handy so that consumers of this gem can distinguish
  # between a fat-fingered field, and a field that is set to nil.
  module DynamicStruct
    DEFAULT_PROC = lambda do |hash, key|
      raise NoMethodError, "undefined method `#{key}' for #{hash.inspect}"
    end

    def self.new(source)
      hash = Hashie::Mash.new(source)
      recursively_freeze(hash)
      hash
    end

    def self.recursively_freeze(object)
      case object
        when Array
          object.each { |obj| recursively_freeze(obj) }
        when Hash
          set_default_proc_on(object)
          recursively_freeze(object.values)
      end
    end

    def self.set_default_proc_on(hash)
      hash.default_proc = DEFAULT_PROC
    end
  end
end

require 'interpol/hash_set_default_proc_18' unless {}.respond_to?(:default_proc=)

