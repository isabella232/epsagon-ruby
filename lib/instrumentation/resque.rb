class EpsagonResqueInstrumentation < OpenTelemetry::Instrumentation::Base
  install do |_config|
    require_dependencies
    patch
  end

  present do
    defined?(::Resque)
  end

  private

  def patch
    ::Resque.prepend(EpsagonResqueModule)
    ::Resque::Job.prepend(EpsagonResqueJob)
  end

  def require_dependencies
    require_relative 'epsagon_resque_job'
  end
end
