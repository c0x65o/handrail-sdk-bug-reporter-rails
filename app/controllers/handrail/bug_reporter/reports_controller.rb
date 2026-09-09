require "action_controller/base"
require "handrail/bug_reporter/forwarding"

module Handrail
  module BugReporter
    class ReportsController < ActionController::Base
      protect_from_forgery :with => :exception, :only => [:create, :archive, :subscription]
      rescue_from ActionController::InvalidAuthenticityToken do
        render_error(403, "invalid_authenticity_token")
      end

      def create
        forward { |service| service.submit(request.env.fetch(ForwardingGuard::PAYLOAD_KEY)) }
      end

      def policy
        forward { |service| service.policy }
      end

      def subscription
        forward(:subscription) do |service|
          service.subscription(request.env.fetch(ForwardingGuard::PAYLOAD_KEY),
            request.env.fetch(ForwardingGuard::RESOURCE_KEY))
        end
      end

      def history
        forward(true) do |service|
          service.history(request.request_method, request.env.fetch(ForwardingGuard::RESOURCE_KEY),
            request.env.fetch(ForwardingGuard::QUERY_KEY))
        end
      end

      def archive
        history
      end

      private

      # Keep verification mandatory even when a host disables its own CSRF checks
      # (e.g. an API controller or a test environment). Use Rails' real verifier.
      def protect_against_forgery?
        true
      end

      def forward(ownership_status = false)
        config = Rails.application.config
        factory = config.handrail_bug_reporter_factory if config.respond_to?(:handrail_bug_reporter_factory)
        return render_error(503, "bug_reporting_unavailable") unless factory.is_a?(Factory)
        return render_error(404, "bug_reporting_disabled") if factory.configuration.status == :disabled
        return render_error(503, "bug_reporting_unavailable") unless factory.configuration.status == :ready
        response = yield Forwarding.new(factory, request)
        return render_subscription(response) if ownership_status == :subscription
        body = JSON.parse(response.body)
        # Validate JSON, then preserve history wire bytes (including future
        # versioned fields and numeric precision) for the browser parser.
        render :json => (ownership_status ? response.body : body), :status => response.status_code
      rescue Error => error
        if ownership_status == :subscription
          return render_error(400, "invalid_report") if error.code == :invalid_subscription
          status = error.status_code || 502
          log_subscription_failure(error.status_code ? "upstream_rejected" : "upstream_unavailable", status)
          return render_error(status, error.status_code ? "bug_reporting_rejected" : "bug_reporting_unavailable")
        end
        # Match the JS forwarding error contract without exposing upstream
        # diagnostics or changing the public Ruby client's exception behavior.
        if ownership_status && [401, 403].include?(error.status_code)
          render_error(error.status_code, "bug_reporting_rejected")
        else
          render_error(502, "bug_reporter_upstream_failed")
        end
      rescue JSON::ParserError, TypeError
        render_error(502, "bug_reporter_upstream_failed")
      end

      def render_error(status, code)
        render :json => { :error => code }, :status => status
      end

      def render_subscription(response)
        bytes = response.body
        bytes = bytes.dup.force_encoding(Encoding::UTF_8) if bytes.is_a?(String)
        raise TypeError unless bytes.is_a?(String) && bytes.valid_encoding?
        JSON.parse(bytes)
        render :json => bytes, :status => response.status_code
      rescue JSON::ParserError, TypeError, EncodingError, ArgumentError
        log_subscription_failure("response_unreadable", 502)
        render_error(502, "bug_reporting_unavailable")
      end

      def log_subscription_failure(stage, status)
        # Do not include arbitrary IDs, error diagnostics or credentials. The
        # shared transport does not expose failed attempt counts or identity
        # checkpoints, so do not guess them from configuration.
        logger.error(JSON.generate(:schema_version => 1,
          :component => "handrail_bug_reporter_proxy", :event => "bug_notification.forward_failed",
          :stage => stage, :status => status, :consent_validated => true,
          :upstream_response_received => stage != "upstream_unavailable")) if logger
      rescue StandardError
        # Host telemetry must never change the child-route result.
        nil
      end
    end
  end
end
