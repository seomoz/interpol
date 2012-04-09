# Interpol Example

This directory contains an example application that uses interpol.

## Setup

Ensure the gems are all installed:

```
bundle install
```

## Run the tests

Interpol provides support for generating tests in either Test::Unit or RSpec.
This example app includes both. The endpoint definition contains an example
with a fat-fingered attribute name in order to demonstrate what failures
from generated interpol tests look like.

Run the RSpec tests:

```
$ rake spec

API Examples
  show_contact (v 1.0) has valid data for example 1
  show_contact (v 1.0) has valid data for example 2
  show_contact (v 1.0) has valid data for example 3 (FAILED - 1)

Failures:

  1) API Examples show_contact (v 1.0) has valid data for example 3
     Failure/Error: define_test(description) { example.validate! }
     Interpol::ValidationError:
       Found 2 error(s) when validating against endpoint show_contact (v. 1.0). Errors: 
         - The property '#/' did not contain a required property of 'date_of_birth' in schema 393a88cb-bc93-529f-a9da-fe00de85e0d9#
         - The property '#/' contains additional properties ["date_of_brith"] outside of the schema when none are allowed in schema 393a88cb-bc93-529f-a9da-fe00de85e0d9#.

       Data:
       {"first_name"=>"Jack", "last_name"=>"Brown", "date_of_brith"=>"1981-08-03", "gender"=>"male"}
     # /Users/myron/code/interpol/lib/interpol/endpoint.rb:97:in `validate_data!'
     # /Users/myron/code/interpol/lib/interpol/endpoint.rb:129:in `validate!'
     # /Users/myron/code/interpol/lib/interpol/test_helper.rb:22:in `block (2 levels) in define_interpol_example_tests'

Finished in 0.01537 seconds
3 examples, 1 failure
```

Run the Test::Unit tests:

```
$ rake test
Run options: 

# Running tests:

..E

Finished tests in 0.014566s, 205.9591 tests/s, 0.0000 assertions/s.

  1) Error:
test_show_contact_v_1_0_has_valid_data_for_example_3(APIExamplesTest):
Interpol::ValidationError: Found 2 error(s) when validating against endpoint show_contact (v. 1.0). Errors: 
  - The property '#/' did not contain a required property of 'date_of_birth' in schema 393a88cb-bc93-529f-a9da-fe00de85e0d9#
  - The property '#/' contains additional properties ["date_of_brith"] outside of the schema when none are allowed in schema 393a88cb-bc93-529f-a9da-fe00de85e0d9#.

Data:
{"first_name"=>"Jack", "last_name"=>"Brown", "date_of_brith"=>"1981-08-03", "gender"=>"male"}
    /Users/myron/code/interpol/lib/interpol/endpoint.rb:97:in `validate_data!'
    /Users/myron/code/interpol/lib/interpol/endpoint.rb:129:in `validate!'
    /Users/myron/code/interpol/lib/interpol/test_helper.rb:22:in `block (2 levels) in define_interpol_example_tests'

3 tests, 0 assertions, 0 failures, 1 errors, 0 skips
```

## Run the stub app

`stub_app.config.ru` contains the stub app, generated from the endpoint definition.

```
rake boot_stub_app
```

Let's hit this with curl:

```
$ curl -is localhost:3100/contacts/17

HTTP/1.1 200 OK 
X-Frame-Options: sameorigin
X-Xss-Protection: 1; mode=block
Content-Type: application/json;charset=utf-8
Content-Length: 84
Server: WEBrick/1.3.1 (Ruby/1.9.3/2012-02-16)
Date: Thu, 05 Apr 2012 18:07:34 GMT
Connection: Keep-Alive

{"first_name":"John","last_name":"Doe","date_of_birth":"1979-05-23","gender":"male"}
```

## Run the real app with the ResponseSchemaValidator middleware

`app.rb` contains an implementation of the "real app" using sinatra.
Let's start it:

```
rake boot_app
```

In your browser, go to `http://localhost:4567/contacts/good` (which
should render valid JSON) and `http://localhost:4567/contacts/bad`
(which should render a validation error).

## Run the documentation app

`documentation_app.config.ru` contains the documentation app,
generated from the endpoint definition. Let's start it:

```
rake boot_stub_app
```

Then visit `localhost:3200/` in your web browser.

