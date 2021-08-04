# frozen_string_literal: true

require 'epsagon'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

RSpec.describe do
  describe 'Configuration' do
    let(:exporter) { EXPORTER }
    let(:spans) { exporter.finished_spans }
    let(:span) { exporter.finished_spans.last }
    let(:tracer) { OpenTelemetry.tracer_provider.tracer('epsagon-ruby-tests', '0.1.0') }
    let(:epsagon_token)     { 'abcdabcdabcdabcdabcdabcd' }
    let(:epsagon_app_name)  { 'example_app' }
    let(:epsagon_debug)     { true }
    let(:epsagon_metadata)  { true }

    before do
      Epsagon.class_variable_set(:@@epsagon_config, nil)
    end

    describe 'does not send configured ignored_keys' do
      context 'with ignored keys set' do
        around do |example|
          exporter.reset
          Epsagon.init(token: epsagon_token, app_name: epsagon_app_name)
          OpenTelemetry::SDK.configure do |c|
            c.add_span_processor span_processor
          end
          require 'byebug'; byebug
          example.run
        end

        it 'does not set ignored keys' do
          Epsagon.add_ignored_key('excluded')
          Epsagon.add_ignored_key('inside.mapping.excluded')
          Epsagon.add_ignored_key('nested.mapping.partially.excluded')
          tracer.in_span('nested_outer') do |span|
            nested = {'partially' => {'excluded' => 'should not see this', 'included' => 'should see this'}}
            inside = {'excluded' => 'should not see this', 'included' => 'should see this'}
            span.set_mapping_attribute('excluded', 'should not see this')
            span.set_mapping_attribute('inside.mapping', inside)
            span.set_mapping_attribute('nested.mapping', nested)
          end
          Epsagon.remove_ignored_key('excluded')
          Epsagon.remove_ignored_key('inside.mapping.excluded')
          Epsagon.remove_ignored_key('nested.mapping.partially.excluded')
          expect(span.attributes['excluded']).to eq nil
          expect(JSON.parse(span.attributes['inside.mapping'])).to eq({'included' => 'should see this'})
          expect(JSON.parse(span.attributes['nested.mapping'])).to eq({'partially' => {'included' => 'should see this'}})
        end
      end
    end
  end
end
