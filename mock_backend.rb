
require 'sinatra'

set port: 4568

post '/*' do
	File.open('tmp/body.pb', 'wb') { |file| file.write(env['rack.input'].read) }
  ''
end
