require "json"
require "securerandom"
require "time"
require "date"
require "handrail/bug_reporter/identity"
require "handrail/bug_reporter/screenshot"
require "handrail/bug_reporter/notification"

module Handrail
  module BugReporter
    # One instance is one prepared report. Reuse it for serialization/retries.
    # Inputs and hooks use string or symbol keys; hook fields use wire names.
    class Payload
      class Error < StandardError
        attr_reader :code

        def initialize(code, message)
          @code = code.freeze
          super(message)
        end
      end

      CALLER_REPORT_FIELDS = %w[title description severity route app_version
        build_number commit_sha app_flavor reproducer metadata].map(&:freeze).freeze
      FIELD_ALIASES = {
        "app_version" => "appVersion", "build_number" => "buildNumber",
        "commit_sha" => "commitSha", "app_flavor" => "appFlavor"
      }.each { |key, value| key.freeze; value.freeze }.freeze
      IMPACTS = {
        "critical" => "critical", "sev1" => "critical",
        "high" => "high", "sev2" => "high",
        "moderate" => "moderate", "sev3" => "moderate", "medium" => "moderate",
        "low" => "low", "sev4" => "low"
      }.each { |key, value| key.freeze; value.freeze }.freeze
      REDACTED = "[REDACTED]".freeze
      OMIT = Object.new.freeze
      MAX_DEPTH = 20
      SENSITIVE_KEY = /(?:^|_)(?:authorization|proxy_authorization|bearer|cookie|set_cookie|password|passwd|passphrase|credential|credentials|secret|client_secret|private_key|api_key|access_key|profile_key|session|session_id|session_token|access_token|refresh_token|id_token|jwt|csrf|xsrf|verifier|card_number|credit_card|cvv|cvc)(?:_|$)|(?:token|secret|password|credential|private_key)$|(?:^|_)(?:private_message|direct_message|dm_content)(?:_|$)/.freeze

      def initialize(input, project_id:, environment:, redaction_hooks: [], allow_screenshots: false)
        invalid_report! unless input.is_a?(Hash)
        validate_required!(input)
        project = clean_string(project_id)
        env = clean_string(environment)
        unless project && env
          raise Error.new("invalid_configuration", "Bug reporting is not configured.")
        end
        # Capture trusted values before hooks. Never derive them from hook output.
        event = clean_string(read(input, "event_id", "eventId"))
        profile = clean_string(read(input, "profile_key", "profileKey"))
        notification = Notification.preference(read(input, "notification"))
        screenshot = read(input, "screenshot")
        attachment = screenshot.nil? ? {} : normalize_screenshot(screenshot, allow_screenshots)
        fields = {}
        CALLER_REPORT_FIELDS.each do |key|
          aliases = [key, FIELD_ALIASES[key]].compact
          fields[key] = read(input, *aliases)
        end
        impact = normalize_impact(read(input, "impact")) || normalize_impact(read(input, "severity"))
        fields["severity"] = impact
        reproducer = read(input, "reproducer")
        if js_truthy?(reproducer)
          fields["reproducer"] = reproducer
        elsif has_key?(input, "steps_to_reproduce", "stepsToReproduce", "steps")
          fields["reproducer"] = read(input, "steps_to_reproduce", "stepsToReproduce", "steps")
        else
          fields["reproducer"] = nil
        end
        fields = self.class.redact_sensitive_values(fields)
        redaction_hooks.each do |hook|
          failed = false
          begin
            fields = allowed_fields(self.class.redact_sensitive_values(hook.call(fields)))
          rescue StandardError
            failed = true
          end
          # Raise outside rescue so Ruby's implicit cause cannot expose secrets.
          raise Error.new("redaction_failed", "The bug report could not be safely prepared.") if failed
          validate_required!(fields)
        end
        validate_required!(fields)
        fields = allowed_fields(fields)
        fields["title"] = clean_string(fields["title"])
        fields["description"] = clean_string(fields["description"])
        fields["project_id"] = project
        fields["environment"] = env.downcase
        fields["event_id"] = event ? event[0, 160] : SecureRandom.uuid
        fields["profile_key"] = profile if profile
        fields["reporter_notification"] = notification if notification
        @data = deep_freeze(fields.merge(attachment).merge(Identity::SDK_IDENTITY))
        freeze
      end

      def to_h
        @data
      end

      def as_json(_options = nil)
        @data
      end

      def to_json(*args)
        @data.to_json(*args)
      end

      def self.redact_sensitive_values(input)
        normalized = json_value(input, {}, 0)
        normalized.is_a?(Hash) ? normalized : {}
      end

      def self.json_value(input, seen, depth)
        case input
        when nil, true, false, Integer
          return input
        when String
          return input.dup
        when Float
          return input.finite? ? input : nil
        when Time, DateTime
          return input.to_time.utc.iso8601(3)
        when Date
          return Time.utc(input.year, input.month, input.day).iso8601(3)
        end
        return OMIT unless input.is_a?(Hash) || input.is_a?(Array)
        return "[Circular]" if depth >= MAX_DEPTH || seen[input.object_id]
        seen[input.object_id] = true
        begin
          if input.is_a?(Array)
            return input.each_with_object([]) do |value, output|
              normalized = json_value(value, seen, depth + 1)
              output << normalized unless normalized.equal?(OMIT)
            end
          end
          input.each_with_object({}) do |(raw_key, value), output|
            next unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            key = raw_key.to_s[0, 200]
            next if key.empty? || %w[__proto__ prototype constructor].include?(key)
            normalized_key = key.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase.gsub(/[^a-z0-9]+/, "_")
            normalized = normalized_key =~ SENSITIVE_KEY ? REDACTED : json_value(value, seen, depth + 1)
            output[key] = normalized unless normalized.equal?(OMIT)
          end
        ensure
          seen.delete(input.object_id)
        end
      end
      private_class_method :json_value

      private

      def normalize_screenshot(screenshot, allow_screenshots)
        begin
          return Screenshot.normalize(screenshot, :allow_screenshots => allow_screenshots)
        rescue Screenshot::Error
          # Expose the same error type as other payload validation failures.
        end
        raise Error.new("invalid_screenshot", Screenshot::ERROR_MESSAGE), cause: nil
      end

      def read(hash, *keys)
        keys.each do |key|
          return hash[key] if hash.key?(key)
          return hash[key.to_sym] if hash.key?(key.to_sym)
        end
        nil
      end

      def has_key?(hash, *keys)
        keys.any? { |key| hash.key?(key) || hash.key?(key.to_sym) }
      end

      def clean_string(value)
        return nil unless value.is_a?(String) && value.valid_encoding?
        # ECMAScript trim whitespace, including NBSP and BOM (Ruby strip differs).
        cleaned = value.gsub(/\A[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+\z/, "")
        cleaned.empty? ? nil : cleaned
      end

      def js_truthy?(value)
        !(value.nil? || value == false || value == "" || value == 0 || (value.is_a?(Float) && value.nan?))
      end

      def normalize_impact(value)
        cleaned = clean_string(value)
        cleaned && IMPACTS[cleaned.downcase]
      end

      def validate_required!(fields)
        invalid_report! unless clean_string(read(fields, "title")) && clean_string(read(fields, "description"))
      end

      def invalid_report!
        raise Error.new("invalid_report", "A report title and description are required.")
      end

      def allowed_fields(fields)
        fields.each_with_object({}) do |(key, value), allowed|
          allowed[key] = value if CALLER_REPORT_FIELDS.include?(key)
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| key.freeze; deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end
    end
  end
end
