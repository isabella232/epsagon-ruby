# frozen_string_literal: true

require 'rubygems'
require 'net/http'
require 'bundler/setup'
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

require_relative 'instrumentation/sinatra'
require_relative 'instrumentation/net_http'
require_relative 'instrumentation/faraday'
require_relative 'util'

Bundler.require

# Epsagon tracing main entry point
module Epsagon
  @@epsagon_config = {
      metadata_only: ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false',
      debug: ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true',
      token: ENV['EPSAGON_TOKEN'],
      app_name: ENV['EPSAGON_APP_NAME'],
      backend: ENV['EPSAGON_BACKEND'] || 'localhost:55681/v1/trace'
    }

  module_function

  def init(**args)
    @@epsagon_config.merge!(args)
    OpenTelemetry::SDK.configure
  end

  # config opentelemetry with epsaon extensions:

  def epsagon_confs(configurator)
    configurator.resource = OpenTelemetry::SDK::Resources::Resource.telemetry_sdk.merge(
      OpenTelemetry::SDK::Resources::Resource.create({ 'application' => @@epsagon_config[:app_name] })
    )
    configurator.use 'EpsagonSinatraInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonNetHTTPInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonFaradayInstrumentation', { epsagon: @@epsagon_config }

    if @@epsagon_config[:debug]
      configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        OpenTelemetry::Exporter::OTLP::Exporter.new(headers: {
                            'x-epsagon-token' => @@epsagon_config[:token]
                          },
                          endpoint: @@epsagon_config[:backend],
                          insecure: @@epsagon_config[:insecure] || false)
      )

      configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      )
    else
      configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        exporter: OpenTelemetry::Exporter::OTLP::Exporter.new(headers: {
                                                                'x-epsagon-token' => @@epsagon_config[:token]
                                                              },
                                                              endpoint: @@epsagon_config[:backend],
                                                              insecure: @@epsagon_config[:insecure] || false)
      )
    end
  end

end

# monkey patch to include epsagon confs
module OpenTelemetry
  # monkey patch inner SDK module
  module SDK
    def self.configure
      super do |c|
        yield c if block_given?
        Epsagon.epsagon_confs c
      end
    end
  end
end
