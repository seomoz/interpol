require 'sinatra/base'

module Interpol
  class DocumentationApp < Sinatra::Base
    dir = File.dirname(File.expand_path(__FILE__))

    set :views, "#{dir}/documentation_app/views"
    set :public_folder, "#{dir}/documentation_app/public"

    get '/' do
      erb :layout
    end
  end
end

