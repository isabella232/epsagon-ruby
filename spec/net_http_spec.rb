# frozen_string_literal: true
require 'spec_helper'
require_relative '../lib/instrumentation/net_http'
require 'byebug'

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
    stub_request(:get, 'http://example.com/success?count=10').to_return(status: 200)
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
    specify 'before request' do
      expect(exporter.finished_spans.size).to eq 0
    end

    describe 'with metadata_only' do
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

      include_examples 'HTTP Request with metadata_only' do
        let(:operation)   { 'GET' }
        let(:status_code) { 200 }
        let(:path)        { '/success' }
      end
    end

    describe 'with metadata_only = false' do
      let(:config) do
        {
          epsagon: {
            metadata_only: false,
            ignore_domains: []
          }
        }
      end

      context 'without query params' do
        before do
          ::Net::HTTP.get('example.com', '/success')
        end

        include_examples 'HTTP Request with metadata_only: false' do
          let(:operation)   { 'GET' }
          let(:status_code) { 200 }
          let(:path)        { '/success' }
        end
        include_examples 'HTTP Request without query params'
      end

      context 'with query params' do
        before do
          uri = URI('http://example.com/success?count=10')
          ::Net::HTTP.get(uri) # => String
        end

        include_examples 'HTTP Request with metadata_only: false' do
          let(:operation)   { 'GET' }
          let(:status_code) { 200 }
          let(:path)        { '/success' }
        end
        include_examples 'HTTP Request with query params'
      end
    end

    context 'failure' do
      it 'captures the http error' do
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

      it 'captures request timeout' do
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
end
