# frozen_string_literal: true

require 'spec_helper'
require 'faraday'
require_relative '../lib/instrumentation/faraday'
require 'byebug'

describe 'Faraday::Middlewares::TracerMiddleware' do
  let(:instrumentation) { EpsagonFaradayInstrumentation.instance }
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

  let(:headers) do
    {
      'User-Agent': 'ruby',
      'Accept': '*/*',
      'Accept-Encoding': 'compress'
    }
  end

  let(:client) do
    ::Faraday.new('http://username:password@example.com') do |builder|
      builder.adapter(:test) do |stub|
        stub.get('/success') { |_| [200, {}, 'OK'] }
        stub.get('/failure') { |_| [500, {}, 'OK'] }
        stub.get('/not_found') { |_| [404, {}, 'OK'] }
      end
    end
  end

  before do
    exporter.reset
    instrumentation.instance_variable_set(:@config, nil)
    instrumentation.install(config)
  end

  after do
    instrumentation.instance_variable_set(:@installed, false)
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
      client.get('/success', headers)
    end

    it_behaves_like 'HTTP Request with metadata_only'
  end

  context 'with metadata_only = false' do
    let(:config) do
      {
        epsagon: {
          metadata_only: false,
          ignore_domains: []
        }
      }
    end

    context 'without query parameters' do
      before do
        client.get('/success', nil, headers)
      end

      it_behaves_like 'HTTP Request with metadata_only: false', {query_params: false}
    end

    context 'with query parameters' do
      before do
        client.get('/success?debug=true', nil, headers)
      end

      it_behaves_like 'HTTP Request with metadata_only: false', {query_params: true}
    end
  end

  skip describe 'first span' do


    it 'has http 200 attributes' do
      # expect(span.name).to eq 'example.com'
      # expect(span.attributes['operation']).to eq 'GET'
      # expect(span.attributes['http.status_code']).to eq 200
      # expect(span.attributes['http.request.path']).to eq '/success'
      # expect(response.env.request_headers['Traceparent']).to eq(
      #   "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      # )
    end

    it 'has http.status_code 404' do
      response = client.get('/not_found')

      expect(span.name).to eq 'example.com'
      expect(span.attributes['operation']).to eq 'GET'
      expect(span.attributes['http.status_code']).to eq 404
      expect(span.attributes['http.request.path']).to eq '/not_found'
      expect(response.env.request_headers['Traceparent']).to eq(
        "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      )
    end

    it 'has http.status_code 500' do
      response = client.get('/failure')

      expect(span.name).to eq 'example.com'
      expect(span.attributes['operation']).to eq 'GET'
      expect(span.attributes['http.status_code']).to eq 500
      expect(span.attributes['http.request.path']).to eq '/failure'
      expect(response.env.request_headers['Traceparent']).to eq(
        "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      )
    end

    #TODO: Check if we actually need this
    skip it 'merges http client attributes' do
      client_context_attrs = {
        'test.attribute' => 'test.value', 'http.method' => 'OVERRIDE'
      }
      response = OpenTelemetry::Common::HTTP::ClientContext.with_attributes(client_context_attrs) do
        client.get('/success')
      end

      expect(span.name).to eq 'example.com'
      expect(span.attributes['operation']).to eq 'OVERRIDE'
      expect(span.attributes['http.status_code']).to eq 200
      expect(span.attributes['http.request.path']).to eq '/success'
      expect(span.attributes['test.attribute']).to eq 'test.value'
      expect(response.env.request_headers['Traceparent']).to eq(
        "00-#{span.hex_trace_id}-#{span.hex_span_id}-01"
      )
    end

    # TODO: Decide if we actually need this
    skip it 'accepts peer service name from config' do
      instrumentation.instance_variable_set(:@installed, false)
      instrumentation.install(peer_service: 'example:faraday')

      client.get('/success')

      expect(span.attributes['peer.service']).to eq 'example:faraday'
    end

    # TODO: Decide if we actually need this
    skip it 'prioritizes context attributes over config for peer service name' do
      instrumentation.instance_variable_set(:@installed, false)
      instrumentation.install(peer_service: 'example:faraday')

      client_context_attrs = { 'peer.service' => 'example:custom' }
      OpenTelemetry::Common::HTTP::ClientContext.with_attributes(client_context_attrs) do
        client.get('/success')
      end

      expect(span.attributes['peer.service']).to eq 'example:custom'
    end
  end
end
