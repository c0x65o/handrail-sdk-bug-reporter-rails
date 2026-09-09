require "bundler/setup"
require "json"
require "rack/mock"
require_relative "../support/no_network"
require_relative "../fixtures/views/config/application"

# Reuse the real Engine routes, controller/view and helper from rendering_checks.
ReporterViewHost::Application.initialize!
ActionController::Base.asset_host = nil
configuration = Handrail::BugReporter::Configuration.new(
  :api_base_url => "https://unused.invalid", :project_id => "style-project",
  :environment => "staging", :report_token => "fixture-never-serialized")
Rails.application.config.handrail_bug_reporter_factory = Handrail::BugReporter::Factory.new(
  configuration, :http => lambda { |*args| raise "Unexpected helper transport" },
  :resolve_application_session_token => lambda { |*args| raise "Unexpected helper credentials" })

pages = JSON.parse(STDIN.read, :symbolize_names => true).map do |options|
  Rails.application.config.reporter_view_options = options
  response = Rack::MockRequest.new(Rails.application).get("/view")
  raise "Helper rendering failed: #{response.status}: #{response.body}" unless response.status == 200
  response.body
end
STDOUT.write(JSON.generate(:rails_version => Rails.version, :pages => pages))
