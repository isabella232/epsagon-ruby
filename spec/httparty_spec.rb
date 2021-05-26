# frozen_string_literal: true

require 'httparty'
require 'epsagon'
require 'opentelemetry/sdk'
require 'climate_control'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

RSpec.describe 'HTTParty Instrumentation' do
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
    it "doesn't have spans before request" do
      expect(exporter.finished_spans.size).to eq 0
    end

    describe 'after requests' do
      before do
        HTTParty.get('https://google.com')
      end

      it 'has the correct span name' do
        expect(span.name).to eq 'google.com'
      end

      it 'has the correct type' do
        expect(span.attributes['type']).to eq 'http'
      end

      it 'has the correct method' do
        expect(span['http.method']).to eq 'get'
      end
    end
  end
end
