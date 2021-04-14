# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require './lib/epsagon'

Epsagon.init(metadata_only: false, insecure: true, debug: true, backend: 'localhost:4569/', app_name: 'epsaon-test-rails')

require 'action_controller/railtie'
require 'rails'

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

class TestsController < ActionController::Base
  include Rails.application.routes.url_helpers

  def index
    render :inline => "ok"
  end

  def make_error
  	raise
  end
end

Rails.application.initialize!



Rails.application.routes.draw do
	post '/valid/:path', to: 'tests#index' 
	get '/make-error', to: 'tests#make_error'
end




run Rails.application

# To run this example run the `rackup` command with this file
# Example: rackup trace_request_demonstration.ru
# Navigate to http://localhost:9292/
# Spans for the requests will appear in the console
