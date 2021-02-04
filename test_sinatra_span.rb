# frozen_string_literal: true

require 'sinatra'
require './lib/epsagon'

get '/*' do
  'Hello world!'
end
