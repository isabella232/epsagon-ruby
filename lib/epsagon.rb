# frozen_string_literal: true

require 'rubygems'
require 'net/http'
require 'bundler/setup'
require 'opentelemetry'

require_relative 'instrumentation/sinatra'
require_relative 'instrumentation/net_http'
require_relative 'instrumentation/faraday'
require_relative 'util'

Bundler.require

def metadata_only?
  ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false'
end

def debug?
  ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true'
end

# #config opentelemetry with epsaon extensions:
OpenTelemetry::SDK.configure do |c|
  c.use 'EpsagonSinatraInstrumentation'
  c.use 'EpsagonNetHTTPInstrumentation'
  c.use 'EpsagonFaradayInstrumentation'
  if debug?
    c.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  else
    c.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      EpsagonExporter.new(headers: {
                            epasgon_token: ENV['EPSAGON_TOKEN'],
                            epasgon_app_name: ENV['EPSAGON_APP_NAME']
                          },
                          endpoint: '7fybd5lgpc.execute-api.us-east-2.amazonaws.com:443/dev/trace',
                          insecure: false)
    )
  end
end
