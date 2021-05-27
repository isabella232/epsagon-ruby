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
  SPAN_KIND = {
    'ReceiveMessage' => :consumer,
    'SendMessage' => :producer,
    'SendMessageBatch' => :producer,
    'Publish' => :producer,
  }

  def call(context)
    span_name = ''
    span_kind = :client
    attributes = {
      'aws.service' => context.client.class.to_s.split('::')[1].downcase,
      'aws.operation' => context.operation.name
    }  
    attributes['aws.region'] = context.client.config.region unless attributes['aws.service'] == 's3'
    span_kind = SPAN_KIND[attributes['aws.operation']] || span_kind
    if attributes['aws.service'] == 's3'
      attributes['aws.s3.bucket'] = context.params[:bucket]
      span_name = attributes['aws.s3.bucket'] if attributes['aws.s3.bucket']
      attributes['aws.s3.key'] = context.params[:key]
      attributes['aws.s3.copy_source'] = context.params[:copy_source]
    elsif attributes['aws.service'] == 'sqs'
      queue_url = context.params[:queue_url]
      queue_name = queue_url ? queue_url[queue_url.rindex('/')+1..-1] : context.params[:queue_name]
      attributes['aws.sqs.max_number_of_messages'] = context.params[:max_number_of_messages]
      attributes['aws.sqs.wait_time_seconds'] = context.params[:wait_time_seconds]
      attributes['aws.sqs.visibility_timeout'] = context.params[:visibility_timeout]
      if queue_name
        attributes['aws.sqs.queue_name'] = queue_name
        span_name = attributes['aws.sqs.queue_name'] if attributes['aws.sqs.queue_name']
      end
      unless config[:epsagon][:metadata_only]
        if attributes['aws.operation'] == 'SendMessageBatch'
          messages_attributes = context.params[:entries].map do |m|
            record = {
              'message_attributes' => m[:message_attributes].map {|k,v| [k, v.to_h]},
              'message_body' => m[:message_body],
            } 
          end
          attributes['aws.sqs.record'] = JSON.dump(messages_attributes) if messages_attributes
        end
        attributes['aws.sqs.record.message_body'] = context.params[:message_body]
        attributes['aws.sqs.record.message_attributes'] = JSON.dump(context.params[:message_attributes]) if context.params[:message_attributes]
      end
    elsif attributes['aws.service'] == 'sns'
      topic_arn = context.params[:topic_arn]
      topic_name = topic_arn ? topic_arn[topic_arn.rindex(':')+1..-1] : context.params[:name] 
      attributes['aws.sns.topic_name'] = topic_name
      unless config[:epsagon][:metadata_only]
        attributes['aws.sns.subject'] = context.params[:subject]
        attributes['aws.sns.message_attributes'] = JSON.dump(context.params[:message_attributes]) if context.params[:message_attributes]
      end
    end
    tracer.in_span(span_name, kind: span_kind, attributes: attributes) do |span|
      untraced do
        @handler.call(context).tap do |result|
          if attributes['aws.service'] == 's3'
            modified = context.http_response.headers[:'last-modified']
            reformatted_modified = modified ? 
                                  Time.strptime(modified, '%a, %d %b %Y %H:%M:%S %Z')
                                  .strftime('%Y-%m-%dT%H:%M:%SZ') :
                                  nil
            if context.operation.name == 'GetObject'
              span.set_attribute('aws.s3.content_length', context.http_response.headers[:'content-length']&.to_i)
            end
            span.set_attribute('aws.s3.etag', context.http_response.headers[:etag]&.tr('"',''))
            span.set_attribute('aws.s3.last_modified', reformatted_modified)
          elsif attributes['aws.service'] == 'sqs'
            if context.operation.name == 'SendMessage'
              span.set_attribute('aws.sqs.record.message_id', result.message_id)
            end
            if context.operation.name == 'SendMessageBatch'
              messages_attributes = result.successful.map do |m|
                record = {'message_id' => m.message_id}
                unless config[:epsagon][:metadata_only]
                  context.params[:entries].each do |e|
                    record.merge!({
                      'message_attributes' => e[:message_attributes].map {|k,v| [k, v.to_h]},
                      'message_body' => e[:message_body],
                    }) if e[:id] == m.id
                  end
                end
                record
              end
              span.set_attribute('aws.sqs.record', JSON.dump(messages_attributes)) if messages_attributes
            end
            if context.operation.name == 'ReceiveMessage'
              messages_attributes = result.messages.map do |m|
                record = {
                  'message_id' => m.message_id,
                  'attributes' => {
                    'sender_id' => m.attributes['SenderId'],
                    'sent_timestamp' => m.attributes['SentTimestamp'],
                    'aws_trace_header' => m.attributes['AWSTraceHeader'],
                  }
                }
                unless config[:epsagon][:metadata_only]
                  record['message_attributes'] = m.message_attributes.map {|k,v| [k, v.to_h]}
                  record['message_body'] = m.body
                end 
                record
              end
              span.set_attribute('aws.sqs.record', JSON.dump(messages_attributes)) if messages_attributes
            end
          elsif attributes['aws.service'] == 'sns'
            span.set_attribute('aws.sns.message_id', result.message_id) if context.operation.name == 'Publish'
          end
          span.set_attribute('http.status_code', context.http_response.status_code)
        end
      end
    end
  end

  def tracer
    EpsagonAwsSdkInstrumentation.instance.tracer()
  end

  def config
    EpsagonAwsSdkInstrumentation.instance.config
  end
end
