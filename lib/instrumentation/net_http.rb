# frozen_string_literal: true

require 'opentelemetry'

require_relative '../util'
require_relative '../epsagon_constants'

# Net::HTTP patch for epsagon instrumentaton
module EpsagonNetHTTPExtension
  HTTP_METHODS_TO_SPAN_NAMES = Hash.new { |h, k| h[k] = "HTTP #{k}" }
  USE_SSL_TO_SCHEME = { false => 'http', true => 'https' }.freeze

  def config
    EpsagonNetHTTPInstrumentation.instance.config
  end

  def request(req, body = nil, &block)
    # Do not trace recursive call for starting the connection
    return super(req, body, &block) unless started?
    return super(req, body, &block) if config[:epsagon][:ignore_domains].any? {|d| @address.include? d}

    attributes = Hash[OpenTelemetry::Common::HTTP::ClientContext.attributes]
    path_with_params, query = req.path.split('?')
    path, path_params = path_with_params.split(';')

    attributes.merge!({
                        'type' => 'http',
                        'operation' => req.method,
                        'http.scheme' => USE_SSL_TO_SCHEME[use_ssl?],
                        'http.request.path' => URI(path).path
                      })

    unless config[:epsagon][:metadata_only]
      headers = Hash[req.each_header.to_a]
      attributes.merge!({
                          'http.request.path_params' => path_params,
                          'http.request.body' => body,
                          'http.request.headers' => headers.to_json,
                          'http.request.headers.User-Agent' => headers['user-agent']
                        })
      attributes.merge!(Util.epsagon_query_attributes(query))
    end

    tracer.in_span(
      @address,
      attributes: attributes,
      kind: :client
    ) do |span|
      OpenTelemetry.propagation.http.inject(req)

      super(req, body, &block).tap do |response|
        annotate_span_with_response!(span, response)
      end
    end
  end

  private

  def annotate_span_with_response!(span, response)
    return unless response&.code
    return unless span.respond_to?(:set_attribute)

    status_code = response.code.to_i

    span.set_attribute('http.status_code', status_code)
    unless config[:epsagon][:metadata_only]
      span.set_attribute('http.response.headers', Hash[response.each_header.to_a].to_json)
      span.set_attribute('http.response.body', response.body)
    end
    span.status = OpenTelemetry::Trace::Status.http_to_status(
      status_code
    )
  end

  def tracer
    EpsagonNetHTTPInstrumentation.instance.tracer
  end
end

# Net::HTTP epsagon instrumentaton
class EpsagonNetHTTPInstrumentation < OpenTelemetry::Instrumentation::Base
  VERSION = EpsagonConstants::VERSION

  install do |_|
    ::Net::HTTP.prepend(EpsagonNetHTTPExtension)
  end

  present do
    defined?(::Net::HTTP)
  end
end
