require "handrail/bug_reporter/configuration"

module Handrail
  module BugReporter
    module Notification
      WARNING = "The report was sent, but update notifications could not be enabled.".freeze
      TRIM = /\A[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+\z/.freeze

      class Subscription
        include SafeSerialization
        attr_reader :active, :created, :recipient_hint, :subscribed_at

        def initialize(input)
          @active = true
          @created = input["created"].equal?(true)
          @recipient_hint = Notification.clean(input["recipient_hint"])
          @subscribed_at = Notification.clean(input["subscribed_at"])
          freeze
        end

        def inspect
          "#<Handrail::BugReporter::Notification::Subscription active=true>"
        end
        alias_method :to_s, :inspect
      end

      class << self
        # Ruby input: notification: { notify_on_resolution: true,
        # consent_version: "v1" }. String and symbol keys are interchangeable.
        # Only explicit consent counts; email and credentials are never copied.
        def preference(input)
          return nil unless input.is_a?(Hash) && read(input, "notify_on_resolution").equal?(true)
          { "notify_on_resolution" => true,
            "consent_version" => clean(read(input, "consent_version")) || "v1".freeze }.freeze
        end

        # Report acceptance precedes this boundary. Child failures never escape
        # into Client#submit's intake error mapping, or replay the parent request.
        def follow_up(client, response, preference)
          return [nil, nil] unless preference
          if response.key?("notification_subscription")
            subscription = parse(response)
          else
            segment = bug_segment(response["bug_id"])
            return [nil, WARNING] unless segment
            config = client.configuration
            url = config.endpoints[:bugs] + "/" + segment + "/subscription?" + URI.encode_www_form(
              :project_id => config.project_id, :environment => config.environment)
            result = client.request(:method => "POST", :url => url,
              :body => JSON.generate("reporter_notification" => preference))
            bytes = result.body
            bytes = bytes.dup.force_encoding(Encoding::UTF_8) if bytes.is_a?(String)
            return [nil, WARNING] unless bytes.is_a?(String) && bytes.valid_encoding?
            subscription = parse(JSON.parse(bytes))
          end
          [subscription, subscription ? nil : WARNING]
        rescue StandardError
          # Do not retain raw upstream errors, parser text or resolver causes.
          [nil, WARNING]
        end

        def clean(value)
          return nil unless value.is_a?(String) && value.valid_encoding?
          value = value.encode(Encoding::UTF_8).gsub(TRIM, "")
          value.empty? ? nil : value.freeze
        end

        private

        def read(input, key)
          input.key?(key) ? input[key] : input[key.to_sym]
        end

        def parse(response)
          input = response.is_a?(Hash) && response["notification_subscription"]
          return nil unless input.is_a?(Hash) && input["active"].equal?(true)
          Subscription.new(input)
        end

        def bug_segment(value)
          return nil unless value.is_a?(String) && value.valid_encoding?
          return nil if value.encode(Encoding::UTF_8) =~ /[\x00-\x1f\x7f]/
          id = clean(value)
          # Match owned history's path containment rules before encoding.
          return nil unless id && id != "." && id != ".." && !(id =~ /[\/\\%]/)
          URI.encode_www_form_component(id).gsub("+", "%20")
        end
      end
    end
  end
end
