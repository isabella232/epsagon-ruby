# frozen_string_literal: true

require 'epsagon'

RSpec.describe do
  describe 'Configuration' do
    let(:epsagon_token)     { 'abcdabcdabcdabcdabcdabcd' }
    let(:epsagon_app_name)  { 'example_app' }
    let(:epsagon_debug)     { true }
    let(:epsagon_metadata)  { true }

    before do
      Epsagon.class_variable_set(:@@epsagon_config, nil)
    end

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

    describe 'assigns values passed to init' do
      context 'without any arguments' do
        before do
          Epsagon.init
        end

        it 'assigns empty string to token' do
          expect(Epsagon.get_config[:token]).to eq ''
        end

        it 'assigns empty string to app name' do
          expect(Epsagon.get_config[:app_name]).to eq ''
        end

        it 'assigns default value of "false" to debug' do
          expect(Epsagon.get_config[:debug]).to eq false
        end

        it 'assigns default value of "true" to metadata' do
          expect(Epsagon.get_config[:metadata_only]).to eq true
        end

        it 'assigns default value of "5000" to max attribute size' do
          expect(Epsagon.get_config[:max_attribute_size]).to eq 5000
        end

        it 'assigns default value of "opentelemetry.tc.epsagon.com:443/traces" to backend' do
          expect(Epsagon.get_config[:backend]).to eq 'opentelemetry.tc.epsagon.com:443/traces'
        end
      end

      context 'with token and app_name' do
        before do
          Epsagon.init(token: epsagon_token, app_name: epsagon_app_name)
        end

        it 'assigns the correct token' do
          expect(Epsagon.get_config[:token]).to eq epsagon_token
        end

        it 'assigns the correct app_name' do
          expect(Epsagon.get_config[:app_name]).to eq epsagon_app_name
        end
      end

      context 'with environment variable set' do
        let(:second_epsagon_token) { 'second_token' }
        let(:second_epsagon_app_name) { 'second_app_name' }

        before do
          Epsagon.init(token: second_epsagon_token, app_name: second_epsagon_app_name)
        end

        around do |example|
          ClimateControl.modify EPSAGON_TOKEN: epsagon_token,
            EPSAGON_APP_NAME: epsagon_app_name,
            EPSAGON_DEBUG: epsagon_debug.to_s,
            EPSAGON_METADATA: epsagon_metadata.to_s do
              example.run
          end
        end

        it 'does overwrite the environment epsagon_token' do
          expect(Epsagon.get_config[:token]).to eq second_epsagon_token
        end

        it 'does overwrite the environment epsagon_app_name' do
          expect(Epsagon.get_config[:app_name]).to eq second_epsagon_app_name
        end

        it 'keeps the debug flag' do
          expect(Epsagon.get_config[:debug]).to eq epsagon_debug
        end

        it 'keeps the metadata flag' do
          expect(Epsagon.get_config[:metadata_only]).to eq epsagon_metadata
        end
      end
    end
  end
end
