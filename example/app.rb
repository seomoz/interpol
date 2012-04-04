require 'sinatra'
require 'json'

unless ENV['RACK_ENV'] == 'production'
  require_relative 'interpol_config'
  require 'interpol/response_schema_validator'
  use Interpol::ResponseSchemaValidator
end

CONTACTS = {
  'good' => {
    'first_name' => 'John',
    'last_name' => 'Doe',
    'date_of_birth' => Date.new(1975, 3, 12),
    'gender' => 'male'
  },

  'bad' => {
    'first_name' => 'Jane',
    'last_name' => 'Doe'
  }
}

helpers do
  def contact
    CONTACTS.fetch(params[:contact_id]) { halt 404, "Not found" }
  end
end

get '/contacts/:contact_id' do
  content_type :json
  JSON.dump(contact)
end
