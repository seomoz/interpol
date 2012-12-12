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
    SAFE_METHOD_MISSING = ::Hashie::Mash.superclass.instance_method(:method_missing)

    Mash = Class.new(::Hashie::Mash) do
      undef sort
    end

    def self.new(*args)
      Mash.new(*args).tap do |mash|
        mash.extend(self)
      end
    end

    def self.extended(mash)
      recursively_extend(mash)
    end

    def self.recursively_extend(object)
      case object
        when Array
          object.each { |v| recursively_extend(v) }
        when Mash
          object.extend(self) unless object.is_a?(self)
          object.each { |_, v| recursively_extend(v) }
      end
    end

    def method_missing(method_name, *args, &blk)
      if key = method_name.to_s[/\A([^?=]*)[?=]?\z/, 1]
        unless has_key?(key)
          return safe_method_missing(method_name, *args, &blk)
        end
      end

      super
    end

  private

    def safe_method_missing(*args)
      SAFE_METHOD_MISSING.bind(self).call(*args)
    end
  end
end

