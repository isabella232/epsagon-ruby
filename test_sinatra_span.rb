# frozen_string_literal: true

require 'sinatra'
require './lib/epsagon'
require 'JSON'

post '/*' do
  JSON.generate({body: request.body.read, path: request.path})
end
