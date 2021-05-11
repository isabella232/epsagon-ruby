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

  def self.trim_attr(value, max_size)
  	if value.instance_of? Array then 
  		current_size = 2
  		value.each_with_index do |el, i|
  			el_size =  el.to_s.size + (i==0 ? 0 : 2)
  			if current_size + el_size > max_size then 
  				return value[0,i] + [Util.trim_attr(el, max_size - current_size)]
  			else 
  				current_size += el_size
  			end
  		end
  		return value
  	elsif value.instance_of? String then
  		value[0, max_size]
  	else
  		value
  	end
  end

  def self.redis_default_url
    @@redis_default_url ||= "#{Redis::Client::DEFAULTS[:scheme]}://#{Redis::Client::DEFAULTS[:host]}:#{Redis::Client::DEFAULTS[:port]}/#{Redis::Client::DEFAULTS[:db]}"
  end

  def self.untraced(&block)
	  OpenTelemetry::Trace.with_span(OpenTelemetry::Trace::Span.new, &block)
	end

end
