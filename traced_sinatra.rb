# frozen_string_literal: true

require 'sinatra'
require './lib/epsagon'
require 'json'
require 'net/http'

BACKEND = 'opentelemetry.tc.epsagon.com:443/traces'

Epsagon.init(metadata_only: false, debug: true, backend: BACKEND, app_name: 'send-test-spans')

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
    OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
  )
end

get '/make-error' do
	raise
end


post '/*' do
  JSON.generate({ body: request.body.read, path: request.path })
end
