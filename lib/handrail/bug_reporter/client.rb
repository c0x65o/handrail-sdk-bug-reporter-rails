require "handrail/bug_reporter/transport"
require "handrail/bug_reporter/policy"
require "handrail/bug_reporter/payload"
require "handrail/bug_reporter/history"

module Handrail
  module BugReporter
    class Client
      include SafeSerialization
      attr_reader :configuration

      class SubmissionResult
        include SafeSerialization
        attr_reader :status, :status_code, :bug_id, :response

        def initialize(status, status_code = nil, response = nil)
          @status, @status_code = status, status_code
          @response = freeze_response(response)
          value = response && response["bug_id"]
          @bug_id = value.is_a?(String) && !value.strip.empty? ? value.strip.freeze : nil
          freeze
        end

        def submitted?
          status == :submitted
        end

        def inspect
          "#<Handrail::BugReporter::Client::SubmissionResult status=#{status}>"
        end
        alias_method :to_s, :inspect

        private

        def freeze_response(value)
          case value
          when Hash
            value.each { |key, child| key.freeze; freeze_response(child) }
          when Array
            value.each { |child| freeze_response(child) }
          end
          value.freeze
        end
      end

      def initialize(configuration, transport, request = nil, resolver = nil)
        @configuration, @transport = configuration, transport
        @request, @resolver = request, resolver
      end

      # Foundation for operation-specific methods. Project/environment binding is
      # authoritative configuration; payload/query builders consume these readers.
      def request(method:, endpoint: :reports, body: nil, url: nil)
        @transport.request(:method => method, :url => url || configuration.endpoints && configuration.endpoints[endpoint],
          :body => body, :session_provider => lambda { @resolver.call(@request) if @resolver })
      end

      # Permission and hooks are trusted caller options, never report fields.
      # Prepare exactly once; Transport alone owns retries and fresh sessions.
      def submit(input, redaction_hooks: [], allow_screenshots: false)
        return SubmissionResult.new(:disabled) if configuration.status == :disabled
        unless configuration.status == :ready
          raise Error.new(:invalid_configuration), :cause => nil
        end
        bytes = prepare_submission(input, redaction_hooks, allow_screenshots)
        response = request(:method => "POST", :body => bytes)
        SubmissionResult.new(:submitted, response.status_code, parse_submission_response(response))
      rescue Error => error
        if error.code == :request_failed && error.status_code
          raise Error.new(:submission_rejected, error.status_code,
            :code => error.upstream_code, :message => error.upstream_message,
            :request_id => error.request_id), :cause => nil
        end
        raise error, :cause => nil
      end

      # Owned history uses server projections; no client-side ownership cache.
      def list_bugs(options = {})
        History.list(self, options)
      end

      def get_bug(bug_id)
        History.get(self, bug_id)
      end

      def archive_bug(bug_id)
        History.change_archive_state(self, bug_id, true)
      end

      def restore_bug(bug_id)
        History.change_archive_state(self, bug_id, false)
      end

      def archive_closed_bugs
        History.archive_closed(self)
      end

      # Best effort only: discovery never changes ordinary submission state.
      # Each invocation owns its deadline and result; there is no shared cache.
      def discover_policy(timeout_ms: nil)
        return nil unless configuration.status == :ready
        @transport.with_deadline(Policy.timeout_ms(timeout_ms)) do |deadline|
          url = configuration.endpoints[:policy] + "?" + URI.encode_www_form(
            :project_id => configuration.project_id, :environment => configuration.environment)
          hydrating = @resolver.respond_to?(:call)
          resolver_failed = false
          provider = lambda do
            begin
              @resolver.call(@request) if hydrating
            rescue StandardError
              resolver_failed = true
              raise
            end
          end
          (Policy::IDENTITY_RETRY_DELAYS.length + 1).times do |attempt|
            deadline.pause(Policy::IDENTITY_RETRY_DELAYS[attempt - 1]) if attempt > 0
            begin
              response = @transport.request(:method => "GET", :url => url,
                :session_provider => provider, :deadline => deadline)
            rescue Error => error
              return nil if resolver_failed || !hydrating ||
                (error.status_code && !Transport::TRANSIENT_STATUSES.include?(error.status_code))
              next
            end
            body = JSON.parse(response.body)
            deadline.check!
            policy = Policy.parse(body, :project_id => configuration.project_id,
              :environment => configuration.environment)
            deadline.check!
            return policy if policy
            return nil unless hydrating
          end
          nil
        end
      rescue Transport::Deadline::Expired, StandardError
        nil
      end

      def inspect
        "#<Handrail::BugReporter::Client status=#{configuration.status}>"
      end
      alias_method :to_s, :inspect

      private

      def prepare_submission(input, redaction_hooks, allow_screenshots)
        Payload.new(input, :project_id => configuration.project_id,
          :environment => configuration.environment, :redaction_hooks => redaction_hooks,
          :allow_screenshots => allow_screenshots).to_json
      rescue Payload::Error => error
        raise Error.new(error.code.to_sym), :cause => nil
      rescue StandardError
        raise Error.new(:invalid_report), :cause => nil
      end

      def parse_submission_response(response)
        # Deliberately stricter than JS submit: empty, invalid or non-object JSON
        # is a malformed response, not a submitted result with a null response.
        begin
          body = response.body
          # Net::HTTP can deliver binary strings; validate JSON's UTF-8 bytes.
          body = body.dup.force_encoding(Encoding::UTF_8) if body.is_a?(String)
          parsed = JSON.parse(body) if body.is_a?(String) && body.valid_encoding?
          return parsed if parsed.is_a?(Hash)
        rescue JSON::ParserError, EncodingError, ArgumentError
          # Never retain parser messages or causes containing upstream bytes.
        end
        raise Error.new(:malformed_response, response.status_code,
          :request_id => response.request_id), :cause => nil
      end
    end

    class Factory
      include SafeSerialization
      attr_reader :configuration

      def initialize(configuration, options = {})
        @configuration = configuration
        @resolver = options[:resolve_application_session_token]
        @transport = Transport.new(configuration, options)
        freeze
      end

      def for_request(request = nil)
        Client.new(@configuration, @transport, request, @resolver)
      end

      def inspect
        "#<Handrail::BugReporter::Factory status=#{configuration.status}>"
      end
      alias_method :to_s, :inspect
    end
  end
end
