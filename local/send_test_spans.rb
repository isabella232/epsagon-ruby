# frozen_string_literal: true

require './lib/epsagon'
require 'faraday'
require 'net/http'
require 'aws-sdk-s3'

BACKEND = 'opentelemetry.tc.epsagon.com:443/traces'

Epsagon.init(metadata_only: false, debug: true, app_name: 'send-test-spans')

# add custom resource tag:
# OpenTelemetry::SDK.configure do |c|
#   c.resource = OpenTelemetry::SDK::Resources::Resource.telemetry_sdk.merge(
#     OpenTelemetry::SDK::Resources::Resource.create({ 'custom_resource_tag' => 'custom_resource_tag_val' })
#   )
# end

# Aws::S3::Client.new.list_buckets()

pids = {}
pids[:traced_rails] = spawn 'rackup trace_request_demonstration.ru'
pids[:traced_app] = spawn 'ruby local/traced_sinatra.rb'
pids[:untraced_app] = spawn 'ruby local/untraced_sinatra.rb'
sleep 6

# # "vanilla" spans:
# tracer = OpenTelemetry.tracer_provider.tracer('send-test-spans', '0.1.0')

# #Rails:
# `curl -s -X POST "http://localhost:9292/valid/path?q1=a&q2=b&q1=c" -d "amir=asdasd"`
# `curl  http://localhost:9292/make-error`
# `curl  http://localhost:9292/path/does/not/exist`

# tracer.in_span('nested_outer') do |span|
#   span.set_attribute('is_question', true)
#   span.set_attribute('answer', 42)
#   span.set_attribute('exact', 42.225)
#   span.set_attribute('message', 'These pretzels are making me thirsty')
#   tracer.in_span('inner') do |child_span|
#     child_span.set_attribute('inner_span_attr', 'is awesome')
#     tracer.in_span('more_inner') do |grandchild_span|
#       grandchild_span.set_attribute('more_inner_span_attr', 'is more awesome')
#     end
#   end
# end

# tracer.in_span('test_status_ok') do |span|
#   span.status = OpenTelemetry::Trace::Status.new(OpenTelemetry::Trace::Status::OK)
# end

# tracer.in_span('test_status_error') do |span|
#   span.status = OpenTelemetry::Trace::Status.new(OpenTelemetry::Trace::Status::ERROR)
# end

# begin
# 	tracer.in_span('with_exception') do |span|
# 	  raise RuntimeError.new("This is the error message")
# 	end
# rescue RuntimeError
# 	#raised and ignored for span creation
# end

# #Faraday:
# url = 'http://localhost:4566/some/path/index.html;pathparam=who,even,uses,this?q1=a&q2=b&q1=c'
# Faraday.post(url, 'yanti=parazi')

# #Faraday with error:
# Faraday.get('http://localhost:4566/does-not-exist')

# #Faraday with server error:
# Faraday.get('http://localhost:4566/make-error')

# Sinatra (on server process) with error
`curl -X POST http://localhost:4567/foo/bar -d "amir=asdasd"`

# Sinatra (on server process) with error
# `curl http://localhost:4567/asdasd`

# # Sinatra (on server process) server error:
# `curl http://localhost:4567/make-error`

Process.kill('SIGHUP', pids[:traced_app])
Process.detach(pids[:traced_app])
Process.kill('SIGHUP', pids[:untraced_app])
Process.detach(pids[:untraced_app])
Process.kill('SIGHUP', pids[:traced_rails])
Process.detach(pids[:traced_rails])
