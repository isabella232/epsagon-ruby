# frozen_string_literal: true

require 'epsagon'

RSpec.describe do
  describe 'Configuration' do
    let(:epsagon_token)     { 'abcd' }
    let(:epsagon_app_name)  { 'example_app' }
    let(:epsagon_debug)     { true }
    let(:epsagon_metadata)  { true }

    before do
      Epsagon.init
    end

    around do |example|
      ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
                  EPSAGON_APP_NAME: epsagon_app_name,
                  EPSAGON_DEBUG: epsagon_debug.to_s,
                  EPSAGON_METADATA: epsagon_metadata.to_s do
        example.run
      end
    end

    describe 'retrieves' do
      specify 'token from environment variable' do
        expect(Epsagon.get_config[:token]).to eq epsagon_token
      end

      specify 'app_name from environment variable' do
        expect(Epsagon.get_config[:app_name]).to eq epsagon_app_name
      end

      specify 'debug from environment variable' do
        expect(Epsagon.get_config[:debug]).to eq epsagon_debug
      end

      specify 'metadata from environment variable' do
        expect(Epsagon.get_config[:metadata_only]).to eq epsagon_metadata
      end
    end
  end
end