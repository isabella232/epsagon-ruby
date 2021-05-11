# frozen_string_literal: true

require 'epsagon'

RSpec.describe do
  describe 'Configuration' do
    let(:epsagon_token)     { 'abcd' }
    let(:epsagon_app_name)  { 'example_app' }
    let(:epsagon_debug)     { true }
    let(:epsagon_metadata)  { true }

    describe 'retrieves values from environment variables' do
      context 'with set values' do
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

        specify 'retrieves EPSAGON_TOKEN' do
          expect(Epsagon.get_config[:token]).to eq epsagon_token
        end

        specify 'retrieves EPSAGON_APP_NAME' do
          expect(Epsagon.get_config[:app_name]).to eq epsagon_app_name
        end

        specify 'retrieves EPSAGON_DEBUG' do
          expect(Epsagon.get_config[:debug]).to eq epsagon_debug
        end

        specify 'retrieves EPSAGON_METADATA' do
          expect(Epsagon.get_config[:metadata_only]).to eq epsagon_metadata
        end
      end

      context 'without set environment variable' do
        before do
          Epsagon.init
        end

        it 'assigns empty string to EPSAGON_TOKEN' do
          expect(Epsagon.get_config[:token]).to eq ''
        end

        it 'assigns empty string to EPSAGON_APP_NAME' do
          expect(Epsagon.get_config[:app_name]).to eq ''
        end
      end
    end
  end
end