require "handrail/bug_reporter/configuration"
require "net/http"
require "openssl"
require "json"
require "timeout"

module Handrail
  module BugReporter
    class Error < StandardError
      include SafeSerialization
      attr_reader :code, :status_code, :upstream_code, :upstream_message, :request_id

      def initialize(code, status_code = nil, diagnostic = {})
        @code = code
        @status_code = status_code
        @upstream_code = diagnostic[:code]
        @upstream_message = diagnostic[:message]
        @request_id = diagnostic[:request_id]
        super(code == :invalid_configuration ? "Bug reporting is not configured." : "Bug reporting request failed.")
      end

      def inspect
        "#<Handrail::BugReporter::Error: #{message}>"
      end
    end

    class Transport
      include SafeSerialization
      TRANSIENT_STATUSES = [408, 425, 429, 500, 502, 503, 504].freeze
      NETWORK_ERRORS = [Timeout::Error, IOError, EOFError, SocketError,
        Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ECONNREFUSED,
        Errno::EPIPE, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH].freeze

      # Request-local deadline, with a real watchdog for stalled host resolvers
      # and injected HTTP boundaries, plus clock checks for deterministic tests.
      class Deadline
        # Must bypass StandardError handlers that normally swallow resolver or
        # network errors. Only the discovery caller handles this interruption.
        class Expired < Exception; end

        def initialize(milliseconds, clock, sleeper)
          @seconds, @clock, @sleeper = milliseconds / 1000.0, clock, sleeper
          @expires_at = @clock.call + @seconds
          @real_expires_at = monotonic + @seconds
        end

        def run
          Timeout.timeout(remaining, Expired) do
            result = yield self
            check!
            result
          end
        end

        def remaining
          seconds = [@expires_at - @clock.call, @real_expires_at - monotonic].min
          raise Expired unless seconds > 0
          seconds
        end
        alias_method :check!, :remaining

        def pause(seconds)
          budget = remaining
          @sleeper.call([seconds, budget].min)
          # A truncated backoff cannot permit another attempt, even if an
          # injected sleeper returns before the real watchdog has fired.
          raise Expired if seconds >= budget
          check!
        end

        private

        def monotonic
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      # Only successful body bytes are exposed for downstream operation parsing.
      # Neither response nor transport inspection prints response/request data.
      class Response
        include SafeSerialization
        attr_reader :status, :status_code, :body, :attempts, :elapsed_ms, :request_id

        def initialize(status, status_code, body, attempts, elapsed_ms, request_id = nil)
          @status, @status_code, @body = status, status_code, body && body.dup.freeze
          @attempts, @elapsed_ms = attempts, elapsed_ms
          @request_id = request_id && request_id.dup.freeze
          freeze
        end

        def inspect
          "#<Handrail::BugReporter::Transport::Response status=#{status}>"
        end
        alias_method :to_s, :inspect
      end

      # Ruby < 2.5 has a hard-coded Net::HTTP retry. Guard before reconnect/write
      # as well as setting max_retries=0 on versions that expose that setting.
      class SingleAttemptHTTP < Net::HTTP
        private

        def begin_transport(request)
          raise EOFError, "HTTP attempt already performed" if @handrail_attempt_started
          @handrail_attempt_started = true
          super
        end
      end

      # HTTP boundary: call(uri, method, headers, body, timeouts) ->
      # { :status => Integer, :headers => Hash, :body => String }.
      # Boundaries must do exactly one attempt and must never follow redirects.
      class NetHTTP
        include SafeSerialization
        def initialize(http_factory = nil)
          @http_factory = http_factory || lambda { |host, port| SingleAttemptHTTP.new(host, port, nil) }
        end

        def call(uri, method, headers, body, timeouts)
          http = @http_factory.call(uri.hostname, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.verify_hostname = true if http.respond_to?(:verify_hostname=)
          http.open_timeout = timeouts[:open_timeout]
          http.read_timeout = timeouts[:read_timeout]
          http.write_timeout = timeouts[:write_timeout] if http.respond_to?(:write_timeout=)
          http.max_retries = 0 if http.respond_to?(:max_retries=)
          request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri.request_uri, headers)
          request.body = body if body
          # Also bounds writes on old Rubies without write_timeout and slow streams.
          Timeout.timeout(timeouts[:request_timeout]) do
            http.start do |connection|
              response = connection.request(request)
              { :status => response.code.to_i, :headers => response.each_header.to_h, :body => response.body }
            end
          end
        end

        def inspect
          "#<Handrail::BugReporter::Transport::NetHTTP>"
        end
        alias_method :to_s, :inspect
      end

      def initialize(configuration, options = {})
        @configuration = configuration
        @http = options[:http] || NetHTTP.new
        @clock = options[:clock] || lambda { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @sleeper = options[:sleeper] || lambda { |seconds| sleep(seconds) }
        freeze
      end

      # URL must stay under the configured intake. No caller-provided headers.
      # Body is already serialized and is copied once, never regenerated on retry.
      def with_deadline(milliseconds, &block)
        Deadline.new(milliseconds, @clock, @sleeper).run(&block)
      end

      def request(method:, url:, body: nil, session_provider: nil, deadline: nil)
        return Response.new(:disabled, nil, nil, 0, 0) if @configuration.status == :disabled
        fail_public(:invalid_configuration) unless @configuration.status == :ready
        uri = request_uri(url)
        fail_public(:request_failed) unless ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"].include?(method)
        method = method.dup.freeze
        fail_public(:request_failed) unless body.nil? || body.is_a?(String)
        bytes = body && body.dup.freeze
        sensitive = [@configuration.send(:report_token)]
        started = @clock.call
        @configuration.max_attempts.times do |index|
          deadline.check! if deadline
          if index > 0
            delay = @configuration.retry_delay_ms * (2 ** (index - 1)) / 1000.0
            deadline ? deadline.pause(delay) : @sleeper.call(delay)
          end
          token = fresh_session_token(session_provider, deadline)
          deadline.check! if deadline
          sensitive << token if token
          headers = @configuration.send(:report_headers).merge("accept" => "application/json")
          headers["content-type"] = "application/json" if bytes
          headers["x-handrail-application-session-token"] = token if token
          response = nil
          retryable = false
          begin
            timeouts = @configuration.timeouts
            if deadline
              remaining = deadline.remaining
              timeouts = timeouts.each_with_object({}) { |(key, value), result| result[key] = [value, remaining].min }.freeze
            end
            response = @http.call(uri.dup, method, headers, bytes, timeouts)
          rescue *NETWORK_ERRORS
            retryable = true
          rescue StandardError
            # SSL verification, programming errors and protocol failures are permanent.
            retryable = false
          end
          deadline.check! if deadline
          if response
            status = response[:status]
            fail_public(:request_failed) unless status.is_a?(Integer) && status.between?(100, 599)
            if status.between?(200, 299)
              # Keep only sanitized header correlation for downstream parse errors.
              request_id = diagnostics(response.merge(:body => nil), sensitive)[:request_id]
              return Response.new(:ok, status, response[:body], index + 1, elapsed(started), request_id)
            end
            retryable = TRANSIENT_STATUSES.include?(status)
          end
          next if retryable && index + 1 < @configuration.max_attempts
          diagnostic = response ? diagnostics(response, sensitive) : {}
          fail_public(:request_failed, response && response[:status], diagnostic)
        end
      rescue Error => error
        raise error, :cause => nil
      rescue StandardError
        fail_public(:request_failed)
      end

      def inspect
        "#<Handrail::BugReporter::Transport>"
      end
      alias_method :to_s, :inspect

      private

      def fail_public(code, status = nil, diagnostic = {})
        raise Error.new(code, status, diagnostic), :cause => nil
      end

      def request_uri(url)
        uri = URI.parse(url)
        root = URI.parse(@configuration.endpoints[:reports])
        valid = uri.is_a?(URI::HTTP) && !uri.userinfo && !uri.fragment &&
          uri.scheme == root.scheme && uri.host == root.host && uri.port == root.port &&
          (uri.path == root.path || uri.path.start_with?(root.path + "/")) &&
          !(uri.path =~ /(?:\A|\/)\.{1,2}(?:\/|\z)|%(?:2e|2f|5c|00|0a|0d)|\\/i)
        fail_public(:invalid_configuration) unless valid
        uri
      end

      def fresh_session_token(provider, deadline = nil)
        return nil unless provider.respond_to?(:call)
        token = provider.call
        return nil unless token.is_a?(String) && token.valid_encoding?
        token = token.strip
        token =~ /\A[\x21-\x7e]+\z/ ? token.freeze : nil
      rescue StandardError
        raise if deadline
        nil
      end

      def elapsed(started)
        value = (@clock.call - started) * 1000.0
        value.finite? ? [[value, 0].max, 1_000_000].min : 0
      end

      def diagnostics(response, sensitive)
        body = response[:body]
        parsed = body.is_a?(String) && body.valid_encoding? && body.length <= 16_384 ? JSON.parse(body) : nil
        parsed = {} unless parsed.is_a?(Hash)
        nested = parsed["error"].is_a?(Hash) ? parsed["error"] : {}
        headers = response[:headers].is_a?(Hash) ? response[:headers] : {}
        headers = headers.each_with_object({}) { |(key, value), result| result[key.to_s.downcase] = value }
        { :code => safe_field(nested["code"] || parsed["code"], 120, sensitive, true),
          :message => safe_field(nested["message"] || (parsed["error"].is_a?(String) ? parsed["error"] : parsed["message"]), 500, sensitive),
          :request_id => safe_field(headers["x-request-id"], 200, sensitive, true) ||
            safe_field(headers["x-handrail-request-id"], 200, sensitive, true) ||
            safe_field(nested["requestId"] || nested["request_id"] || parsed["requestId"] || parsed["request_id"], 200, sensitive, true) }.freeze
      rescue JSON::ParserError, EncodingError
        # Invalid/oversized bodies must not suppress a safe header correlation ID.
        diagnostics(response.merge(:body => nil), sensitive)
      end

      def safe_field(value, limit, sensitive, identifier = false)
        return nil unless value.is_a?(String) && value.valid_encoding?
        # Redact BEFORE control-character cleanup and truncation, on every field.
        redacted = value.dup
        sensitive.compact.uniq.sort_by { |secret| -secret.length }.each do |secret|
          redacted = redacted.gsub(secret, "[REDACTED]")
        end
        redacted = redacted.gsub(/\bhbr_[A-Za-z0-9_-]+\b/, "[REDACTED]")
        redacted = redacted.gsub(/\bBearer\s+\S+/i, "Bearer [REDACTED]")
        redacted = redacted.gsub(/[\x00-\x1f\x7f]+/, " ").strip
        return nil if redacted.empty?
        return nil if identifier && !(redacted =~ /\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/)
        redacted[0, limit].freeze
      end
    end
  end
end
