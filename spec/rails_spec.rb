# frozen_string_literal: true
require 'rails'
require 'rack/test'
require 'opentelemetry/sdk'
require 'byebug'
require_relative '../lib/instrumentation/rails'
require_relative 'test_helpers/app_config'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

default_rails_app = nil

describe 'Rails Instrumentation' do
  include Rack::Test::Methods

  # let(:instrumentation) { OpenTelemetry::Instrumentation::Rails::Instrumentation.instance }
  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }
  let(:span) { exporter.finished_spans.last }
  let(:rails_app) { default_rails_app }

  # Clear captured spans
  before do
    exporter.reset

    OpenTelemetry::SDK.configure do |c|
      c.use 'EpsagonRailsInstrumentation', { epsagon: {} }
      c.use 'EpsagonRailsInstrumentation', { epsagon: {} }
      c.add_span_processor span_processor
    end

    default_rails_app = AppConfig.initialize_app
    ::Rails.application = default_rails_app
  end

  it 'sets the span name to ControllerName#action' do
    get '/ok'

    expect(last_response.body).to eq 'actually ok'
    expect(last_response.ok?).to eq true
    expect(span.name).to eq 'example.org'
    expect(span.kind).to eq :server
    expect(span.status.ok?).to eq true

    # expect(span.instrumentation_library.name).to eq 'OpenTelemetry::Instrumentation::Rack'
    # expect(span.instrumentation_library.version).to eq OpenTelemetry::Instrumentation::Rack::VERSION

    # expect(span.attributes['http.method']).to eq 'GET'
    # expect(span.attributes['http.host']).to eq 'example.org'
    expect(span.attributes['http.scheme']).to eq 'http'
    # expect(span.attributes['http.target']).to eq '/ok'
    expect(span.attributes['http.status_code']).to eq 200
    expect(span.attributes['http.user_agent']).to eq nil
    expect(span.attributes['http.route']).to eq nil
  end

  it 'sets the span name when the controller raises an exception' do
    get 'internal_server_error'

    expect(span.name).to eq 'example.org'
  end

  it 'does not set the span name when an exception is raised in middleware' do
    get '/ok?raise_in_middleware'

    expect(span.name).to eq 'example.org'
  end

  it 'has the correct span name' do
    get '/ok?redirect_in_middleware'

    expect(span.name).to eq 'example.org'
  end

  describe 'when the application has exceptions_app configured' do
    let(:rails_app) { AppConfig.initialize_app(use_exceptions_app: true) }

    it 'has the correct span name' do
      get 'internal_server_error'

      expect(span.name).to eq 'example.org'
    end
  end

  describe 'when the application has enable_rails_route enabled' do
    # before do
    #   OpenTelemetry::Instrumentation::Rails::Instrumentation.instance.config[:enable_recognize_route] = true
    # end

    # after do
    #   OpenTelemetry::Instrumentation::Rails::Instrumentation.instance.config[:enable_recognize_route] = false
    # end

    it 'sets the span name to ControllerName#action' do
      get '/ok'

      expect(last_response.body).to eq 'actually ok'
      expect(last_response.ok?).to eq true
      expect(span.name).to eq 'example.org'
      expect(span.kind).to eq :server
      expect(span.status.ok?).to eq true

      # expect(span.instrumentation_library.name).to eq 'OpenTelemetry::Instrumentation::Rack'
      # expect(span.instrumentation_library.version).to eq OpenTelemetry::Instrumentation::Rack::VERSION

      # expect(span.attributes['http.method']).to eq 'GET'
      # expect(span.attributes['http.host']).to eq 'example.org'
      expect(span.attributes['http.scheme']).to eq 'http'
      # expect(span.attributes['http.target']).to eq '/ok'
      expect(span.attributes['http.status_code']).to eq 200
      expect(span.attributes['http.user_agent']).to eq nil
      # expect(span.attributes['http.route']).to eq '/ok(.:format)'
    end
  end

  #
  # Not sure if we need this test case because right now we're not installing EpsagonRackInstrumentation
  #
  skip describe 'when the application does not have the tracing rack middleware' do
    let(:rails_app) { AppConfig.initialize_app(remove_rack_tracer_middleware: true) }

    it 'does something' do
      get '/ok'

      expect(last_response.body).to eq 'actually ok'
      expect(last_response.ok?).to eq true
      expect(spans.size).to eq(0)
    end
  end

  def app
    rails_app
  end
end
