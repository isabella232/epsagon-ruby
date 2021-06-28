require 'json'

module EpsagonResqueModule
  def self.prepended(base)
    class << base
      prepend ClassMethods
    end
  end

  # Module to prepend to Resque singleton class
  module ClassMethods
    def push(queue, item)
      epsagon_conf = config[:epsagon] || {}
      # Check if the job is being wrapped by ActiveJob
      # before retrieving the job class name
      job_class = if item[:class] == 'ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper' && item[:args][0]&.is_a?(Hash)
                    item[:args][0]['job_class']
                  else
                    item[:class]
                  end
      attributes = {
        'operation' => 'enqueue',
        'messaging.system' => 'resque',
        'messaging.resque.job_class' => job_class,
        'messaging.destination' => queue.to_s,
        'messaging.destination_kind' => 'queue',
        'messaging.resque.redis_url' => Resque.redis.connection[:id]
      }
      unless epsagon_conf[:metadata_only]
        attributes.merge!({
          'messaging.resque.args' => JSON.dump(item)
        })
      end

      tracer.in_span(queue.to_s, attributes: attributes, kind: :producer) do
        OpenTelemetry.propagation.text.inject(item)
        super
      end
    end

    def tracer
      EpsagonResqueInstrumentation.instance.tracer
    end

    def config
      EpsagonResqueInstrumentation.instance.config
    end
  end
end

module EpsagonResqueJob
  def perform # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    inner_exception = nil
    epsagon_conf = config[:epsagon] || {}
    job_args = args || []

    # Check if the job is being wrapped by ActiveJob
    # before retrieving the job class name
    job_class = if payload_class_name == 'ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper' && job_args[0]&.is_a?(Hash)
                  job_args[0]['job_class']
                else
                  payload_class_name
                end

    attributes = {
        'operation' => 'perform',
        'messaging.system' => 'resque',
        'messaging.resque.job_class' => job_class,
        'messaging.destination' => queue.to_s,
        'messaging.destination_kind' => 'queue',
        'messaging.resque.redis_url' => Resque.redis.connection[:id]
    }
    runner_attributes = {
      'type' => 'resque_worker',
      'messaging.resque.redis_url' => Resque.redis.connection[:id],

    }

    extracted_context = OpenTelemetry.propagation.text.extract(@payload)

    unless epsagon_conf[:metadata_only]
      attributes.merge!({
        'messaging.resque.args' => JSON.dump(args)
      })
    end
    tracer.in_span(
      queue.to_s,
      attributes: attributes,
      with_parent: extracted_context,
      kind: :consumer
    ) do |trigger_span|
      tracer.in_span(job_class,
        attributes: runner_attributes,
        kind: :consumer
      ) do |runner_span|
        super
      end
    rescue Exception => e
      inner_exception = e
    end
    raise inner_exception if inner_exception
  end

  private

  def tracer
    EpsagonResqueInstrumentation.instance.tracer
  end

  def config
    EpsagonResqueInstrumentation.instance.config
  end
end
