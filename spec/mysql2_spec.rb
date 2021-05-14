# frozen_string_literal: true

require 'mysql2'
require 'epsagon'
require 'opentelemetry/sdk'
require 'climate_control'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

#
# These tests require a local MySQL Database to test against
# Use this command to start a local instance:
# docker run --name mysql --rm -p 3306:3306 -e MYSQL_ROOT_HOST=% -e MYSQL_ROOT_PASSWORD=root -d mysql/mysql-server:8.0.25
#
describe 'EpsagonMySql2Instrumentation' do
  let(:exporter)          { EXPORTER }
  let(:span)              { exporter.finished_spans.first }
  let(:epsagon_token)     { 'abcd' }
  let(:epsagon_app_name)  { 'example_app' }

  before do
    ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                          EPSAGON_APP_NAME: epsagon_app_name do
      OpenTelemetry::SDK.configure do |c|
        c.add_span_processor span_processor
      end
    end

    Epsagon.init
    exporter.reset
  end

  describe 'tracing' do
    let(:client) do
      ::Mysql2::Client.new(
        host: host,
        port: port,
        database: database,
        username: 'root',
        password: password
      )
    end

    let(:host) { ENV.fetch('TEST_MYSQL_HOST', '127.0.0.1') }
    let(:port) { ENV.fetch('TEST_MYSQL_PORT', '3306') }
    let(:database) { ENV.fetch('TEST_MYSQL_DB', 'mysql') }
    let(:username) { ENV.fetch('TEST_MYSQL_USER', 'root') }
    let(:password) { ENV.fetch('TEST_MYSQL_PASSWORD', 'root') }

    it "doesn't have spans before request" do
      expect(exporter.finished_spans.size).to eq 0
    end

    describe 'after requests' do
      before do
        client.query('SELECT 1')
      end

      it 'has the correct span name' do
        expect(span.name).to eq host
      end

      it 'has the correct db system' do
        expect(span.attributes['db.system']).to eq 'mysql'
      end

      it 'has the correct db name' do
        expect(span.attributes['db.name']).to eq 'mysql'
      end

      it 'has the correct db statement' do
        expect(span.attributes['db.statement']).to eq 'SELECT ?'
      end

      it 'has the correct peer name' do
        expect(span.attributes['net.peer.name']).to eq host.to_s
      end

      it 'has the correct port' do
        expect(span.attributes['net.peer.port']).to eq port.to_s
      end
    end

    it 'after error' do
      expect do
        client.query('SELECT INVALID')
      end.to raise_error(Mysql2::Error)

      expect(span.name).to eq host
      expect(span.attributes['db.system']).to eq 'mysql'
      expect(span.attributes['db.name']).to eq 'mysql'
      expect(span.attributes['db.statement']).to eq 'SELECT INVALID'
      expect(span.attributes['net.peer.name']).to eq host.to_s
      expect(span.attributes['net.peer.port']).to eq port.to_s

      expect(span.status.code).to eq(
        OpenTelemetry::Trace::Status::ERROR
      )
      expect(span.events.first.name).to eq 'exception'
      expect(span.events.first.attributes['exception.type']).to eq 'Mysql2::Error'
      expect(!span.events.first.attributes['exception.message'].nil?).to be true
      expect(!span.events.first.attributes['exception.stacktrace'].nil?).to be true
    end

    it 'extracts statement type that begins the query' do
      base_sql = 'SELECT 1'
      explain = 'EXPLAIN'
      explain_sql = "#{explain} #{base_sql}"
      client.query(explain_sql)

      expect(span.name).to eq host
      expect(span.attributes['db.system']).to eq 'mysql'
      expect(span.attributes['db.name']).to eq 'mysql'
      expect(span.attributes['db.statement']).to eq "EXPLAIN SELECT ?"
      expect(span.attributes['net.peer.name']).to eq host.to_s
      expect(span.attributes['net.peer.port']).to eq port.to_s
    end

    it 'uses component.name and instance.name as span.name fallbacks with invalid sql' do
      expect do
        client.query('DESELECT 1')
      end.to raise_error(Mysql2::Error)

      expect(span.name).to eq host
      expect(span.attributes['db.system']).to eq 'mysql'
      expect(span.attributes['db.name']).to eq 'mysql'
      expect(span.attributes['db.statement']).to eq 'DESELECT ?'
      expect(span.attributes['net.peer.name']).to eq host.to_s
      expect(span.attributes['net.peer.port']).to eq port.to_s

      expect(span.status.code).to eq(
        OpenTelemetry::Trace::Status::ERROR
      )
      expect(span.events.first.name).to eq 'exception'
      expect(span.events.first.attributes['exception.type']).to eq 'Mysql2::Error'
      expect(!span.events.first.attributes['exception.message'].nil?).to be true
      expect(!span.events.first.attributes['exception.stacktrace'].nil?).to be true
    end
  end
end
