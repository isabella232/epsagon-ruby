require 'opentelemetry'
require 'httparty'

module EpsagonHTTPartyExtension
  USE_SSL_TO_SCHEME = { false => 'http', true => 'https' }.freeze

  def config
    EpsagonHTTPartyInstrumentation.instance.config
  end

  def perform(&block)
    # return super(&block) unless @started

    @started = true
    attributes = Hash[OpenTelemetry::Common::HTTP::ClientContext.attributes]
    path_with_params, query = path.to_s.split('?')
    path, path_params = path_with_params.split(';')
    use_ssl = path.start_with?('https://')

    attributes.merge!({
                        'type' => 'http',
                        'http.method' => http_method,
                        'http.scheme' => USE_SSL_TO_SCHEME[use_ssl],
                        'http.request.path' => path
                      })
    options[:headers] = {} unless options.respond_to?(:headers)
    unless config[:epsagon][:metadata_only]
      headers = options[:headers]
      attributes.merge!({
                          'http.request.path_params' => path_params,
                          # 'http.request.body' => body
                          'http.request.headers' => headers.to_json,
                          # 'http.request.headers.User-Agent' => headers['user-agent']
                        })
      attributes.merge!(Util.epsagon_query_attributes(query))
    end

    tracer.in_span(
      path,
      attributes: attributes,
      kind: :client
    ) do |span|
      OpenTelemetry.propagation.http.inject(options[:headers])
      super(&block).tap do |response|
        annotate_span_with_response!(span, response)
      end
    end
  end

  private

  def annotate_span_with_response!(span, response)
    return unless response&.code

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
    EpsagonHTTPartyInstrumentation.instance.tracer
  end
end

# HTTParty epsagon instrumentaton
class EpsagonHTTPartyInstrumentation < OpenTelemetry::Instrumentation::Base
  VERSION = EpsagonConstants::VERSION

  install do |_|
    ::HTTParty::Request.send(:prepend, EpsagonHTTPartyExtension)
  end

  present do
    defined?(::HTTParty::Request)
  end
end
