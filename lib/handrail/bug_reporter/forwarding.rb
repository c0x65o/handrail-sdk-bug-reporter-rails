require "handrail/bug_reporter/client"
require "handrail/bug_reporter/payload"

module Handrail
  module BugReporter
    # For already-normalized browser wire objects. This never calls Client#submit
    # or Payload.new: browser identity/event IDs and subscription ownership survive.
    class Forwarding
      AUTH_KEY = /(?:\A|_)(?:auth|authentication|authorization|proxy_authorization|bearer|cookie|set_cookie|session|report_token|access_token|refresh_token|id_token|jwt|csrf|xsrf|authenticity_token)(?:_|$)/.freeze

      def initialize(factory, request)
        @configuration = factory.configuration
        @client = factory.for_request(request)
      end

      def submit(input)
        body = remove_server_fields(Payload.redact_sensitive_values(input))
        profile = clean(input["profile_key"])
        body["profile_key"] = profile if profile
        body["project_id"] = @configuration.project_id
        body["environment"] = @configuration.environment
        preference = body.delete("reporter_notification")
        if preference.is_a?(Hash) && preference["notify_on_resolution"] == true
          body["reporter_notification"] = {
            "notify_on_resolution" => true,
            "consent_version" => clean(preference["consent_version"]) || "v1"
          }
        end
        @client.request(:method => "POST", :body => JSON.generate(body))
      end

      def subscription(input, resource)
        preference = input.is_a?(Hash) && input["reporter_notification"]
        unless preference.is_a?(Hash) && preference["notify_on_resolution"] == true
          raise Error.new(:invalid_subscription), :cause => nil
        end
        body = { "reporter_notification" => {
          "notify_on_resolution" => true,
          "consent_version" => clean(preference["consent_version"]) || "v1"
        } }
        query = URI.encode_www_form("project_id" => @configuration.project_id,
          "environment" => @configuration.environment)
        # The guard supplies the validated, encoded child resource. The request
        # boundary refreshes host identity on every attempt without parent intake.
        @client.request(:method => "POST", :endpoint => :bugs, :body => JSON.generate(body),
          :url => @configuration.endpoints[:bugs] + resource.fetch(1) + "?" + query)
      end

      def policy
        query = URI.encode_www_form("project_id" => @configuration.project_id,
          "environment" => @configuration.environment)
        @client.request(:method => "GET", :endpoint => :policy,
          :url => @configuration.endpoints[:policy] + "?" + query)
      end

      def history(method, resource, query)
        endpoint, suffix = resource
        scope = query.merge("project_id" => @configuration.project_id,
          "environment" => @configuration.environment)
        @client.request(:method => method, :endpoint => endpoint,
          :url => @configuration.endpoints.fetch(endpoint) + suffix + "?" + URI.encode_www_form(scope))
      end

      private

      def clean(value)
        return nil unless value.is_a?(String)
        # ECMAScript trim semantics, shared by the browser forwarding reference.
        value = value.gsub(/\A[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+\z/, "")
        value.empty? ? nil : value
      end

      def remove_server_fields(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), result|
            normalized = key.gsub(/([a-z0-9])([A-Z])/, '\1_\2').downcase.gsub(/[^a-z0-9]+/, "_")
            next if normalized == "automation_requests" || normalized =~ AUTH_KEY
            result[key] = remove_server_fields(child)
          end
        when Array
          value.map { |child| remove_server_fields(child) }
        else
          value
        end
      end
    end
  end
end
