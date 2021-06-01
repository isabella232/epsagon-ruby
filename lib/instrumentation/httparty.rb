require 'opentelemetry'
require 'httparty'
require_relative '../epsagon_constants'
require_relative '../util'

module EpsagonHTTPartyExtension
  USE_SSL_TO_SCHEME = { false => 'http', true => 'https' }.freeze
  SUPPORTED_HTTP_METHODS = {
    'Net::HTTP::Get' => 'GET',
    'Net::HTTP::Post' => 'POST',
    'Net::HTTP::Patch' => 'PATCH',
    'Net::HTTP::Put' => 'PUT',
    'Net::HTTP::Delete' => 'DELETE'
  }.freeze

  def config
    EpsagonHTTPartyInstrumentation.instance.config
  end

  def perform(&block)
    path_with_params, query_with_params = path.to_s.split('?')
    path, path_params = path_with_params.split(';')
    use_ssl = path.start_with?('https://')
    span_name = URI.parse(path).host.downcase
    method = SUPPORTED_HTTP_METHODS[http_method.to_s]

    attributes = Hash[OpenTelemetry::Common::HTTP::ClientContext.attributes].merge(
      {
        'type' => 'http',
        'http.request.query' => query_with_params,
        'operation' => method,
        'http.scheme' => USE_SSL_TO_SCHEME[use_ssl],
        'http.request.path' => path
      }
    )

    options[:headers] = {} if options[:headers].nil?
    final_attribute_set = attributes.merge(add_metadata_attributes(path_params, query_with_params))

    tracer.in_span(
      span_name,
      attributes: final_attribute_set,
      kind: :client
    ) do |span|
      OpenTelemetry.propagation.http.inject(options[:headers])
      super(&block).tap do |response|
        annotate_span_with_response!(span, response)
      end
    end
  end

  private

  def add_metadata_attributes(path_params, query_with_params)
    return {} if config[:epsagon][:metadata_only]

    headers = options[:headers]
    body = options[:body]
    Util.epsagon_query_attributes(query_with_params).merge(
      {
        'http.request.path_params' => path_params,
        'http.request.headers' => headers.to_json,
        'http.request.headers.User-Agent' => headers['user-agent'],
        'http.request.body' => body
      }
    )
  end

  def annotate_span_with_response!(span, response)
    return unless response&.code

    status_code = response.code.to_i
    span.set_attribute('http.status_code', status_code)

    unless config[:epsagon][:metadata_only]
      span.set_attribute('http.response.headers', Hash[response.each_header.to_a].to_json)
      span.set_attribute('http.response.body', response.body.to_s)
    end
    span.status = OpenTelemetry::Trace::Status.http_to_status(
      status_code
    )
  end

  def tracer
    EpsagonHTTPartyInstrumentation.instance.tracer
  end
end

# HTTParty epsagon instrumentaton
class EpsagonHTTPartyInstrumentation < OpenTelemetry::Instrumentation::Base
  VERSION = ::EpsagonConstants::VERSION

  install do |_|
    ::HTTParty::Request.send(:prepend, EpsagonHTTPartyExtension)
  end

  present do
    defined?(::HTTParty::Request)
  end
end
