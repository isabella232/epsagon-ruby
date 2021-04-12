# frozen_string_literal: true

require './lib/epsagon'

pids = {}
pids[:traced_app] = spawn 'rackup trace_request_demonstration.ru'
sleep 30

puts `curl -X POST http://localhost:9292/foo/bar -d "amir=asdasd"`

Process.kill('SIGHUP', pids[:traced_app])
Process.detach(pids[:traced_app])

