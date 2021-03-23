# frozen_string_literal: true

require 'aws-sdk-s3'
require './lib/epsagon'

print Aws::S3::Client.new.get_object(bucket: 'epsagon-ruby-test', key: 'test_file.txt').body.read
