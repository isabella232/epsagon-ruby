# frozen_string_literal: true
require 'json'
require 'rubygems'
require 'net/http'
require 'bundler/setup'
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/sidekiq'

require_relative 'instrumentation/sinatra'
require_relative 'instrumentation/net_http'
require_relative 'instrumentation/faraday'
require_relative 'instrumentation/aws_sdk'
require_relative 'instrumentation/rails'
require_relative 'util'
require_relative 'epsagon_constants'
require_relative 'exporter_extension'

Bundler.require

# Epsagon tracing main entry point
module Epsagon
  DEFAULT_BACKEND = 'opentelemetry.tc.epsagon.com:443/traces'
  DEFAULT_IGNORE_DOMAINS = ['newrelic.com']

  @@epsagon_config = {}

  module_function

  def init(**args)
    @@epsagon_config = {
      metadata_only: ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false',
      debug: ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true',
      token: ENV['EPSAGON_TOKEN'] || '',
      app_name: ENV['EPSAGON_APP_NAME'] || '',
      max_attribute_size: ENV['EPSAGON_MAX_ATTRIBUTE_SIZE'] || 5000,
      backend: ENV['EPSAGON_BACKEND'] || DEFAULT_BACKEND,
      ignore_domains: ENV['EPSAGON_IGNORE_DOMAINS'] || DEFAULT_IGNORE_DOMAINS
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
        'epsagon.version' => EpsagonConstants::VERSION,
        'epsagon.metadata_only' => @@epsagon_config[:metadata_only]
      })
    )
    configurator.use 'EpsagonSinatraInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonNetHTTPInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonFaradayInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonAwsSdkInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'EpsagonRailsInstrumentation', { epsagon: @@epsagon_config }
    configurator.use 'OpenTelemetry::Instrumentation::Sidekiq', { epsagon: @@epsagon_config }

    if @@epsagon_config[:debug]
      configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      )
    end
    
    configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      exporter: OpenTelemetry::Exporter::OTLP::Exporter.new(headers: {
                                                              'x-epsagon-token' => @@epsagon_config[:token]
                                                            },
                                                            endpoint: @@epsagon_config[:backend],
                                                            insecure: @@epsagon_config[:insecure] || false)
    )
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
      @attributes = Hash[@attributes.select {|k,v| not BLANKS.include? v}.map { |k,v|
        [k, Util.trim_attr(v, Epsagon.get_config[:max_attribute_size])]
      }]
    end
  end
end

module SidekiqClientMiddlewareExtension
  def call(_worker_class, job, _queue, _redis_pool)
    config = OpenTelemetry::Instrumentation::Sidekiq::Instrumentation.instance.config[:epsagon] || {}
    attributes = {
      'operation' => job['at'] ? 'perform_at' : 'perform_async',
      'messaging.system' => 'sidekiq',
      'messaging.sidekiq.job_class' => job['wrapped']&.to_s || job['class'],
      'messaging.message_id' => job['jid'],
      'messaging.destination' => job['queue'],
      'messaging.destination_kind' => 'queue',
      'messaging.sidekiq.redis_url' => Sidekiq.options['url'] || Util.redis_default_url
    }
    unless config[:metadata_only]
      attributes.merge!({
        'messaging.sidekiq.args' => JSON.dump(job['args'])
      })
    end
    tracer.in_span(
      job['queue'],
      attributes: attributes,
      kind: :producer
    ) do |span|
      OpenTelemetry.propagation.text.inject(job)
      span.add_event('created_at', timestamp: job['created_at'])
      Util.untraced {yield}
    end
  end
end

module SidekiqServerMiddlewareExtension
  def call(_worker, msg, _queue)
    inner_exception = nil
    config = OpenTelemetry::Instrumentation::Sidekiq::Instrumentation.instance.config[:epsagon] || {}
    parent_context = OpenTelemetry.propagation.text.extract(msg)
    attributes = {
        'operation' => 'perform',
        'messaging.system' => 'sidekiq',
        'messaging.sidekiq.job_class' => msg['wrapped']&.to_s || msg['class'],
        'messaging.message_id' => msg['jid'],
        'messaging.destination' => msg['queue'],
        'messaging.destination_kind' => 'queue',
        'messaging.sidekiq.redis_url' => Sidekiq.options['url'] || Util.redis_default_url
    }
    runner_attributes = {
      'type' => 'sidekiq_worker',
      'messaging.sidekiq.redis_url' => Sidekiq.options['url'] || Util.redis_default_url,

    }
    unless config[:metadata_only]
      attributes.merge!({
        'messaging.sidekiq.args' => JSON.dump(msg['args'])
      })
    end
    tracer.in_span(
      msg['queue'],
      attributes: attributes,
      with_parent: parent_context,
      kind: :consumer
    ) do |trigger_span|
      trigger_span.add_event('created_at', timestamp: msg['created_at'])
      trigger_span.add_event('enqueued_at', timestamp: msg['enqueued_at'])
      tracer.in_span(msg['wrapped']&.to_s || msg['class'],
        attributes: runner_attributes,
        kind: :consumer
      ) do |runner_span|
        yield
      end
    rescue Exception => e
      inner_exception = e
    end
    raise inner_exception if inner_exception
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
  module Instrumentation
    module Sidekiq
      class Instrumentation
        def add_server_middleware
          ::Sidekiq.configure_server do |config|
            config.server_middleware do |chain|
              chain.add Middlewares::Server::TracerMiddleware
            end
          end

          if defined?(::Sidekiq::Testing) # rubocop:disable Style/GuardClause
            ::Sidekiq::Testing.server_middleware do |chain|
              chain.add Middlewares::Server::TracerMiddleware
            end
          end
        end
      end
      module Middlewares
        module Client
          class TracerMiddleware
            prepend SidekiqClientMiddlewareExtension
          end
        end
        module Server
          class TracerMiddleware
            prepend SidekiqServerMiddlewareExtension
          end
        end
      end
    end
  end
end
