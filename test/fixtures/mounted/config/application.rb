require "logger"
require "rails"
require "action_controller/railtie"
require "handrail/bug_reporter"

module MountedHost
  class Application < Rails::Application
    config.root = File.expand_path("..", File.dirname(__FILE__))
    config.eager_load = false
    config.cache_classes = true
    config.secret_key_base = "mounted-fixture-only-" * 8
    config.logger = Logger.new(nil)
    config.active_support.deprecation = :stderr
    config.hosts.clear if config.respond_to?(:hosts)
    config.session_store :cookie_store, :key => "_mounted_host", :httponly => true
    # The engine must enforce its verifier even when the host's test default is off.
    config.action_controller.allow_forgery_protection = false
  end
end

class SessionFixtureController < ActionController::Base
  def show
    # Represents an existing host-authenticated principal; the SDK never signs in
    # a user or chooses session credentials from headers/JSON.
    session[:principal] = "fixture-principal"
    render :json => { :csrf => form_authenticity_token }
  end
end
