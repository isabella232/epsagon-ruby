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
require_relative 'instrumentation/postgres'
require_relative 'instrumentation/resque'
require_relative 'util'
require_relative 'epsagon_constants'
require_relative 'exporter_extension'
require_relative 'arn_parser'

Bundler.require


# Epsagon tracing main entry point
module Epsagon
  DEFAULT_BACKEND = 'opentelemetry.tc.epsagon.com:443/traces'
  DEFAULT_IGNORE_DOMAINS = ['newrelic.com'].freeze
  MUTABLE_CONF_KEYS = Set.new([:metadata_only, :max_attribute_size, :ignore_domains, :ignored_keys]) 


  @@epsagon_config = nil

  module_function

  def init(**args)
    get_config.merge!(args)
    validate(get_config)
    OpenTelemetry::SDK.configure
    @@initialized = true
  end

  def validate(config)
    Util.validate_value(config, :metadata_only, 'Must be a boolean') {|v| !!v == v}
    Util.validate_value(config, :debug, 'Must be a boolean') {|v| !!v == v}
    Util.validate_value(config, :token, 'Must be a valid Epsagon token') {|v| v.is_a? String and v.size > 10}
    Util.validate_value(config, :app_name, 'Must be a String') {|v| v.is_a? String}
    Util.validate_value(config, :max_attribute_size, 'Must be an Integer') {|v| v.is_a? Integer}
    Util.validate_value(config, :ignore_domains, 'Must be iterable') {|v| v.respond_to?(:each)}
    Util.validate_value(config, :ignored_keys, 'Must be iterable') {|v| v.respond_to?(:each)}
  end

  def set_config(**args)
    unless args.keys.all? {|a| MUTABLE_CONF_KEYS.include?(a)}
      raise ArgumentError.new("only #{MUTABLE_CONF_KEYS.to_a} are mutable after `Epsagon.init`")
    end
    Epsagon.init unless @@initialized
    new_conf = get_config.merge(args)
    validate(new_conf)
    @@epsagon_config = new_conf
  end

  def add_ignored_key(key)
    get_config[:ignored_keys].push(key).uniq
  end

  def remove_ignored_key(key)
    get_config[:ignored_keys].delete(key)
  end

  def get_config
    @@epsagon_config ||= {
      metadata_only: ENV['EPSAGON_METADATA']&.to_s&.downcase != 'false',
      debug: ENV['EPSAGON_DEBUG']&.to_s&.downcase == 'true',
      token: ENV['EPSAGON_TOKEN'] || '',
      app_name: ENV['EPSAGON_APP_NAME'] || '',
      max_attribute_size: ENV['EPSAGON_MAX_ATTRIBUTE_SIZE'] || 5000,
      backend: ENV['EPSAGON_BACKEND'] || DEFAULT_BACKEND,
      ignore_domains: ENV['EPSAGON_IGNORE_DOMAINS'] || DEFAULT_IGNORE_DOMAINS,
      ignored_keys: ENV['EPSAGON_IGNORED_KEYS'] || []
    }
  end

  def set_ecs_metadata
    metadata_uri = ENV['ECS_CONTAINER_METADATA_URI']
    return {} if metadata_uri.nil?

    response = Net::HTTP.get(URI(metadata_uri))
    ecs_metadata = JSON.parse(response)
    arn = Arn.parse(ecs_metadata['Labels']['com.amazonaws.ecs.task-arn'])

    {
      'aws.account_id' => arn.account,
      'aws.region' => arn.region,
      'aws.ecs.cluster' => ecs_metadata['Labels']['com.amazonaws.ecs.cluster'],
      'aws.ecs.task_arn' => ecs_metadata['Labels']['com.amazonaws.ecs.task-arn'],
      'aws.ecs.container_name' => ecs_metadata['Labels']['com.amazonaws.ecs.container-name'],
      'aws.ecs.task.family' => ecs_metadata['Labels']['com.amazonaws.ecs.task-definition-family'],
      'aws.ecs.task.revision' => ecs_metadata['Labels']['com.amazonaws.ecs.task-definition-version']
    }
  end

  # config opentelemetry with epsaon extensions:

  def epsagon_confs(configurator)
    otel_resource = {
      'application' => get_config[:app_name],
      'epsagon.version' => EpsagonConstants::VERSION,
      'epsagon.metadata_only' => get_config[:metadata_only]
    }.merge(set_ecs_metadata)

    configurator.resource = OpenTelemetry::SDK::Resources::Resource.telemetry_sdk.merge(
      OpenTelemetry::SDK::Resources::Resource.create(otel_resource)
    )

    configurator.use 'EpsagonSinatraInstrumentation', { epsagon: get_config }
    configurator.use 'EpsagonNetHTTPInstrumentation', { epsagon: get_config }
    configurator.use 'EpsagonFaradayInstrumentation', { epsagon: get_config }
    configurator.use 'EpsagonAwsSdkInstrumentation', { epsagon: get_config }
    configurator.use 'EpsagonRailsInstrumentation', { epsagon: get_config }
    configurator.use 'OpenTelemetry::Instrumentation::Sidekiq', { epsagon: get_config }
    configurator.use 'EpsagonPostgresInstrumentation', { epsagon: get_config }
    configurator.use 'EpsagonResqueInstrumentation', { epsagon: get_config }


    if get_config[:debug]
      configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
      )
    end

    configurator.add_span_processor OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      exporter: OpenTelemetry::Exporter::OTLP::Exporter.new(headers: {
                                                              'x-epsagon-token' => get_config[:token]
                                                            },
                                                            endpoint: get_config[:backend],
                                                            insecure: get_config[:insecure] || false)
    )
  end
end


module SpanExtension

  BLANKS = [nil, [], '']

  def set_mapping_attribute(key, value)
    value = Util.prepare_attr(key, value, Epsagon.get_config[:max_attribute_size], Epsagon.get_config[:ignored_keys])
    set_attribute(key, value) if value
  end

  def set_attribute(key, value)
    unless BLANKS.include?(value)
      value = Util.prepare_attr(key, value, Epsagon.get_config[:max_attribute_size], Epsagon.get_config[:ignored_keys])
      super(key, value) if value
    end
  end

  def initialize(*args)
    super(*args)
    if @attributes
      @attributes = Hash[@attributes.select {|k,v| not BLANKS.include? v}.map { |k,v|
        v = Util.prepare_attr(k, v, Epsagon.get_config[:max_attribute_size], Epsagon.get_config[:ignored_keys])
        [k, v] if v
      }.compact]
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
