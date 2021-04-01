# frozen_string_literal: true

require 'opentelemetry/sdk'
require 'faraday'
require './lib/epsagon'

url = 'http://example.com/some/path/index.html;pathparam=who,even,uses,this?q1=a&q2=b&q1=c'
Faraday.post(url, 'yanti=parazi')
