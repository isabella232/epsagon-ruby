# frozen_string_literal: true

require './lib/epsagon'

pids = {}
pids[:traced_app] = spawn 'rackup trace_request_demonstration.ru'
sleep 6

`curl -s -X POST "http://localhost:9292/valid/path?q1=a&q2=b&q1=c" -d "amir=asdasd"`
`curl  http://localhost:9292/make-error`
`curl  http://localhost:9292/path/does/not/exist`

Process.kill('SIGHUP', pids[:traced_app])
Process.detach(pids[:traced_app])
