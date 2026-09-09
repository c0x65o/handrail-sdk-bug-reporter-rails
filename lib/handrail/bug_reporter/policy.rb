require "handrail/bug_reporter/configuration"

module Handrail
  module BugReporter
    # Verified, immutable policy projection. No credentials or discovery cache.
    class Policy
      include SafeSerialization
      AUTOMATION_OPTIONS = [].freeze
      ROLES = %w[requester contributor maintainer].map(&:freeze).freeze
      ACCESS_LEVELS = %w[default user full_access].map(&:freeze).freeze
      MAX_RISKS = %w[none low moderate high].map(&:freeze).freeze
      IMPACTS = %w[critical high moderate low].map(&:freeze).freeze
      IDENTITY_RETRY_DELAYS = [0.1, 0.25].freeze

      attr_reader :schema_version, :project_id, :environment, :identity_verified,
        :access_level, :role, :ask_options, :automation_policy, :reporter_notifications

      def self.timeout_ms(value)
        numeric = value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
        numeric ? [[value.round, 1].max, 30_000].min : 5000
      end

      def self.clean(value)
        return nil unless value.is_a?(String) && value.valid_encoding?
        value = value.strip
        value.empty? ? nil : value.freeze
      end

      def self.parse(body, project_id:, environment:)
        return nil unless body.is_a?(Hash)
        reporter = body["reporter"]
        return nil unless body["schema_version"] == 1 && body["project_id"] == project_id &&
          clean(body["environment"]).to_s.downcase == environment && reporter.is_a?(Hash)
        access = clean(reporter["access_level"])
        return nil unless reporter["identity_verified"] == true &&
          ACCESS_LEVELS.include?(access) && body["ask_options"].is_a?(Array)
        new(body, project_id, environment, access)
      end

      def initialize(body, project_id, environment, access)
        @schema_version, @identity_verified = 1, true
        @project_id, @environment = project_id.dup.freeze, environment.dup.freeze
        @access_level = access
        role = self.class.clean(body["reporter"]["role"])
        @role = ROLES.include?(role) ? role : nil
        @ask_options = AUTOMATION_OPTIONS
        @automation_policy = parse_automation(body["automation_policy"])
        notification = body["reporter_notifications"]
        notification = {} unless notification.is_a?(Hash)
        available = notification["available"] == true
        lifecycles = notification["lifecycles"]
        lifecycles = [] unless lifecycles.is_a?(Array)
        @reporter_notifications = {
          :available => available,
          :recipient_hint => available ? self.class.clean(notification["recipient_hint"]) : nil,
          :lifecycles => lifecycles.select { |value| value == "fixed" || value == "deployed" }.map { |value| value.dup.freeze }.freeze
        }.freeze
        freeze
      end

      def inspect
        "#<Handrail::BugReporter::Policy verified=true>"
      end
      alias_method :to_s, :inspect

      private

      def parse_automation(record)
        return nil unless record.is_a?(Hash) && record["schema_version"] == 3
        automatic = self.class.clean(record["automatic_fix_max_risk"])
        production = record["production_max_risk_by_impact"]
        return nil unless MAX_RISKS.include?(automatic) && production.is_a?(Hash)
        risks = {}
        IMPACTS.each do |impact|
          risk = self.class.clean(production[impact])
          return nil unless MAX_RISKS.include?(risk)
          risks[impact.to_sym] = risk
        end
        { :schema_version => 3, :automatic_fix_max_risk => automatic,
          :production_max_risk_by_impact => risks.freeze }.freeze
      end
    end
  end
end
