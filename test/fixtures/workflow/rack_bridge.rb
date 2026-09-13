# Execute the actual workflow host over stdin/stdout, without a socket/browser.
# Only outbound HTTP is faked; this is supplemental to rendered browser QA.
ENV["RAILS_ENV"] = ENV["RACK_ENV"] = "test"
require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../../../lib", __dir__))
require_relative "../../support/no_network"
require "rack/mock"
require "tempfile"
require_relative "config/application"
require_relative "factory"

audit = Tempfile.new("workflow-audit", ENV.fetch("TMPDIR"))
Rails.application.config.handrail_bug_reporter_factory = WorkflowFactory.build(ARGV.fetch(0), audit.path)
Rails.application.initialize!
$stdout.sync = true
begin
  STDIN.each_line do |line|
    input = JSON.parse(line)
    env = Rack::MockRequest.env_for("http://127.0.0.1" + input.fetch("path"),
      :method => input.fetch("method"), :input => input.fetch("body", ""))
    env["HTTP_HOST"] = "127.0.0.1"
    input.fetch("headers", {}).each do |key, value|
      name = key.upcase.tr("-", "_")
      env[name == "CONTENT_TYPE" ? name : "HTTP_" + name] = value
    end
    status, headers, response = Rails.application.call(env)
    body = ""
    response.each { |part| body << part }
    response.close if response.respond_to?(:close)
    rows = File.readlines(audit.path).map { |row| JSON.parse(row) }
    puts JSON.generate(:status => status, :headers => headers, :body => body, :audit => rows)
  end
ensure
  audit.close!
end
