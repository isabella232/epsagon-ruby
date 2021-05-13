# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'epsagon'
  s.version     = '0.0.24'
  s.required_ruby_version = '>=2.0.0'
  s.summary     = 'Epsagon provides tracing to Ruby applications for the collection of distributed tracing and performance metrics.'
  s.description = <<-EOS.gsub(/^\s+/, '')
    Epsagon provides tracing to Ruby applications for the collection of distributed tracing and performance metrics to simplify complex architectures, eliminate manual work, visualize and correlate data to identify and fix problems fast.
  EOS
  s.authors     = ['Epsagon']
  s.email       = 'info@epsagon.com'
  s.files       = ::Dir.glob('lib/**/*.rb')
  s.require_paths = ['lib']
  s.homepage = 'https://github.com/epsagon/epsagon-ruby'
  s.license = 'MIT'
  s.add_runtime_dependency  'opentelemetry-api', '~> 0.11.0'
  s.add_runtime_dependency  'opentelemetry-exporter-otlp', '~> 0.11.0'
  s.add_runtime_dependency  'opentelemetry-instrumentation-sinatra', '~> 0.11.0'
  s.add_runtime_dependency  'opentelemetry-instrumentation-sidekiq', '~> 0.11.0'
  s.add_runtime_dependency  'opentelemetry-sdk', '~> 0.11.1'
end
