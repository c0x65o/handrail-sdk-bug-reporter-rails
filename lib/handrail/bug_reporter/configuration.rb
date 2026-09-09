require "uri"
require "json"

module Handrail
  module BugReporter
    # ActiveSupport's default Object#as_json walks instance variables. Structured
    # logging must be as safe as inspect, even after a Rails host loads it.
    module SafeSerialization
      def as_json(*_args)
        inspect
      end

      def to_json(*args)
        as_json.to_json(*args)
      end
    end

    # Immutable server configuration. Never store a request or resolved session here.
    class Configuration
      include SafeSerialization
      attr_reader :enabled, :status, :endpoints, :project_id, :environment,
        :max_attempts, :retry_delay_ms, :timeouts

      def initialize(options = {})
        @enabled = options[:enabled] != false
        @project_id = clean(options[:project_id])
        @environment = clean(options[:environment])
        @environment = @environment.downcase.freeze if @environment
        @report_token = header_token(options[:report_token])
        @report_token_header = options.fetch(:report_token_header, "authorization").to_s.dup.freeze
        @endpoints = normalize_endpoints(options[:api_base_url])
        attempts = options[:max_attempts]
        @max_attempts = finite_number?(attempts) && attempts == attempts.to_i ? [[attempts.to_i, 1].max, 3].min : 1
        @retry_delay_ms = bounded(options[:retry_delay_ms], 250, 0, 30_000)
        @timeouts = {
          :open_timeout => bounded(options[:open_timeout], 5, 0.001, 60),
          :read_timeout => bounded(options[:read_timeout], 10, 0.001, 60),
          :write_timeout => bounded(options[:write_timeout], 10, 0.001, 60),
          :request_timeout => bounded(options[:request_timeout], 30, 0.001, 120)
        }.freeze
        ready = @endpoints && @project_id && @environment && @report_token &&
          ["authorization", "x-handrail-bug-report-token"].include?(@report_token_header)
        @status = !@enabled ? :disabled : (ready ? :ready : :misconfigured)
        freeze
      end

      def snapshot
        { :enabled => enabled, :status => status, :max_attempts => max_attempts,
          :retry_delay_ms => retry_delay_ms, :timeouts => timeouts,
          :has_report_token => !@report_token.nil? }.freeze
      end

      def inspect
        "#<Handrail::BugReporter::Configuration status=#{status}>"
      end
      alias_method :to_s, :inspect

      private

      def clean(value)
        return nil unless value.is_a?(String) && value.valid_encoding?
        value = value.strip
        value.empty? ? nil : value.freeze
      end

      def header_token(value)
        value = clean(value)
        value && value =~ /\A[\x21-\x7e]+\z/ ? value : nil
      end

      def bounded(value, fallback, minimum, maximum)
        finite_number?(value) ? [[value, minimum].max, maximum].min : fallback
      end

      def finite_number?(value)
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      end

      def normalize_endpoints(value)
        input = clean(value)
        return nil unless input && input =~ /\Ahttps?:\/\//i
        return nil if input =~ /[\s\\?#]/
        uri = URI.parse(input)
        return nil unless uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty? &&
          !uri.userinfo && uri.port.between?(1, 65_535)
        path = uri.path.gsub(/\/+/, "/").sub(/\/+\z/, "")
        # Avoid server/proxy disagreement about path traversal and encoded separators.
        return nil if path =~ /(?:\A|\/)\.{1,2}(?:\/|\z)|%(?:2e|2f|5c|00|0a|0d)/i
        unless path.end_with?("/api/mobile-bug-reports")
          path += path.end_with?("/api") ? "/mobile-bug-reports" : "/api/mobile-bug-reports"
        end
        uri.host = uri.host.downcase
        uri.path = path
        reports = uri.to_s.freeze
        { :reports => reports, :policy => (reports + "/policy").freeze,
          :mine => (reports + "/mine").freeze, :history => (reports + "/mine").freeze,
          :bugs => (reports + "/bugs").freeze }.freeze
      rescue URI::Error, ArgumentError
        nil
      end

      # Only the transport uses these credentials; they are absent from snapshots.
      def report_token
        @report_token
      end

      def report_headers
        if @report_token_header == "x-handrail-bug-report-token"
          { "x-handrail-bug-report-token" => @report_token }
        else
          { "authorization" => "Bearer #{@report_token}" }
        end
      end
    end
  end
end
