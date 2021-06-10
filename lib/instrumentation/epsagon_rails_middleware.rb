# frozen_string_literal: true

require 'opentelemetry/trace/status'

module QueueTime
  REQUEST_START = 'HTTP_X_REQUEST_START'
  QUEUE_START = 'HTTP_X_QUEUE_START'
  MINIMUM_ACCEPTABLE_TIME_VALUE = 1_000_000_000

  module_function

  def get_request_start(env, now = nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    header = env[REQUEST_START] || env[QUEUE_START]
    return unless header

    # nginx header is seconds in the format "t=1512379167.574"
    # apache header is microseconds in the format "t=1570633834463123"
    # heroku header is milliseconds in the format "1570634024294"
    time_string = header.to_s.delete('^0-9')
    return if time_string.nil?

    # Return nil if the time is clearly invalid
    time_value = "#{time_string[0, 10]}.#{time_string[10, 6]}".to_f
    return if time_value.zero? || time_value < MINIMUM_ACCEPTABLE_TIME_VALUE

    # return the request_start only if it's lesser than
    # current time, to avoid significant clock skew
    request_start = Time.at(time_value)
    now ||= Time.now.utc
    request_start.utc > now ? nil : request_start
  rescue StandardError => e
    # in case of an Exception we don't create a
    # `request.queuing` span
    OpenTelemetry.logger.debug("[rack] unable to parse request queue headers: #{e}")
    nil
  end
end

class EpsagonRackMiddleware
  class << self
    def allowed_rack_request_headers
      @allowed_rack_request_headers ||= Array(config[:allowed_request_headers]).each_with_object({}) do |header, memo|
        memo["HTTP_#{header.to_s.upcase.gsub(/[-\s]/, '_')}"] = build_attribute_name('http.request.headers.', header)
      end
    end

    def allowed_response_headers
      @allowed_response_headers ||= Array(config[:allowed_response_headers]).each_with_object({}) do |header, memo|
        memo[header] = build_attribute_name('http.response.headers.', header)
        memo[header.to_s.upcase] = build_attribute_name('http.response.headers.', header)
      end
    end

    def build_attribute_name(prefix, suffix)
      prefix + suffix.to_s.downcase.gsub(/[-\s]/, '_')
    end

    def config
      EpsagonRailsInstrumentation.instance.config
    end

    private

    def clear_cached_config
      @allowed_rack_request_headers = nil
      @allowed_response_headers = nil
    end
  end

  EMPTY_HASH = {}.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    original_env = env.dup
    extracted_context = OpenTelemetry.propagation.http.extract(env)
    frontend_context = create_frontend_span(env, extracted_context)

    # restore extracted context in this process:
    OpenTelemetry::Context.with_current(frontend_context || extracted_context) do
      request_span_name = create_request_span_name(env['REQUEST_URI'] || original_env['PATH_INFO'])
      tracer.in_span(env['HTTP_HOST'] || 'unknown',
                     attributes: request_span_attributes(env: env),
                     kind: :server) do |http_span|
        RackExtension.with_span(http_span) do
          tracer.in_span(
              env['HTTP_HOST'],
              kind: :server,
              attributes: {type: 'rails'}
            ) do |framework_span|
            @app.call(env).tap do |status, headers, response|
              set_attributes_after_request(http_span, framework_span, status, headers, response)
            end
          end
        end
      end
    end
  ensure
    finish_span(frontend_context)
  end

  private

  # return Context with the frontend span as the current span
  def create_frontend_span(env, extracted_context)
    request_start_time = QueueTime.get_request_start(env)

    return unless config[:record_frontend_span] && !request_start_time.nil?

    span = tracer.start_span('http_server.proxy',
                             with_parent: extracted_context,
                             attributes: {
                               'start_time' => request_start_time.to_f
                             },
                             kind: :server)

    OpenTelemetry::Trace.context_with_span(span, parent_context: extracted_context)
  end

  def finish_span(context)
    OpenTelemetry::Trace.current_span(context).finish if context
  end

  def tracer
    EpsagonRailsInstrumentation.instance.tracer
  end

  def request_span_attributes(env:)
    request = Rack::Request.new(env)
    path, path_params = request.path.split(';')
    request_headers = JSON.generate(Hash[*env.select { |k, _v| k.to_s.start_with? 'HTTP_' }
      .collect { |k, v| [k.sub(/^HTTP_/, ''), v] }
      .collect { |k, v| [k.split('_').collect(&:capitalize).join('-'), v] }
      .sort
      .flatten])

    attributes = {
      'operation' => env['REQUEST_METHOD'],
      'type' => 'http',
      'http.scheme' => env['rack.url_scheme'],
      'http.request.path' => path,
      'http.request.headers' => request_headers
    }

    unless config[:epsagon][:metadata_only]
      request.body.rewind
      request_body = request.body.read
      request.body.rewind

      attributes.merge!(Util.epsagon_query_attributes(request.query_string))

      attributes.merge!({
                          'http.request.body' => request_body,
                          'http.request.path_params' => path_params,
                          'http.request.headers.User-Agent' => env['HTTP_USER_AGENT']
                        })
    end

    attributes
  end

  # e.g., "/webshop/articles/4?s=1":
  def fullpath(env)
    query_string = env['QUERY_STRING']
    path = env['SCRIPT_NAME'] + env['PATH_INFO']

    query_string.empty? ? path : "#{path}?#{query_string}"
  end

  # https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/data-http.md#name
  #
  # recommendation: span.name(s) should be low-cardinality (e.g.,
  # strip off query param value, keep param name)
  #
  # see http://github.com/open-telemetry/opentelemetry-specification/pull/416/files
  def create_request_span_name(request_uri_or_path_info)
    # NOTE: dd-trace-rb has implemented 'quantization' (which lowers url cardinality)
    #       see Datadog::Quantization::HTTP.url

    if (implementation = config[:url_quantization])
      implementation.call(request_uri_or_path_info)
    else
      request_uri_or_path_info
    end
  end

  def set_attributes_after_request(http_span, _framework_span, status, headers, response)
    unless config[:epsagon][:metadata_only]
      http_span.set_attribute('http.response.headers', JSON.generate(headers))
      http_span.set_attribute('http.response.body', response.join) if response.respond_to?(:join)
    end

    http_span.set_attribute('http.status_code', status)
    http_span.status = OpenTelemetry::Trace::Status.http_to_status(status)
  end

  def allowed_request_headers(env)
    return EMPTY_HASH if self.class.allowed_rack_request_headers.empty?

    {}.tap do |result|
      self.class.allowed_rack_request_headers.each do |key, value|
        result[value] = env[key] if env.key?(key)
      end
    end
  end

  def allowed_response_headers(headers)
    return EMPTY_HASH if headers.nil?
    return EMPTY_HASH if self.class.allowed_response_headers.empty?

    {}.tap do |result|
      self.class.allowed_response_headers.each do |key, value|
        if headers.key?(key)
          result[value] = headers[key]
        else
          # do case-insensitive match:
          headers.each do |k, v|
            if k.upcase == key
              result[value] = v
              break
            end
          end
        end
      end
    end
  end

  def config
    EpsagonRailsInstrumentation.instance.config
  end
end

# class EpsagonRackInstrumentation < OpenTelemetry::Instrumentation::Base
#   install do |config|
#     require_dependencies

#     retain_middleware_names if config[:retain_middleware_names]
#   end

#   present do
#     defined?(::Rack)
#   end

#   private

#   def require_dependencies
#     require_relative 'middlewares/tracer_middleware'
#   end

#   MissingApplicationError = Class.new(StandardError)

#   # intercept all middleware-compatible calls, retain class name
#   def retain_middleware_names
#     next_middleware = config[:application]
#     raise MissingApplicationError unless next_middleware

#     while next_middleware
#       if next_middleware.respond_to?(:call)
#         next_middleware.singleton_class.class_eval do
#           alias_method :__call, :call

#           def call(env)
#             env['RESPONSE_MIDDLEWARE'] = self.class.to_s
#             __call(env)
#           end
#         end
#       end

#       next_middleware = next_middleware.instance_variable_defined?('@app') &&
#                         next_middleware.instance_variable_get('@app')
#     end
#   end
# end

class EpsagonRailtie < ::Rails::Railtie
  config.before_initialize do |app|
    # EpsagonRackInstrumentation.instance.install({})

    app.middleware.insert_after(
      ActionDispatch::RequestId,
      EpsagonRackMiddleware
    )
  end
end
