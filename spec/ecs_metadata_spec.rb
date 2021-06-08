# frozen_string_literal: true

require 'rails'
require 'rack/test'
require 'opentelemetry/sdk'
require 'byebug'
require 'webmock/rspec'
require 'climate_control'
require_relative 'test_helpers/app_config'
require 'epsagon'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

default_rails_app = nil

describe 'ECS Metadata' do
  include Rack::Test::Methods

  let(:epsagon_token)     { 'abcd' }
  let(:epsagon_app_name)  { 'example_app' }
  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }
  let(:span) { exporter.finished_spans.last }
  let(:rails_app) { default_rails_app }
  let(:metadata_uri) { 'http://localhost:9000/metadata' }
  let(:example_response) { File.read('./spec/support/aws_ecs_metadata_response.json') }

  # Clear captured spans
  before do
    exporter.reset
    stub_request(:get, 'http://localhost:9000/metadata')
      .to_return(status: 200, body: example_response, headers: {})

    ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                          EPSAGON_APP_NAME: epsagon_app_name do
      OpenTelemetry::SDK.configure do |c|
        c.add_span_processor span_processor
      end
      Epsagon.init
    end

    default_rails_app = AppConfig.initialize_app
    ::Rails.application = default_rails_app
  end

  before do
    # WebMock.disable_net_connect!(allow_localhost: true)
  end

  context 'with ECS environment variable set' do
    before(:each) do
      get '/ok'
    end

    around do |example|
      ClimateControl.modify ECS_CONTAINER_METADATA_URI: metadata_uri do
        example.run
      end
    end

    describe 'span' do
      it 'has aws.ecs.container_name' do
        expect(span.resource.instance_values['attributes']['aws.ecs.container_name']).to eq 'nginx-curl'
      end
    end
  end

  context 'without ECS environment variable set' do
    before do
      get '/ok'
    end

    describe 'span' do
      it 'does not have aws.ecs.container_name set' do
        expect(span.resource.instance_values['attributes']['aws.ecs.container_name']).to eq nil
      end
    end
  end

  def app
    rails_app
  end
end
