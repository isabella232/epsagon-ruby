require 'aws-sdk-core'

# AWS SDK plugin for epsagon instrumentation
class EpsagonAwsPlugin < Seahorse::Client::Plugin
  def add_handlers(handlers, _)
    handlers.add(EpsagonAwsHandler, step: :validate)
  end
end

# Generates Spans for all uses of AWS SDK
class EpsagonAwsHandler < Seahorse::Client::Handler
  def call(context)
    tracer.in_span('') do |span|
      @handler.call(context).tap do
        span.set_attribute('aws.service', context.client.class.to_s.split('::')[1].downcase)
        span.set_attribute('aws.aws.operation', context.operation.name)
        span.set_attribute('aws.region', context.client.config.region)
        span.set_attribute('aws.status_code', context.http_response.status_code)
      end
    end
  end

  def tracer
    EpsagonAwsSdkInstrumentation.instance.tracer
  end
end