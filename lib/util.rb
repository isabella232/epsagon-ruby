# frozen_string_literal: true

require 'cgi'

# Utilities for epsagon opentelemetry solution
module Util
  def self.validate_value(h, k, message, &block)
    raise ArgumentError.new( "#{k} #{message}. Got #{h[k].class}: #{h[k]}" ) unless yield(h[k])
  end

  def self.epsagon_query_attributes(query_string)
    if query_string&.include? '='
      { 'http.request.query_params' => CGI.parse(query_string).to_json }
    else
      { 'http.request.query' => query_string }
    end
  end


  def self.remove_key_recursive(h, key) 
    dot_idx = key.index('.')
    if not dot_idx.nil?
      next_hash = h[key[0..dot_idx - 1]]
      self.remove_key_recursive(next_hash, key[dot_idx + 1..-1]) if next_hash
    else
      h.delete(key)
    end
  end

  def self.prepare_attr(key, value, max_size, excluded_keys)
    return nil if excluded_keys.include? key
    return self.trim_attr(value, max_size) unless value.instance_of? Hash
    value = value.dup
    excluded_keys.each do |ekey|
      if ekey.start_with? (key + '.')
        rest_of_key = ekey[key.size + 1..-1]
        self.remove_key_recursive(value, rest_of_key)
      end
    end
    return self.trim_attr(JSON.dump(value), max_size)
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
  		(value.frozen? ? value.dup : value).force_encoding('utf-8')[0, max_size]
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
