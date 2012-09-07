# 1.9 has Enumerable#each_with_object, but 1.8 does not.
# This provides 1.8 compat for the places where we use each_with_object.
module Enumerable
  def each_with_object(object)
    each { |item| yield item, object }
    object
  end
end

