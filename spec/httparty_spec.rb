# frozen_string_literal: true

require 'httparty'
require 'epsagon'
require 'opentelemetry/sdk'
require 'climate_control'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

RSpec.shared_examples 'HTTP GET Metadata Only' do
  it 'has the correct span name' do
    expect(span.name).to eq 'www.google.com'
  end

  it 'has the correct type' do
    expect(span.attributes['type']).to eq 'http'
  end

  it 'has the correct method' do
    expect(span.attributes['operation']).to eq 'GET'
  end

  it 'has the correct scheme' do
    expect(span.attributes['http.scheme']).to eq 'https'
  end

  it 'has the correct status_code' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has the correct http.request.path' do
    expect(span.attributes['http.request.path']).to eq '/search'
  end
end

RSpec.describe 'HTTParty Instrumentation' do
  let(:exporter)          { EXPORTER }
  let(:span)              { exporter.finished_spans.first }
  let(:epsagon_token)     { 'abcd' }
  let(:epsagon_app_name)  { 'example_app' }

  before do
    Epsagon.class_variable_set(:@@epsagon_config, nil)
    exporter.reset
  end

  describe 'tracing' do
    it "doesn't have spans before request" do
      expect(exporter.finished_spans.size).to eq 0
    end

    describe 'GET HTTPS with metadata only' do
      before do
        ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                              EPSAGON_APP_NAME: epsagon_app_name,
                              EPSAGON_METADATA: 'true' do
          OpenTelemetry::SDK.configure do |c|
            c.add_span_processor span_processor
          end
        end

        Epsagon.init
        HTTParty.get('https://www.google.com')
      end

      it_behaves_like 'HTTP GET Metadata Only'

      [
        'http.request.path_params',
        'http.request.query',
        'http.request.query_params',
        'http.request.body',
        'http.request.headers',
        'http.request.body',
        'http.response.headers',
        'http.request.headers.User-Agent'
      ].each do |attribute|
        it "does not have #{attribute}" do
          expect(span.attributes[attribute]).to eq nil
        end
      end
    end

    describe 'GET HTTPS with additional data' do
      let(:request_headers) do
        {
          'Content-type': 'application/json',
          'Accept-Encoding': 'gzip, deflate',
          'User-Agent': 'Mozilla/5.0'
        }
      end
      let(:span_headers) { JSON.parse(span.attributes['http.request.headers']) }

      before do

        ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                              EPSAGON_APP_NAME: epsagon_app_name,
                              EPSAGON_METADATA: 'false' do
          OpenTelemetry::SDK.configure do |c|
            c.add_span_processor span_processor
          end
        end

        Epsagon.init(metadata_only: false)
        HTTParty.get('https://www.google.com/search?q=Test', headers: request_headers)
      end

      it_behaves_like 'HTTP GET Metadata Only'

      it 'has empty request body' do
        expect(span.attributes['http.request.body']).to eq nil
      end

      it 'has accept-encoding header' do
        expect(span_headers['accept-encoding']).to eq 'gzip, deflate'
      end

      it 'has Content-Type header' do
        expect(span_headers['content-type']).to eq 'application/json'
      end

      it 'has User Agent' do
        expect(span_headers['user-agent']).to eq 'Mozilla/5.0'
      end
    end

  #   describe 'GET HTTPS with Params' do
  #     before do
  #       HTTParty.get('https://www.google.com/search?q=Test')
  #     end

  #     it 'has the correct http.request.query' do
  #       # expect(span.attributes['http.banana.query']).to eq 'q'
  #       expect(JSON.parse(span.attributes['http.request.query'])).to eq 'q' => ['Test']
  #     end

  #     it 'has http.request.query_params' do
  #       expect(JSON.parse(span.attributes['http.request.query_params'])).to eq 'q' => ['Test']
  #     end

  #     it 'has empty request body' do
  #       expect(span.attributes['http.request.body']).to eq nil
  #     end
  #   end
  end

  # TODO: Test with metadata_only to ensure that flag works
end
