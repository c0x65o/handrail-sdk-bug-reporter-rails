require "logger"
require "rails"
require "action_controller/railtie"
require "sprockets/railtie"
require "handrail/bug_reporter"

module CompatibilityHost
  class Application < Rails::Application
    config.root = File.expand_path("..", File.dirname(__FILE__))
    config.eager_load = false
    config.cache_classes = true
    config.secret_key_base = "compatibility-fixture-only-" * 8
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :stderr
    config.hosts.clear if config.respond_to?(:hosts)
    config.session_store :cookie_store, :key => "_compatibility_host", :httponly => true
    # Prove the SDK uses Rails' real verifier even with host test defaults off.
    config.action_controller.allow_forgery_protection = false
    config.assets.enabled = true
    config.assets.version = "1"
    config.assets.js_compressor = nil
    config.assets.css_compressor = nil
  end
end

class CompatibilitySessionController < ActionController::Base
  def show
    session[:principal] = "fixture-principal"
    render :json => { :csrf => form_authenticity_token }
  end
end
