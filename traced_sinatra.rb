# frozen_string_literal: true

require 'sinatra'
require './lib/epsagon'
require 'json'
require 'net/http'

Epsagon.init(metadata_only: false, debug: true, backend: 'localhost:4568/test/trace/path', insecure: true)

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
    OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
  )
end

post '/*' do
  JSON.generate({ body: request.body.read, path: request.path })
end
