require_relative "http_boundary"

module WorkflowFactory
  def self.build(scenario, audit)
    unless %w[submission subscription_failure subscription_empty accepted_malformed accepted_empty history lifecycle_retry].include?(scenario)
      raise ArgumentError, "Unknown workflow scenario"
    end
    boundary = WorkflowHTTP.new(scenario, audit)
    configuration = Handrail::BugReporter::Configuration.new(
      :api_base_url => "https://handrail.invalid/api", :project_id => "project-123",
      :environment => " StAgInG ", :report_token => WorkflowHTTP::REPORT_TOKEN, :max_attempts => 1)
    Handrail::BugReporter::Factory.new(configuration, :http => boundary,
      :authorize_request => boundary.method(:authorize),
      :resolve_application_session_token => boundary.method(:resolve))
  end
end
