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
epsagon_token = 'abcd'
epsagon_app_name = 'example_app'
metadata_uri = 'http://localhost:9000/metadata'
example_response = File.read('./spec/support/aws_ecs_metadata_response.json')
default_rails_app = nil

describe 'ECS Metadata' do
  include Rack::Test::Methods

  let(:exporter) { EXPORTER }
  let(:spans) { exporter.finished_spans }
  let(:span) { exporter.finished_spans.last }
  let(:rails_app) { default_rails_app }

  before(:all) do
    stub_request(:get, 'http://localhost:9000/metadata')
      .to_return(status: 200, body: example_response, headers: {})
    ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                          EPSAGON_APP_NAME: epsagon_app_name,
                          ECS_CONTAINER_METADATA_URI: metadata_uri do
      OpenTelemetry::SDK.configure do |c|
        c.add_span_processor span_processor
      end
      Epsagon.init
    end
  end

  before do
    exporter.reset

    default_rails_app = AppConfig.initialize_app
    ::Rails.application = default_rails_app
  end

  context 'with ECS environment variable set' do
    before(:each) do
      get '/ok'
    end

    describe 'span' do
      let(:resource) { span.resource.instance_values['attributes'] }

      it 'has aws.account_id' do
        expect(resource['aws.account_id']).to eq '012345678910'
      end

      it 'has aws.region' do
        expect(resource['aws.region']).to eq 'us-east-2'
      end

      it 'has aws.ecs.cluster' do
        expect(resource['aws.ecs.cluster']).to eq 'default'
      end

      it 'has aws.ecs.task_arn' do
        expect(resource['aws.ecs.task_arn']).to eq 'arn:aws:ecs:us-east-2:012345678910:task/9781c248-0edd-4cdb-9a93-f63cb662a5d3'
      end

      it 'has aws.ecs.container_name' do
        expect(resource['aws.ecs.container_name']).to eq 'nginx-curl'
      end

      it 'has aws.ecs.task.family' do
        expect(resource['aws.ecs.task.family']).to eq 'nginx'
      end

      it 'has aws.ecs.task.revision' do
        expect(resource['aws.ecs.task.revision']).to eq '5'
      end
    end
  end

  def app
    rails_app
  end
end
