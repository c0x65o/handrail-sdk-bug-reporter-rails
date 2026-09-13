ENV["RAILS_ENV"] = ENV["RACK_ENV"] = "test"
require "bundler/setup"
require "rackup/handler/webrick"
$LOAD_PATH.unshift(File.expand_path("../../../lib", __dir__))
require_relative "config/application"
require_relative "http_boundary"
# The server only listens on loopback; any outbound socket/Net::HTTP attempt
# fails even if a future change accidentally bypasses the injected boundary.
require_relative "../../support/no_network"

require_relative "factory"
Rails.application.config.handrail_bug_reporter_factory = WorkflowFactory.build(
  ENV.fetch("WORKFLOW_SCENARIO"), ENV.fetch("WORKFLOW_AUDIT"))
Rails.application.initialize!
$stdout.sync = true
Rackup::Handler::WEBrick.run(Rails.application, :Host => "127.0.0.1", :Port => 0,
  :AccessLog => [], :Logger => WEBrick::Log.new($stderr, WEBrick::Log::WARN)) do |server|
  Signal.trap("TERM") { server.shutdown }
  Signal.trap("INT") { server.shutdown }
  puts JSON.generate(:ready => true, :port => server.listeners.first.addr[1],
    :ruby => RUBY_VERSION, :rails => Rails.version, :rack => Rack.release,
    :webrick => WEBrick::VERSION, :bundler => Bundler::VERSION)
end
