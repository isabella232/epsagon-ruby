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

# Epsagon tracing main entry point
module Epsagon
  module_function

  def init(**args)
    defaults = {
      metadata_only: ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false',
      debug: ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true',
      token: ENV['EPSAGON_TOKEN'],
      app_name: ENV['EPSAGON_APP_NAME'],
      backend: ENV['EPSAGON_BACKEND'] || 'localhost:55681/v1/trace'
    }
    @@epsagon_config = defaults.merge(args)
  end

  def metadata_only?
    ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false'
  end

  def debug?
    ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true'
  end

  # config opentelemetry with epsaon extensions:

  def epsagon_confs(configurator)
    configurator.resource = OpenTelemetry::SDK::Resources::Resource.telemetry_sdk.merge(
      OpenTelemetry::SDK::Resources::Resource.create({ 'epasgon_app_name' => ENV['EPSAGON_APP_NAME'] })
    )
    configurator.use 'EpsagonSinatraInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonNetHTTPInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonFaradayInstrumentation', { epsagon: @@epsagon_config }
    # if ENV['EPSAGON_BACKEND']
    configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(headers: {
                                                    'x-epasgon-token' => @@epsagon_config[:token]
                                                  },
                                                  endpoint: @@epsagon_config[:backend],
                                                  insecure: @@epsagon_config[:insecure] || false)
    )
    return unless debug?

    configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  end

  OpenTelemetry::SDK.configure
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
