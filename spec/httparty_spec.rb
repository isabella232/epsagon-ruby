# frozen_string_literal: true

require 'httparty'
# require 'epsagon'
require 'opentelemetry/sdk'
require_relative '../lib/instrumentation/httparty'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

RSpec.shared_examples 'HTTP Metadata Only' do |scheme, method, path|
  span_name = URI.parse(path).host.downcase

  it 'has the correct span name' do
    expect(span.name).to eq span_name
  end

  it 'has the correct type' do
    expect(span.attributes['type']).to eq 'http'
  end

  it 'has the correct method' do
    expect(span.attributes['operation']).to eq method
  end

  it 'has the correct scheme' do
    expect(span.attributes['http.scheme']).to eq scheme
  end

  it 'has the correct status_code' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has the correct http.request.path' do
    expect(span.attributes['http.request.path']).to eq path
  end
end

RSpec.shared_examples 'HTTP Metadata Only Non-Present Fields' do
  [
    'http.request.path_params',
    'http.request.query',
    'http.request.query_params',
    'http.request.body',
    'http.request.headers',
    'http.request.headers.User-Agent',
    'http.response.headers',
    'http.response.body'
  ].each do |attribute|
    it "does not have #{attribute}" do
      expect(span.attributes[attribute]).to eq nil
    end
  end
end

RSpec.shared_examples 'HTTP With Additional Data' do |request_body|
  it 'has accept-encoding header' do
    expect(span_request_headers['Accept-Encoding']).to eq 'gzip, deflate'
  end

  it 'has Content-Type header' do
    expect(span_request_headers['Content-type']).to eq 'text/html'
  end

  it 'has User Agent' do
    expect(span_request_headers['User-Agent']).to eq 'Mozilla/5.0'
  end

  unless request_body.nil?
    it 'has request body' do
      expect(span.attributes['http.request.body']).to eq request_body
    end
  end

  it 'has http.response.headers' do
    expect(span_response_headers).to_not be nil
  end

  it 'has http.response.body' do
    expect(span.attributes['http.response.body']).to_not be nil
  end
end

RSpec.describe 'HTTParty Instrumentation' do
  let(:exporter)          { EXPORTER }
  let(:span)              { exporter.finished_spans.first }
  let(:instrumentation)   { EpsagonHTTPartyInstrumentation.instance }
  let(:metadata_only) { true }
  let(:config) do
    {
      epsagon: {
        metadata_only: metadata_only
      }
    }
  end
  let(:request_headers) do
    {
      'Content-type': 'text/html',
      'Accept-Encoding': 'gzip, deflate',
      'User-Agent': 'Mozilla/5.0'
    }
  end
  let(:span_request_headers) { JSON.parse(span.attributes['http.request.headers']) }
  let(:span_response_headers) { JSON.parse(span.attributes['http.response.headers']) }

  before(:each) do
    instrumentation.instance_variable_set(:@installed, false)
    instrumentation.instance_variable_set(:@config, nil)
    exporter.reset

    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor span_processor
    end

    instrumentation.install(config)
    instrumentation.instance_variable_set(:@config, config)
  end

  it "doesn't have spans before request" do
    expect(exporter.finished_spans.size).to eq 0
  end

  describe 'GET' do
    describe 'GET HTTPS with metadata only' do
      let(:metadata_only) { true }

      before do
        HTTParty.get('https://www.google.com')
      end

      it_behaves_like 'HTTP Metadata Only', 'https', 'GET', 'https://www.google.com/'

      it_behaves_like 'HTTP Metadata Only Non-Present Fields'
    end

    describe 'GET HTTPS with additional data' do
      let(:metadata_only) { false }

      before(:each) do
        HTTParty.get('https://www.google.com/search?q=Test', headers: request_headers)
      end

      it_behaves_like 'HTTP Metadata Only', 'https', 'GET', 'https://www.google.com/search'

      it 'has empty request body' do
        expect(span.attributes['http.request.body']).to eq nil
      end

      it_behaves_like 'HTTP With Additional Data'
    end

    skip describe 'GET HTTPS with Params' do
      let(:metadata_only) { false }

      before do
        OpenTelemetry::SDK.configure do |c|
          c.add_span_processor span_processor
        end

        instrumentation.install(config)
        instrumentation.instance_variable_set(:@config, config)
        HTTParty.get('https://www.google.com/search?q=Test')
      end

      it 'has the correct http.request.query' do
        # expect(span.attributes['http.banana.query']).to eq 'q'
        p span.attributes['http.request.query']
        expect(span.attributes['http.request.query']).to eq 'q=Test'
      end

      it 'has http.request.query_params' do
        expect(JSON.parse(span.attributes['http.request.query_params'])).to eq 'q=Test'
      end

      it 'has empty request body' do
        expect(span.attributes['http.request.body']).to eq nil
      end
    end
  end

  describe 'POST' do
    context 'with metadata_only = true and no body' do
      let(:metadata_only) { true }
      before do
        HTTParty.post('http://localhost/post', headers: request_headers)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'POST', 'http://localhost/post'
      it_behaves_like 'HTTP Metadata Only Non-Present Fields'
    end

    context 'with metadata_only = true and body' do
      let(:metadata_only) { true }
      let(:body)          { { subject: 'This is the screen name' } }

      before do
        HTTParty.post('http://localhost/post', headers: request_headers, body: body.to_json)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'POST', 'http://localhost/post'
      it_behaves_like 'HTTP Metadata Only Non-Present Fields'
    end

    context 'with metadata_only = false and no body' do
      let(:metadata_only) { false }
      before do
        HTTParty.post('http://localhost/post', headers: request_headers)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'POST', 'http://localhost/post'
      it_behaves_like 'HTTP With Additional Data'
    end

    context 'with metadata_only = false and body' do
      let(:metadata_only) { false }
      let(:body)          { { subject: 'This is the screen name' } }

      before do
        HTTParty.post('http://localhost/post', headers: request_headers, body: body.to_json)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'POST', 'http://localhost/post'
      it_behaves_like 'HTTP With Additional Data', { subject: 'This is the screen name' }.to_json
    end
  end

  describe 'PATCH' do
    context 'with metadata_only = true and no body' do
      let(:metadata_only) { true }
      before do
        HTTParty.patch('http://localhost/patch', headers: request_headers)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'PATCH', 'http://localhost/patch'
      it_behaves_like 'HTTP Metadata Only Non-Present Fields'
    end

    context 'with metadata_only = true and body' do
      let(:metadata_only) { true }
      let(:body)          { { subject: 'This is the screen name' } }

      before do
        HTTParty.patch('http://localhost/patch', headers: request_headers, body: body.to_json)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'PATCH', 'http://localhost/patch'
      it_behaves_like 'HTTP Metadata Only Non-Present Fields'
    end

    context 'with metadata_only = false and no body' do
      let(:metadata_only) { false }
      before do
        HTTParty.patch('http://localhost/patch', headers: request_headers)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'PATCH', 'http://localhost/patch'
      it_behaves_like 'HTTP With Additional Data'
    end

    context 'with metadata_only = false and body' do
      let(:metadata_only) { false }
      let(:body)          { { subject: 'This is the screen name' } }

      before do
        HTTParty.patch('http://localhost/patch', headers: request_headers, body: body.to_json)
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'PATCH', 'http://localhost/patch'
      it_behaves_like 'HTTP With Additional Data', { subject: 'This is the screen name' }.to_json
    end
  end
end
