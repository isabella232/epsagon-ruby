# frozen_string_literal: true

require_relative '../util'
require_relative '../epsagon_constants'

require 'faraday'

# Faraday middleware for epsagon instrumentaton
class EpsagonFaradayMiddleware < ::Faraday::Middleware
  def config
    EpsagonFaradayInstrumentation.instance.config
  end

  HTTP_METHODS_SYMBOL_TO_STRING = {
    connect: 'CONNECT',
    delete: 'DELETE',
    get: 'GET',
    head: 'HEAD',
    options: 'OPTIONS',
    patch: 'PATCH',
    post: 'POST',
    put: 'PUT',
    trace: 'TRACE'
  }.freeze

  def call(env)
    http_method = HTTP_METHODS_SYMBOL_TO_STRING[env.method]
    path, path_params = env.url.path.split(';')

    attributes = {
      'type' => 'http',
      'operation' => http_method,
      'http.scheme' => env.url.scheme,
      'http.request.path' => path
    }

    unless config[:epsagon][:metadata_only]
      attributes.merge!(Util.epsagon_query_attributes(env.url.query))
      attributes.merge!({
        'http.request.path_params' => path_params,
        'http.request.headers' => Hash[env.request_headers],
        'http.request.body' => env.body,
        'http.request.headers.User-Agent' => env.request_headers['User-Agent']
      })
    end

    tracer.in_span(
      env.url.host,
      attributes: attributes,
      kind: :client
    ) do |span|
      OpenTelemetry.propagation.http.inject(env.request_headers)

      app.call(env).on_complete { |req| trace_response(span, req.response) }
    end
  end

  private

  attr_reader :app

  def tracer
    EpsagonFaradayInstrumentation.instance.tracer
  end

  def trace_response(span, response)
    span.set_attribute('http.status_code', response.status)

    unless config[:epsagon][:metadata_only]
      span.set_attribute('http.response.headers', Hash[env.response.headers])
      span.set_attribute('http.response.body', response.body)
    end
    span.status = OpenTelemetry::Trace::Status.http_to_status(
      response.status
    )
  end
end
