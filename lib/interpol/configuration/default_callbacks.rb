request_version do
  raise ConfigurationError, "request_version has not been configured"
end

response_version do
  raise ConfigurationError, "response_version has not been configured"
end

validate_response_if do |env, status, headers, body|
  headers['Content-Type'].to_s.include?('json') &&
  status >= 200 && status <= 299 && status != 204 # No Content
end

validate_request_if do |env|
  env['CONTENT_TYPE'].to_s.include?('json') &&
  %w[ POST PUT PATCH ].include?(env.fetch('REQUEST_METHOD'))
end

on_unavailable_request_version do |env, requested, available|
  message = "The requested request version is invalid. " +
            "Requested: #{requested}. " +
            "Available: #{available}"

  rack_json_response(406, :error => message)
end

on_unavailable_sinatra_request_version do |requested, available|
  message = "The requested request version is invalid. " +
            "Requested: #{requested}. " +
            "Available: #{available}"

  halt 406, JSON.dump(:error => message)
end

on_invalid_request_body do |env, error|
  rack_json_response(400, :error => error.message)
end

on_invalid_sinatra_request_params do |error|
  halt 400, JSON.dump(:error => error.message)
end

select_example_response do |endpoint_def, _|
  endpoint_def.examples.first
end

