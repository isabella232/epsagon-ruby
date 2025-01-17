# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

gem 'opentelemetry-api', '~> 0.11.0'
gem 'opentelemetry-sdk', '~> 0.11.1'

gem 'opentelemetry-instrumentation-sinatra', '~> 0.11.0'

gem 'pry', '~> 0.13.1'

gem 'opentelemetry-exporter-otlp', '~> 0.11.0'

gem 'rspec', '~> 3.10'

gem 'aws-sdk-core', '~> 3.113'

gem 'rack', '~> 2.2'

rails_version = ENV.fetch("RAILS_VERSION", "6.1")

if rails_version == "master"
  rails_constraint = { github: "rails/rails" }
else
  rails_constraint = "~> #{rails_version}.0"
end

gem "rails", rails_constraint

gem 'faraday', '~> 1.4'

gem 'sinatra', '~> 2.1'

gem 'aws-sdk-s3', '~> 1.93'

gem "opentelemetry-instrumentation-sidekiq", "~> 0.11.0"

gem "byebug", "~> 11.1"

gem "aws-sdk-sqs", "~> 1.38"

gem "aws-sdk-sns", "~> 1.40"

gem 'rspec-rake'

gem 'climate_control'

gem "pg", "~> 1.2"
gem 'pg_query'
gem 'webmock'

gem "aws-sdk-secretsmanager", "~> 1.46"
