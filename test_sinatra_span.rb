# frozen_string_literal: true

require 'sinatra'
require './lib/epsagon'
require 'json'

post '/*' do
  JSON.generate({ body: request.body.read, path: request.path })
end
