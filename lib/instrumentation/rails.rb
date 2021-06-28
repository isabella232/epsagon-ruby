# frozen_string_literal: true

require 'opentelemetry'

require_relative '../util'
require_relative '../epsagon_constants'


class EpsagonRailsInstrumentation < OpenTelemetry::Instrumentation::Base
  install do |_config|
    require_relative 'epsagon_rails_middleware'
    ::ActionController::Metal.prepend(MetalPatch)
  end

  present do
    defined?(::Rails)
  end
end
