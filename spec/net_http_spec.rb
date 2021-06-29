# frozen_string_literal: true
require 'spec_helper'
require_relative '../lib/instrumentation/net_http'

shared_examples 'HTTP Request with metadata_only' do
  it 'has one finished span' do
    expect(exporter.finished_spans.size).to eq 1
  end

  it 'has the correct span name' do
    expect(span.name).to eq 'example.com'
  end

  it 'has "operation" set' do
    expect(span.attributes['operation']).to eq 'GET'
  end

  it 'has "http.scheme" set' do
    expect(span.attributes['http.scheme']).to eq 'http'
  end

  it 'has "http.status_code" set' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has "http.request.path" set' do
    expect(span.attributes['http.request.path']).to eq '/success'
  end

  it 'has correct span kind' do
    expect(span.kind).to eq :client
  end

  it 'does not have "http.request.path_params"' do
    expect(span.attributes['http.request.path_params']).to be nil
  end

  it 'does not have "http.request.query"' do
    expect(span.attributes['http.request.query']).to be nil
  end

  it 'does not have "http.request.query_params"' do
    expect(span.attributes['http.request.query_params']).to be nil
  end

  it 'does not have "http.request.body"' do
    expect(span.attributes['http.request.body']).to be nil
  end

  it 'does not have "http.request.headers"' do
    expect(span.attributes['http.request.headers']).to be nil
  end

  it 'does not have "http.response.body"' do
    expect(span.attributes['http.response.body']).to be nil
  end

  it 'does not have "http.response.headers"' do
    expect(span.attributes['http.response.headers']).to be nil
  end

  it 'does not have "http.request.headers.User-Agent"' do
    expect(span.attributes['http.request.headers.User-Agent']).to be nil
  end
end

shared_examples 'HTTP Request with metadata_only: false' do
  it 'has one finished span' do
    expect(exporter.finished_spans.size).to eq 1
  end

  it 'has the correct span name' do
    expect(span.name).to eq 'example.com'
  end

  it 'has "operation" set' do
    expect(span.attributes['operation']).to eq 'GET'
  end

  it 'has "http.scheme" set' do
    expect(span.attributes['http.scheme']).to eq 'http'
  end

  it 'has "http.status_code" set' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has "http.request.path" set' do
    expect(span.attributes['http.request.path']).to eq '/success'
  end

  it 'has correct span kind' do
    expect(span.kind).to eq :client
  end

  it 'has "http.request.path_params"' do
    expect(span.attributes['http.request.path_params']).to be nil
  end

  it 'has "http.request.query"' do
    expect(span.attributes['http.request.query']).to be nil
  end

  it 'has "http.request.query_params"' do
    expect(span.attributes['http.request.query_params']).to be nil
  end

  it 'has "http.request.body"' do
    expect(span.attributes['http.request.body']).to be nil
  end

  it 'has "http.request.headers"' do
    expect(span.attributes['http.request.headers']).to be nil
  end

  it 'has "http.response.body"' do
    expect(span.attributes['http.response.body']).to be nil
  end

  it 'has "http.response.headers"' do
    expect(span.attributes['http.response.headers']).to be nil
  end

  it 'has "http.request.headers.User-Agent"' do
    expect(span.attributes['http.request.headers.User-Agent']).to be nil
  end
end

describe 'Net::HTTP::Instrumentation' do
  let(:instrumentation) { EpsagonNetHTTPInstrumentation.instance }
  let(:exporter) { EXPORTER }
  let(:span) { exporter.finished_spans.first }
  let(:config) do
    {
      epsagon: {
        metadata_only: false,
        ignore_domains: []
      }
    }
  end

  before do
    exporter.reset
    WebMock.disable_net_connect!(allow_localhost: true)
    stub_request(:get, 'http://example.com/success').to_return(status: 200)
    stub_request(:post, 'http://example.com/failure').to_return(status: 500)
    stub_request(:get, 'https://example.com/timeout').to_timeout

    instrumentation.instance_variable_set(:@installed, false)
    instrumentation.instance_variable_set(:@config, nil)
    instrumentation.install(config)
  end

  after do
    # Force re-install of instrumentation
    instrumentation.instance_variable_set(:@installed, false)
  end

  describe '#request' do
    it 'before request' do
      expect(exporter.finished_spans.size).to eq 0
    end

    context 'with metadata_only' do
      let(:config) do
        {
          epsagon: {
            metadata_only: true,
            ignore_domains: []
          }
        }
      end

      before do
        ::Net::HTTP.get('example.com', '/success')
      end

      it_behaves_like 'HTTP Request with metadata_only'
    end

    # it 'after request with success code' do
    #   assert_requested(
    #     :get,
    #     'http://example.com/success',
    #     headers: { 'Traceparent' => "00-#{span.hex_trace_id}-#{span.hex_span_id}-01" }
    #   )
    # end

    it 'after request with failure code' do
      ::Net::HTTP.post(URI('http://example.com/failure'), 'q' => 'ruby')

      expect(exporter.finished_spans.size).to eq 1
      expect(span.name).to eq 'example.com'
      expect(span.attributes['operation']).to eq 'POST'
      expect(span.attributes['http.scheme']).to eq 'http'
      expect(span.attributes['http.status_code']).to eq 500
      expect(span.attributes['http.request.path']).to eq '/failure'
      expect(span.kind).to eq :client
      assert_requested(
        :post,
        'http://example.com/failure',
        headers: { 'Traceparent' => "00-#{span.hex_trace_id}-#{span.hex_span_id}-01" }
      )
    end

    it 'after request timeout' do
      expect do
        ::Net::HTTP.get(URI('https://example.com/timeout'))
      end.to raise_error Net::OpenTimeout

      expect(exporter.finished_spans.size).to eq 1
      expect(span.name).to eq 'example.com'
      expect(span.attributes['operation']).to eq 'GET'
      expect(span.attributes['http.scheme']).to eq 'https'
      expect(span.attributes['http.status_code']).to be nil
      expect(span.attributes['http.request.path']).to eq '/timeout'
      expect(span.kind).to eq :client
      expect(span.status.code).to eq(
        OpenTelemetry::Trace::Status::ERROR
      )
      expect(span.status.description).to eq(
        'Unhandled exception of type: Net::OpenTimeout'
      )
      assert_requested(
        :get,
        'https://example.com/timeout',
        headers: { 'Traceparent' => "00-#{span.hex_trace_id}-#{span.hex_span_id}-01" }
      )
    end

    it 'merges http client attributes' do
      OpenTelemetry::Common::HTTP::ClientContext.with_attributes('peer.service' => 'foo') do
        ::Net::HTTP.get('example.com', '/success')
      end

      expect(exporter.finished_spans.size).to eq 1
      expect(span.name).to eq 'example.com'
      expect(span.attributes['operation']).to eq 'GET'
      expect(span.attributes['http.scheme']).to eq 'http'
      expect(span.attributes['http.status_code']).to eq 200
      expect(span.attributes['http.request.path']).to eq '/success'
      expect(span.attributes['peer.service']).to eq 'foo'
      expect(span.kind).to eq :client
      assert_requested(
        :get,
        'http://example.com/success',
        headers: { 'Traceparent' => "00-#{span.hex_trace_id}-#{span.hex_span_id}-01" }
      )
    end
  end

  # describe '#connect' do
  #   it 'emits span on connect' do
  #     WebMock.allow_net_connect!
  #     TCPServer.open('localhost', 0) do |server|
  #       Thread.start { server.accept }
  #       port = server.addr[1]

  #       uri  = URI.parse("http://localhost:#{port}/example")
  #       http = Net::HTTP.new(uri.host, uri.port)
  #       http.read_timeout = 0
  #       expect(-> { http.request(Net::HTTP::Get.new(uri.request_uri)) }).to raise_error(Net::ReadTimeout)
  #     end

  #     expect(exporter.finished_spans.size).to eq(2)
  #     expect(span.name).to eq 'example.com'
  #     expect(span.kind).to eq :client
  #   ensure
  #     WebMock.disable_net_connect!
  #   end

  #   it 'captures errors' do
  #     WebMock.allow_net_connect!

  #     uri  = URI.parse('http://localhost:99999/example')
  #     http = Net::HTTP.new(uri.host, uri.port)
  #     expect(-> { http.request(Net::HTTP::Get.new(uri.request_uri)) }).to raise_error

  #     expect(exporter.finished_spans.size).to eq(1)
  #     expect(span.name).to eq 'localhost'

  #     span_event = span.events.first
  #     expect(span_event.name).to eq 'exception'
  #     expect(span_event.attributes['exception.type']).to_not be nil
  #     expect(span.kind).to eq :client
  #     expect(span_event.attributes['exception.message']).must_match(/Failed to open TCP connection to localhost:99999/)
  #   ensure
  #     WebMock.disable_net_connect!
  #   end
  # end
end
