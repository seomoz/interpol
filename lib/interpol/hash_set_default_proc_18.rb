module Interpol
  module DynamicStruct
    # Hash#default_proc= isn't defined on 1.8; this is the best we can do.
    def self.set_default_proc_on(hash)
      hash.replace(Hash.new(&DEFAULT_PROC).merge(hash))
    end
  end
end

