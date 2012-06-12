# Interpol
![Interpol Logo](https://github.com/seomoz/interpol/blob/assets/interpol-logo.png?raw=true)

[![Build Status](https://secure.travis-ci.org/seomoz/interpol.png)](http://travis-ci.org/seomoz/interpol)

Interpol is a toolkit for policing your HTTP JSON interface. To use it,
define the endpoints of your HTTP API in simple YAML files.
Interpol provides multiple tools to work with these endpoint
definitions:

* `Interpol::TestHelper::RSpec` and `Interpol::TestHelper::TestUnit` are
  modules that you can mix in to your test context. They provide a means
  to generate tests from your endpoint definitions that validate example
  data against your JSON schema definition.
* `Interpol::StubApp` builds a stub implementation of your API from
  the endpoint definitions. This can be distributed with your API's
  client gem so that API users have something local to hit that
  generates data that is valid according to your schema definition.
* `Interpol::ResponseSchemaValidator` is a rack middleware that
  validates your API responses against the JSON schema in your endpoint
  definition files. This is useful in test/development environments to
  ensure that your real API returns valid responses.
* `Interpol::DocumentationApp` builds a sinatra app that renders
  documentation for your API based on the endpoint definitions.

You can use any of these tools individually or some combination of all
of them.

## Installation

Add this line to your application's Gemfile:

    gem 'interpol'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install interpol

## Endpoint Definition

Endpoints are defined in YAML files, using a separate
file per endpoint. Here's an example:

``` yaml
---
name: user_projects
route: /users/:user_id/projects
method: GET
definitions:
  - message_type: response
    versions: ["1.0"]
    status_codes: ["2xx", "404"]
    schema:
      description: Returns a list of projects for the given user.
      type: object
      properties:
        projects:
          description: List of projects.
          type: array
          items:
            type: object
            properties:
              name:
                description: The name of the project.
                type: string
              importance:
                description: The importance of the project, on a scale of 1 to 10.
                type: integer
                minimum: 1
                maximum: 10

    examples:
      - projects:
        - name: iPhone App
          importance: 5
        - name: Rails App
          importance: 7
```

Let's look at this YAML file, point-by-point:

* `name` can be anything you want. Each endpoint should have a different name. Interpol uses
  it in schema validation error messages. It is also used by the
  documentation app.
* `route` defines the sinatra route for this endpoint. Note that while
  Interpol::StubApp supports any sinatra route, Interpol::ResponseSchemaValidator
  (which has to find a matching endpoint definition from the request path), only
  supports a subset of Sinatra's routing syntax. Specifically, it supports static
  segments (`users` and `projects` in the example above) and named
  parameter segments (`:user_id` in the example above).
* `method` defines the HTTP method for this endpoint.  The method should be in uppercase.
* The `definitions` array contains a list of versioned schema definitions, with
  corresponding examples.  Everytime you modify your schema and change the version,
  you should add a new entry here.
* The `message_type` describes whether the following schema is for requests or responses.
  It is an optional attribute that when omitted defaults to response. The only valid values
  are `request` and `response`.
* The `versions` array lists the endpoint versions that should be associated with a
  particular schema definition.
* The `status_codes` is an optional array of status code strings describing for which
  status code or codes this schema applies to. `status_codes` is ignored if used with the
  `request` `message_type`. When used with the `response` `message_type` it is an optional
  attribute that defaults to all status codes. Valid formats for a status code are 3
  characters. Each character must be a digit (0-9) or 'x' (wildcard). The following strings
  are all valid: "200", "4xx", "x0x".
* The `schema` contains a [JSON schema](http://tools.ietf.org/html/draft-zyp-json-schema-03)
  description of the contents of the endpoint. This schema definition is used by the
  `SchemaValidation` middleware to ensure that your implementation of the endpoint
  matches the definition.
* `examples` contains a list of valid example data. It is used by the stub app as example data.

## Configuration

Interpol provides two levels of configuration: global default
configuration, and one-off configuration, set on a particular
instance of one of the provided tools. Each of the tools accepts
a configuration block that provides an identical API to the
global configuration API shown below.

``` ruby
require 'interpol'

Interpol.default_configuration do |config|
  # Tells Interpol where to find your endpoint definition files.
  #
  # Needed by all tools.
  config.endpoint_definition_files = Dir["config/endpoints/*.yml"]

  # Determines which versioned endpoint definition Interpol uses
  # for a request. You can also use a block form, which yields
  # the rack env hash and the endpoint object as arguments.
  # This is useful when you need to extract the version from a
  # request header (e.g. Accept) or from the request URI.
  #
  # Needed by Interpol::StubApp and Interpol::ResponseSchemaValidator.
  config.api_version '1.0'

  # Determines the stub app response when the requested version is not
  # available. This block will be eval'd in the context of the stub app
  # sinatra application, so you can use sinatra helpers like `halt` here.
  #
  # Needed by Interpol::StubApp.
  config.on_unavailable_request_version do |requested_version, available_versions|
    message = JSON.dump(
      "message" => "Not Acceptable",
      "requested_version" => requested_version,
      "available_versions" => available_versions
    )

    halt 406, message
  end

  # Determines which responses will be validated against the endpoint
  # definition when you use Interpol::ResponseSchemaValidator. The
  # validation is meant to run against the "happy path" response.
  # For responses like "404 Not Found", you probably don't want any
  # validation performed. The default validate_if hook will cause
  # validation to run against any 2xx response except 204 ("No Content").
  #
  # Used by Interpol::ResponseSchemaValidator.
  config.validate_if do |env, status, headers, body|
    headers['Content-Type'] == my_custom_mime_type
  end

  # Determines how Interpol::ResponseSchemaValidator handles
  # invalid data. By default it will raise an error, but you can
  # make it print a warning instead.
  #
  # Used by Interpol::ResponseSchemaValidator.
  config.validation_mode = :error # or :warn

  # Determines the title shown on the rendered documentation
  # pages.
  #
  # Used by Interpol::DocumentationApp.
  config.documentation_title = "Acme Widget API Documentaton"
end

```

## Tool Usage

### Interpol::TestHelper::RSpec and Interpol::TestHelper::TestUnit

These are modules that you can extend onto an RSpec example group
or a `Test::Unit::TestCase` subclass, respectively.
They provide a `define_interpol_example_tests` macro that will define
a test for each example for each schema definition in your endpoint
definition files. The tests will validate that your schema is a valid
JSON schema definition and will validate that the examples are valid
according to that schema.

RSpec example:

``` ruby
require 'interpol/test_helper'

describe "My API endpoints" do
  extend Interpol::TestHelper::RSpec

  # the block is only necessary if you want to override the default
  # config or if you have not set a default config.
  define_interpol_example_tests do |ipol|
    ipol.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
  end
end
```

Test::Unit example:

``` ruby
require 'interpol/test_helper'

class MyAPIEndpointsTest < Test::Unit::TestCase
  extend Interpol::TestHelper::TestUnit
  define_interpol_example_tests
end
```

### Interpol::StubApp

This will build a little sinatra app that returns example data from
your endpoint definition files.

Example:

``` ruby
# config.ru

require 'interpol/stub_app'

# the block is only necessary if you want to override the default
# config or if you have not set a default config.
stub_app = Interpol::StubApp.build do |app|
  app.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
  app.api_version do |env|
    RequestVersion.extract_from(env['HTTP_ACCEPT'])
  end
end

run stub_app
```

### Interpol::ResponseSchemaValidator

This rack middleware validates the responses from your app
against the schema definition. Here's an example of how you
might use it with a class-style sinatra app:

``` ruby
require 'sinatra'

# You probably only want to validate the schema in local development.
unless ENV['RACK_ENV'] == 'production'
  require 'interpol/response_schema_validator'

  # the block is only necessary if you want to override the default
  # config or if you have not set a default config.
  use Interpol::ResponseSchemaValidator do |config|
    config.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
    config.api_version do |env|
      RequestVersion.extract_from(env['HTTP_ACCEPT'])
    end
  end
end

get '/users/:user_id/projects' do
  JSON.dump(User.find(params[:user_id]).projects)
end
```

### Interpol::DocumentationApp

This will build a little sinatra app that renders documentation
about your API based on your endpoint definitions.

``` ruby
# config.ru

require 'interpol/documentation_app'

# the block is only necessary if you want to override the default
# config or if you have not set a default config.
doc_app = Interpol::DocumentationApp.build do |app|
  app.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
  app.documentation_title = "My API Documentation"
end

run doc_app
```

Note: the documentation app is definitely a work-in-progress and I'm not
a front-end/UI developer. I'd happily accept a pull request improving it!

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
