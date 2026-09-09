require "logger"
require "rails"
require "action_controller/railtie"
require "sprockets/railtie" if ENV["WITH_SPROCKETS"] == "1"
require "handrail/bug_reporter"

module ReporterViewHost
  class Application < Rails::Application
    config.root = File.expand_path("..", File.dirname(__FILE__))
    config.eager_load = false
    config.cache_classes = true
    config.secret_key_base = "view-fixture-only-" * 8
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :stderr
    config.hosts.clear if config.respond_to?(:hosts)
    config.action_controller.asset_host = "https://assets.host.example"
    if ENV["WITH_SPROCKETS"] == "1"
      config.assets.compile = false
      config.assets.digest = true
      config.assets.manifest = File.expand_path("../fingerprint-manifest.json", File.dirname(__FILE__))
    end
  end
end

class ReporterViewsController < ActionController::Base
  def index
    render :inline => '<main id="host-content" class="host-theme">Host content</main><%= handrail_bug_reporter(Rails.application.config.reporter_view_options) %><button id="host-bug-button" type="button">Help</button>'
  end
end
