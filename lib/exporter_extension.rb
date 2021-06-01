

module OpenTelemetry
  module Exporter
    module OTLP
      # An OpenTelemetry trace exporter that sends spans over HTTP as Protobuf encoded OTLP ExportTraceServiceRequests.
      class Exporter # rubocop:disable Metrics/ClassLength
        def send_bytes(bytes, timeout:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          retry_count = 0
          timeout ||= @timeout
          start_time = Time.now
          untraced do # rubocop:disable Metrics/BlockLength
            request = Net::HTTP::Post.new(@path)
            request.body = if @compression == 'gzip'
                             request.add_field('Content-Encoding', 'gzip')
                             Zlib.gzip(bytes)
                           else
                             bytes
                           end
            request.add_field('Content-Type', 'application/x-protobuf')
            @headers&.each { |key, value| request.add_field(key, value) }

            remaining_timeout = OpenTelemetry::Common::Utilities.maybe_timeout(timeout, start_time)
            return TIMEOUT if remaining_timeout.zero?

            @http.open_timeout = remaining_timeout
            @http.read_timeout = remaining_timeout
            @http.write_timeout = remaining_timeout if WRITE_TIMEOUT_SUPPORTED
            @http.start unless @http.started?
            response = measure_request_duration { @http.request(request) }

            case response
            when Net::HTTPOK
              response.body # Read and discard body
              SUCCESS
            when Net::HTTPServiceUnavailable, Net::HTTPTooManyRequests
              response.body # Read and discard body
              redo if backoff?(retry_after: response['Retry-After'], retry_count: retry_count += 1, reason: response.code)
              FAILURE
            when Net::HTTPRequestTimeOut, Net::HTTPGatewayTimeOut, Net::HTTPBadGateway
              response.body # Read and discard body
              redo if backoff?(retry_count: retry_count += 1, reason: response.code)
              FAILURE
            when Net::HTTPBadRequest, Net::HTTPClientError, Net::HTTPServerError
              # TODO: decode the body as a google.rpc.Status Protobuf-encoded message when https://github.com/open-telemetry/opentelemetry-collector/issues/1357 is fixed.
              response.body # Read and discard body
              FAILURE
            when Net::HTTPRedirection
              @http.finish
              handle_redirect(response['location'])
              redo if backoff?(retry_after: 0, retry_count: retry_count += 1, reason: response.code)
            else
              @http.finish
              FAILURE
            end
          rescue Net::OpenTimeout, Net::ReadTimeout
            puts "Epsagon: timeout while sending trace" if Epsagon.get_config[:debug]
            retry if backoff?(retry_count: retry_count += 1, reason: 'timeout')
            return FAILURE
          ensure
            if Epsagon.get_config[:debug] && response && response.code.to_i >= 400
              puts "Epsagon: Error while sending trace:"
              puts "#{response.code} #{response.class.name} #{response.message}"
              puts "Headers: #{response.to_hash.inspect}"
              puts response.body
            end
          end
        ensure
          # Reset timeouts to defaults for the next call.
          @http.open_timeout = @timeout
          @http.read_timeout = @timeout
          @http.write_timeout = @timeout if WRITE_TIMEOUT_SUPPORTED
        end
      end
    end
  end
end

# puts "Epsagon: timeout while sending trace" if Epsagon.get_config[:debug]
          # if Epsagon.get_config[:debug] && response && response.code >= 400
          #   puts "Epsagon: Error while sending trace:"
          #   puts "Headers: #{response.to_hash.inspect}"
          #   puts "#{response.code} #{response.class.name} #{response.message}"
          #   puts response.body
          # end
