# frozen_string_literal: true

require 'rubygems'
require 'net/http'
require 'bundler/setup'
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

require_relative 'instrumentation/sinatra'
require_relative 'instrumentation/net_http'
require_relative 'instrumentation/faraday'
require_relative 'instrumentation/aws_sdk'
require_relative 'instrumentation/rails'
require_relative 'util'
require_relative 'epsagon_constants'

Bundler.require

# Epsagon tracing main entry point
module Epsagon
  DEFAULT_BACKEND = 'opentelemetry.tc.epsagon.com:443/traces'

  @@epsagon_config = {}

  module_function

  def init(**args)
    @@epsagon_config = {
      metadata_only: ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false',
      debug: ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true',
      token: ENV['EPSAGON_TOKEN'] || '',
      app_name: ENV['EPSAGON_APP_NAME'] || '',
      max_attribute_size: ENV['EPSAGON_MAX_ATTRIBUTE_SIZE'] || 5000,
      backend: ENV['EPSAGON_BACKEND'] || DEFAULT_BACKEND
    }
    @@epsagon_config.merge!(args)
    OpenTelemetry::SDK.configure
  end

  def get_config
    @@epsagon_config
  end

  # config opentelemetry with epsaon extensions:

  def epsagon_confs(configurator)
    configurator.resource = OpenTelemetry::SDK::Resources::Resource.telemetry_sdk.merge(
      OpenTelemetry::SDK::Resources::Resource.create({
        'application' => @@epsagon_config[:app_name],
        'epsagon.version' => EpsagonConstants::VERSION
      })
    )
    configurator.use 'EpsagonSinatraInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonNetHTTPInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonFaradayInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonAwsSdkInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonRailsInstrumentation', { epsagon: @@epsagon_config }

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


module SpanExtension

  BLANKS = [nil, [], '']

  def set_attribute(key, value)
    unless BLANKS.include?(value)
      value = Util.trim_attr(value, Epsagon.get_config[:max_attribute_size])
      super(key, value)
    end
  end

  def initialize(*args)
    super(*args)
    if @attributes
      @attributes = Hash[@attributes.map { |k,v|
        [k, Util.trim_attr(v, Epsagon.get_config[:max_attribute_size])]
      }]
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

    module Trace
      class Span
        prepend SpanExtension
      end
    end
  end
end
