# frozen_string_literal: true

require 'sinatra'
require 'json'
require 'net/http'


set port: 4566

get '/make-error' do
	raise
end

get '/make-request' do
	raise
end


post '/*' do
  JSON.generate({ body: request.body.read, path: request.path })
end

