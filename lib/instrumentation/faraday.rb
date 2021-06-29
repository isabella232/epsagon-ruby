# frozen_string_literal: true
require_relative '../epsagon_constants'
# Patch faraday to include middleware
module EpsagonFaradayPatch
  def adapter(*args)
    use(:epsagon_open_telemetry) unless @handlers.any? do |handler|
      handler.klass == EpsagonFaradayMiddleware
    end

    super
  end
end

# Faraday epsagon instrumentaton
class EpsagonFaradayInstrumentation < OpenTelemetry::Instrumentation::Base
  VERSION = EpsagonConstants::VERSION

  install do |_config|
    require_relative 'epsagon_faraday_middleware'
    ::Faraday::Middleware.register_middleware(
      epsagon_open_telemetry: EpsagonFaradayMiddleware
    )
    ::Faraday::RackBuilder.include(EpsagonFaradayPatch)
  end

  present do
    defined?(::Faraday)
  end
end
