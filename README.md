# Interpol

Police your HTTP JSON interface with interpol.

Interpol is a toolkit for policing your HTTP JSON interface. To use it,
you define the endpoints of your HTTP API in simple YAML files.  From
this metadata, interpol gives you three things:

* A stub sinatra app that serves up example data.
* A rack middleware that will validate the data being returned by an
  endpoint against the JSON schema for that endpoint.
* A documentation browser for your API.

## Installation

Add this line to your application's Gemfile:

    gem 'interpol'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install interpol

## Usage

First, define your API endpoints in interpol YAML files, using
a separate file per endpoint. Here's an example of what one looks like:

``` yaml
---
name: user_projects
route: /users/:user_id/projects
method: GET
entries:
  - versions: ["1.0"]
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
  it in schema validation error messages.
* `route` defines the sinatra route for this endpoint. Any valid sinatra route can be used here.
* `method` defines the HTTP method for this endpoint.  The method should be in uppercase.
* The `entries` array contains a list of tuples (each containing versions/schema/examples).
  Everytime you modify your schema and change the version, you should add a new entry here.
* The `versions` array lists the endpoint versions that should be associated with this entry.
* The `schema` contains a [JSON schema](http://tools.ietf.org/html/draft-zyp-json-schema-03)
  description of the contents of the endpoint. This schema definition is used by the
  `SchemaValidation` middleware to ensure that your implementation of the endpoint
  matches the definition.
* `examples` contains a list of valid examples. It is used by the stub app as example data.

Now that you've defined your endpoints, interpol provides several utilities to work
with the endpoints.

### Test Helpers to Validate your endpoint examples

You can use it with RSpec:

``` ruby
require 'interpol/test_helper'

describe "My API endpoints" do
  extend Interpol::TestHelper::RSpec

  define_interpol_example_tests do |ipol|
    ipol.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
  end
end
```

...or with Test::Unit:

``` ruby
require 'interpol/test_helper'

class MyAPIEndpointsTest < Test::Unit::TestCase
  extend Interpol::TestHelper::TestUnit

  define_interpol_example_tests do |ipol|
    ipol.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
  end
end
```

`define_endpoint_example_tests` defines a test for each example in the endpoint
YAML files. The example data will be validated against your JSON schema definition.
This helps ensure that your examples actually use the right JSON schema.

### Stub App

Put this in a `config.ru`:

``` ruby
require 'interpol/stub_app'

stub_app = Interpol::StubApp.build do |app|
  app.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
  app.api_version do |env|
    # This is called on each request with the Rack env hash.
    # You should return the API version for the request.
    # Interpol will use this to find an appropriate example
    # for this request based on the endpoint definition.
    "1.0"
  end
end

run stub_app
```

...and run with `rackup config.ru`.

### Schema Validation middleware

The validation middleware works with any rack app. Here's what it might look like
when used with a classic style sinatra app:

``` ruby
require 'sinatra'

# You probably only want to validate the schema in local development.
unless ENV['RACK_ENV'] == 'production'
  require 'interpol/schema_validation'
  use Interpol::SchemaValidation do |config|
    config.endpoint_definition_files = Dir["config/endpoints_definitions/*.yml"]
    config.api_version do |env|
      # This is called on each request with the Rack env hash.
      # You should return the API version for the request.
      "1.0"
    end
    config.on_validation_failure :raise # or :warn
  end
end

get '/users/:user_id/projects' do
  JSON.dump(User.find(params[:user_id]).projects)
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
