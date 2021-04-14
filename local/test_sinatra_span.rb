# frozen_string_literal: true

require 'sinatra'
require './lib/epsagon'
require 'json'
require 'net/http'

Epsagon.init(metadata_only: true, debug: true)

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
    OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
  )
end

get '/*' do
  # Net::HTTP.get('example.com', '/index.html')
  JSON.generate({ body: request.body.read, path: request.path })
end
