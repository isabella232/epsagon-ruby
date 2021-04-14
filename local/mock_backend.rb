# frozen_string_literal: true

require 'sinatra'

set port: 4568

post '/*' do
  puts('mock backend!')
  File.open('tmp/body.pb', 'wb') { |file| file.write(env['rack.input'].read) }
  ''
end
