# frozen_string_literal: true

require 'pg'
require 'opentelemetry/sdk'
require_relative '../lib/instrumentation/postgres'
require 'byebug'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

host = ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1')
port = ENV.fetch('TEST_POSTGRES_PORT', '5432')
user = ENV.fetch('TEST_POSTGRES_USER', 'postgres')
dbname = ENV.fetch('TEST_POSTGRES_DB', 'postgres')
password = ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres')

RSpec.shared_examples 'sending correct postgres spans' do |options|
  %i[exec query sync_exec async_exec].each do |method|
    let(:statement) { 'SELECT * FROM Traces;' }
    it "after request (with method: #{method})" do
      client.send(method, statement)

      expect(span.name).to eq 'postgres'
      expect(span.attributes['db.system']).to eq 'postgresql'
      expect(span.attributes['db.name']).to eq 'postgres'
      if options[:metadata_only] == true
        expect(span.attributes['db.statement']).to eq nil
      else
        expect(span.attributes['db.statement']).to eq statement
      end
      expect(span.attributes['db.operation']).to eq 'SELECT'
      # expect(span.attributes['db.connection_string']).to eq 'Server=(localdb)\v11.0; Integrated Security=true;'
      expect(span.attributes['db.user']).to eq 'postgres'
      expect(span.attributes['db.sql.table'].downcase).to eq 'traces'
      expect(span.attributes['net.peer.name']).to eq host.to_s
      expect(span.attributes['net.peer.port']).to eq port.to_s
    end
  end

  %i[exec_params async_exec_params sync_exec_params].each do |method|
    it "after request (with method: #{method}) " do
      statement = 'SELECT $1 AS a'
      client.send(method, statement, [1])

      expect(span.name).to eq 'postgres'
      expect(span.attributes['db.system']).to eq 'postgresql'
      expect(span.attributes['db.name']).to eq 'postgres'

      if options[:metadata_only] == true
        expect(span.attributes['db.statement']).to eq nil
      else
        expect(span.attributes['db.statement']).to eq statement
      end

      expect(span.attributes['db.operation']).to eq 'SELECT'
      expect(span.attributes['net.peer.name']).to eq host.to_s
      expect(span.attributes['net.peer.port']).to eq port.to_s
    end
  end

  %i[prepare async_prepare sync_prepare].each do |method|
    it "after preparing a statement (with method: #{method})" do
      statement = 'SELECT $1 AS a'
      client.send(method, 'foo', statement)

      expect(span.name).to eq 'postgres'
      expect(span.attributes['db.system']).to eq 'postgresql'
      expect(span.attributes['db.name']).to eq 'postgres'

      if options[:metadata_only] == true
        expect(span.attributes['db.statement']).to eq nil
      else
        expect(span.attributes['db.statement']).to eq statement
      end

      expect(span.attributes['db.operation']).to eq 'PREPARE'
      expect(span.attributes['db.postgresql.prepared_statement_name']).to eq 'foo'
      expect(span.attributes['net.peer.name']).to eq host.to_s
      expect(span.attributes['net.peer.port']).to eq port.to_s
    end
  end

  %i[exec_prepared async_exec_prepared sync_exec_prepared].each do |method|
    it "after executing prepared statement (with method: #{method})" do
      statement = 'SELECT $1 AS a'
      client.prepare('foo', 'SELECT $1 AS a')
      client.send(method, 'foo', [1])

      expect(last_span.name).to eq 'postgres'
      expect(last_span.attributes['db.system']).to eq 'postgresql'
      expect(last_span.attributes['db.name']).to eq 'postgres'
      expect(last_span.attributes['db.operation']).to eq 'EXECUTE'
      if options[:metadata_only] == true
        expect(span.attributes['db.statement']).to eq nil
      else
        expect(span.attributes['db.statement']).to eq statement
      end
      expect(last_span.attributes['db.postgresql.prepared_statement_name']).to eq 'foo'
      expect(last_span.attributes['net.peer.name']).to eq host.to_s
      expect(last_span.attributes['net.peer.port']).to eq port.to_s
    end
  end

  it 'only caches 50 prepared statement names' do
    51.times { |i| client.prepare("foo#{i}", "SELECT $1 AS foo#{i}") }
    client.exec_prepared('foo0', [1])

    expect(last_span.name).to eq 'postgres'
    expect(last_span.attributes['db.system']).to eq 'postgresql'
    expect(last_span.attributes['db.name']).to eq 'postgres'
    expect(last_span.attributes['db.operation']).to eq 'EXECUTE'
    # We should have evicted the statement from the cache
    expect(last_span.attributes['db.statement']).to be nil
    expect(last_span.attributes['db.postgresql.prepared_statement_name']).to eq 'foo0'
    expect(last_span.attributes['net.peer.name']).to eq host.to_s
    expect(last_span.attributes['net.peer.port']).to eq port.to_s
  end

  specify 'after error' do
    statement = 'SELECT INVALID'
    expect do
      client.exec(statement)
    end.to raise_error PG::UndefinedColumn

    expect(span.name).to eq 'postgres'
    expect(span.attributes['db.system']).to eq 'postgresql'
    expect(span.attributes['db.name']).to eq 'postgres'
    if options[:metadata_only] == true
      expect(span.attributes['db.statement']).to eq nil
    else
      expect(span.attributes['db.statement']).to eq statement
    end
    expect(span.attributes['db.operation']).to eq 'SELECT'
    expect(span.attributes['net.peer.name']).to eq host.to_s
    expect(span.attributes['net.peer.port']).to eq port.to_s

    expect(span.status.code).to eq(
      OpenTelemetry::Trace::Status::ERROR
    )
    expect(span.events.first.name).to eq 'exception'
    expect(span.events.first.attributes['exception.type']).to eq 'PG::UndefinedColumn'
    expect(span.events.first.attributes['exception.message']).to_not be nil
    expect(span.events.first.attributes['exception.stacktrace']).to_not be nil
  end

  it 'extracts statement type that begins the query' do
    base_sql = 'SELECT 1'
    explain = 'EXPLAIN'
    explain_sql = "#{explain} #{base_sql}"
    client.exec(explain_sql)

    expect(span.name).to eq 'postgres'
    expect(span.attributes['db.system']).to eq 'postgresql'
    expect(span.attributes['db.name']).to eq 'postgres'
    if options[:metadata_only] == true
      expect(span.attributes['db.statement']).to eq nil
    else
      expect(span.attributes['db.statement']).to eq explain_sql
    end
    expect(span.attributes['db.operation']).to eq 'EXPLAIN'
    expect(span.attributes['net.peer.name']).to eq host.to_s
    expect(span.attributes['net.peer.port']).to eq port.to_s
  end

  it 'uses database name as span.name fallback with invalid sql' do
    statement = 'DESELECT 1'
    expect do
      client.exec(statement)
    end.to raise_error PG::SyntaxError

    expect(span.name).to eq 'postgres'
    expect(span.attributes['db.system']).to eq 'postgresql'
    expect(span.attributes['db.name']).to eq 'postgres'
    if options[:metadata_only] == true
      expect(span.attributes['db.statement']).to eq nil
    else
      expect(span.attributes['db.statement']).to eq statement
    end
    expect(span.attributes['db.operation']).to be nil
    expect(span.attributes['net.peer.name']).to eq host.to_s
    expect(span.attributes['net.peer.port']).to eq port.to_s

    expect(span.status.code).to eq(
      OpenTelemetry::Trace::Status::ERROR
    )
    expect(span.events.first.name).to eq 'exception'
    expect(span.events.first.attributes['exception.type']).to eq 'PG::SyntaxError'
    expect(span.events.first.attributes['exception.message']).to_not be nil
    expect(span.events.first.attributes['exception.stacktrace'].nil?).to_not be nil
  end
end

##
## These tests require a running Postgres Docker container to talk to.
## Run: docker run --name postgres -p 5432:5432 -e POSTGRES_USERNAME='postgres' -e POSTGRES_PASSWORD='postgres' -d postgres
##
describe 'EpsagonPostgresInstrumentation' do
  let(:exporter)          { EXPORTER }
  let(:span)              { exporter.finished_spans.first }
  let(:last_span)         { exporter.finished_spans.last }
  let(:instrumentation)   { EpsagonPostgresInstrumentation.instance }
  let(:config)            { {} }

  let(:client) do
    ::PG::Connection.open(
      host: host,
      port: port,
      user: user,
      dbname: dbname,
      password: password
    )
  end

  before(:all) do
    client = ::PG::Connection.open(
      host: host,
      port: port,
      user: user,
      dbname: dbname,
      password: password
    )
    client.exec('CREATE TABLE Traces (ID int PRIMARY KEY, title varchar(40));');
  end

  before do
    instrumentation.instance_variable_set(:@installed, false)
    instrumentation.instance_variable_set(:@config, nil)
    exporter.reset

    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor span_processor
    end

    instrumentation.install(config)
    exporter.reset
  end

  after do
    # Force re-install of instrumentation
    instrumentation.instance_variable_set(:@installed, false)
  end

  after(:all) do
    client = ::PG::Connection.open(
      host: host,
      port: port,
      user: user,
      dbname: dbname,
      password: password
    )
    client.exec('DROP TABLE traces;')
  end

  describe 'tracing' do
    it 'before request' do
      expect(exporter.finished_spans.size).to eq 0
    end

    context 'with metadata_only = true' do
      let(:config) { { epsagon: { metadata_only: true } } }

      it_behaves_like 'sending correct postgres spans', { metadata_only: true }
    end

    context 'with metadata_only = false' do
      let(:config) { { epsagon: { metadata_only: false } } }

      it_behaves_like 'sending correct postgres spans', { metadata_only: false }
    end
  end
end
