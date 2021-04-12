# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'bundler/inline'
require './lib/epsagon'

Epsagon.init(metadata_only: false, debug: true, backend: 'localhost:4569/', app_name: 'test-aws-sdk-s3')

gemfile(true) do
  source 'https://rubygems.org'

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  gem 'rails', github: 'rails/rails', :branch => "main"
  gem 'opentelemetry-sdk'
  gem 'opentelemetry-instrumentation-rails'
end

require 'action_controller/railtie'

# TraceRequestApp is a minimal Rails application inspired by the Rails
# bug report template for action controller.
# The configuration is compatible with Rails 6.0
class TraceRequestApp < Rails::Application
  config.root = __dir__
  config.hosts << 'example.org'
  secrets.secret_key_base = 'secret_key_base'
  config.eager_load = false
  config.logger = Logger.new($stdout)
  Rails.logger  = config.logger
end

# Simple setup for demonstration purposes, simple span processor should not be
# used in a production environment
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
  OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
)


Rails.application.initialize!

run Rails.application

# To run this example run the `rackup` command with this file
# Example: rackup trace_request_demonstration.ru
# Navigate to http://localhost:9292/
# Spans for the requests will appear in the console
