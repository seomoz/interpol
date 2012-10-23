define_request_param_parser('integer') do |param|
  param.string_validation_options 'pattern' => '^\-?\d+$'

  param.parse do |value|
    begin
      raise TypeError unless value # On 1.8.7 Integer(nil) does not raise an error
      Integer(value)
    rescue TypeError
      raise ArgumentError, "Could not convert #{value.inspect} to an integer"
    end
  end
end

define_request_param_parser('number') do |param|
  param.string_validation_options 'pattern' => '^\-?\d+(\.\d+)?$'

  param.parse do |value|
    begin
      Float(value)
    rescue TypeError
      raise ArgumentError, "Could not convert #{value.inspect} to a float"
    end
  end
end

define_request_param_parser('boolean') do |param|
  param.string_validation_options 'enum' => %w[ true false ]

  booleans = { 'true'  => true,  true  => true,
               'false' => false, false => false }
  param.parse do |value|
    booleans.fetch(value) do
      raise ArgumentError, "Could not convert #{value.inspect} to a boolean"
    end
  end
end

define_request_param_parser('null') do |param|
  param.string_validation_options 'enum' => ['']

  nulls = { '' => nil, nil => nil }
  param.parse do |value|
    nulls.fetch(value) do
      raise ArgumentError, "Could not convert #{value.inspect} to a null"
    end
  end
end

define_request_param_parser('string') do |param|
  param.parse do |value|
    unless value.is_a?(String)
      raise ArgumentError, "#{value.inspect} is not a string"
    end

    value
  end
end

define_request_param_parser('string', 'format' => 'date') do |param|
  param.parse do |value|
    unless value =~ /\A\d{4}\-\d{2}\-\d{2}\z/
      raise ArgumentError, "#{value.inspect} is not in iso8601 format"
    end

    Date.new(*value.split('-').map(&:to_i))
  end
end

define_request_param_parser('string', 'format' => 'date-time') do |param|
  param.parse &Time.method(:iso8601)
end

define_request_param_parser('string', 'format' => 'uri') do |param|
  param.parse do |value|
    begin
      URI(value).tap do |uri|
        unless uri.scheme && uri.host
          raise ArgumentError, "#{uri.inspect} is not a valid full URI"
        end
      end
    rescue URI::InvalidURIError => e
      raise ArgumentError, e.message, e.backtrace
    end
  end
end

