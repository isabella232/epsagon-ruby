# frozen_string_literal: true

require 'opentelemetry'
require 'rails'
require 'action_controller/railtie'

require_relative '../util'
require_relative '../epsagon_constants'


module RackExtension
  module_function

  CURRENT_SPAN_KEY = OpenTelemetry::Context.create_key('current-span')

  private_constant :CURRENT_SPAN_KEY

  # Returns the current span from the current or provided context
  #
  # @param [optional Context] context The context to lookup the current
  #   {Span} from. Defaults to Context.current
  def current_span(context = nil)
    context ||= OpenTelemetry::Context.current
    context.value(CURRENT_SPAN_KEY) || OpenTelemetry::Trace::Span::INVALID
  end

  # Returns a context containing the span, derived from the optional parent
  # context, or the current context if one was not provided.
  #
  # @param [optional Context] context The context to use as the parent for
  #   the returned context
  def context_with_span(span, parent_context: OpenTelemetry::Context.current)
    parent_context.set_value(CURRENT_SPAN_KEY, span)
  end

  # Activates/deactivates the Span within the current Context, which makes the "current span"
  # available implicitly.
  #
  # On exit, the Span that was active before calling this method will be reactivated.
  #
  # @param [Span] span the span to activate
  # @yield [span, context] yields span and a context containing the span to the block.
  def with_span(span)
    OpenTelemetry::Context.with_value(CURRENT_SPAN_KEY, span) { |c, s| yield s, c }
  end
end

module MetalPatch
  def dispatch(name, request, response)
    rack_span = RackExtension.current_span
    # rack_span.name = "#{self.class.name}##{name}" if rack_span.context.valid? && !request.env['action_dispatch.exception']
    super(name, request, response)
  end
end

class EpsagonRailsInstrumentation < OpenTelemetry::Instrumentation::Base
  install do |_config|
    require_relative 'epsagon_rails_middleware'
    ::ActionController::Metal.prepend(MetalPatch)
  end

  present do
    defined?(::Rails)
  end
end
