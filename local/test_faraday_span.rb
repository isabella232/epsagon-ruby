# frozen_string_literal: true

require 'opentelemetry/sdk'
require 'faraday'
require './lib/epsagon'

BACKEND = 'opentelemetry.tc.epsagon.com:443/traces'

Epsagon.init(metadata_only: false, debug: true, backend: BACKEND, app_name: 'send-test-spans')

# add custom resource tag:
OpenTelemetry::SDK.configure do |c|
	puts 'resource tag'
  c.resource = OpenTelemetry::SDK::Resources::Resource.telemetry_sdk.merge(
    OpenTelemetry::SDK::Resources::Resource.create({ 'custom_resource_tag' => 'custom_resource_tag_val' })
  )
end

url = 'http://example.com/some/path/index.html;pathparam=who,even,uses,this?q1=a&q2=b&q1=c'
Faraday.post(url, 'yanti=parazi')
