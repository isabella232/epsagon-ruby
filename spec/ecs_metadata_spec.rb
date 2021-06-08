# frozen_string_literal: true

require 'epsagon'
require 'webmock'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.describe 'ECS Metadata' do
  let(:metadata_uri) { 'http://localhost:9000/metadata' }
  let(:example_response) { File.read('./spec/support/aws_ecs_metadata_response.json') }

  context 'with ECS environment variable set' do
    config.before(:each) do
      stub_request(:get, 'http://localhost:9000/metadata').
        to_return(status: 200, body: example_response, headers: { 'Content-Type: application/json' })
    end

    around do |example|
      ClimateControl.modify ECS_CONTAINER_METADATA_URI: metadata_uri do
        example.run
      end
    end

  end
end
