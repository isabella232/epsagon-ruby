# frozen_string_literal: true

require 'cgi'

# Utilities for epsagon opentelemetry solution
module Util
  def self.epsagon_query_attributes(query_string)
    if query_string&.include? '='
      { 'http.request.query_params' => CGI.parse(query_string).to_json }
    else
      { 'http.request.query' => query_string }
    end
  end
end
