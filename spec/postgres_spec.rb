# frozen_string_literal: true

require 'pg'
require 'epsagon'
require 'opentelemetry/sdk'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

describe 'EpsagonPostgresInstrumentation' do
  let(:instrumentation)   { EpsagonPostgresInstrumentation.instance }
  let(:exporter)          { EXPORTER }
  let(:span)              { exporter.finished_spans.first }
  let(:last_span)         { exporter.finished_spans.last }
  let(:epsagon_token)     { 'abcd' }
  let(:epsagon_app_name)  { 'example_app' }
  let(:config)            { {} }

  around do |example|
    ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                          EPSAGON_APP_NAME: epsagon_app_name do
      example.run
    end
  end

  before do
    Epsagon.init
    ClimateControl.modify EPSAGON_APP_NAME: epsagon_app_name do
      OpenTelemetry::SDK.configure do |c|
        c.add_span_processor span_processor
      end
    end
    exporter.reset
  end

  after do
    # Force re-install of instrumentation
    instrumentation.instance_variable_set(:@installed, false)
  end

  describe 'tracing' do
    let(:client) do
      ::PG::Connection.open(
        host: host,
        port: port,
        user: user,
        dbname: dbname,
        password: password
      )
    end

    let(:host) { ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1') }
    let(:port) { ENV.fetch('TEST_POSTGRES_PORT', '5432') }
    let(:user) { ENV.fetch('TEST_POSTGRES_USER', 'postgres') }
    let(:dbname) { ENV.fetch('TEST_POSTGRES_DB', 'postgres') }
    let(:password) { ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres') }

    # before do
    #   instrumentation.install(config)
    # end

    it 'before request' do
      expect(exporter.finished_spans.size).to eq 0
    end

    %i[exec query sync_exec async_exec].each do |method|
      it "after request (with method: #{method})" do
        client.send(method, 'SELECT 1')
        expect(span.name).to eq 'SELECT postgres'
        expect(span.attributes['db.system']).to eq 'postgresql'
        expect(span.attributes['db.name']).to eq 'postgres'
        expect(span.attributes['db.statement']).to eq 'SELECT 1'
        expect(span.attributes['db.operation']).to eq 'SELECT'
        expect(span.attributes['net.peer.name']).to eq host.to_s
        expect(span.attributes['net.peer.port']).to eq port.to_s
      end
    end
  end
end
