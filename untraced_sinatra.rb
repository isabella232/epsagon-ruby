# frozen_string_literal: true

require 'sinatra'
require 'JSON'

set port: 4566

post '/*' do
  JSON.generate({body: request.body.read, path: request.path})
end
