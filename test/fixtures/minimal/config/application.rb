require "logger"
require "rails"
require "action_controller/railtie"

require "handrail/bug_reporter" if ENV["WITH_HANDRAIL"] == "1"

module ScaffoldHost
  class Application < Rails::Application
    config.load_defaults ENV["HANDRAIL_TEST_RAILS_DEFAULTS"] unless ENV["HANDRAIL_TEST_RAILS_DEFAULTS"].to_s.empty?
    config.root = File.expand_path("..", File.dirname(__FILE__))
    config.eager_load = false
    config.cache_classes = true
    config.secret_key_base = "scaffold-test-only-" * 8
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :stderr
    config.hosts.clear if config.respond_to?(:hosts)
  end
end
