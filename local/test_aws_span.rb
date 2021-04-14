# frozen_string_literal: true

require 'aws-sdk-s3'
require './lib/epsagon'

Epsagon.init(metadata_only: false, debug: true, backend: 'localhost:4569/', app_name: 'test-aws-sdk-s3')

print Aws::S3::Client.new.get_object(bucket: 'epsagon-ruby-test', key: 'test_file.txt').body.read
