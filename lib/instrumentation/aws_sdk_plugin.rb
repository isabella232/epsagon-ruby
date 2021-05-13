# frozen_string_literal: true

require 'aws-sdk-core'
require 'opentelemetry/common'
require 'opentelemetry/sdk'

def untraced(&block)
  OpenTelemetry::Trace.with_span(OpenTelemetry::Trace::Span.new, &block)
end

# AWS SDK plugin for epsagon instrumentation
class EpsagonAwsPlugin < Seahorse::Client::Plugin
  def add_handlers(handlers, _)
    handlers.add(EpsagonAwsHandler, step: :validate)
  end
end

# Generates Spans for all uses of AWS SDK
class EpsagonAwsHandler < Seahorse::Client::Handler
  def call(context)
    attributes = {
      'aws.service' => context.client.class.to_s.split('::')[1].downcase,
      'aws.operation' => context.operation.name
    }  
    attributes['aws.region'] = context.client.config.region unless attributes['aws.service'] == 's3'
    if attributes['aws.service'] == 's3'
      attributes['aws.s3.bucket'] = context.params[:bucket]
      attributes['aws.s3.key'] = context.params[:key]
      attributes['aws.s3.copy_source'] = context.params[:copy_source]
    end
    tracer.in_span('', kind: :client, attributes: attributes) do |span|
      untraced do
        @handler.call(context).tap do
          if attributes['aws.service'] == 's3'
            modified = context.http_response.headers[:'last-modified']
            reformated_modified = modified ? 
                                  Time.strptime(modified, '%a, %d %b %Y %H:%M:%S %Z')
                                  .strftime('%Y-%m-%dT%H:%M:%SZ') :
                                  nil
            span.set_attribute('http.status_code', context.http_response.status_code)
            span.set_attribute('aws.s3.content_length', context.http_response.headers[:'content-length']&.to_i)
            span.set_attribute('aws.s3.etag', context.http_response.headers[:etag])
            span.set_attribute('aws.s3.last_modified', reformated_modified)
          end
        end
      end
    end
  end

  def tracer
    EpsagonAwsSdkInstrumentation.instance.tracer()
  end
end
