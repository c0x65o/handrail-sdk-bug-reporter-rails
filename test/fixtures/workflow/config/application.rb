require "logger"
require "rails"
require "action_controller/railtie"
require "handrail/bug_reporter"
require_relative "../../../../app/helpers/handrail/bug_reporter_helper"

module WorkflowHost
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.cache_classes = true
    config.secret_key_base = "workflow-cookie-signing-sentinel-" * 8
    config.logger = Logger.new($stderr)
    config.log_level = :warn
    config.hosts = ["127.0.0.1"]
    config.session_store :cookie_store, :key => "_workflow_host", :httponly => true
    config.action_controller.allow_forgery_protection = true
  end
end

class WorkflowController < ActionController::Base
  protect_from_forgery :with => :exception, :except => :asset
  helper Handrail::BugReporterHelper

  def show
    # Fixture authentication stands for an already signed-in host user. Only the
    # resolver translates this encrypted cookie principal to a Handrail token.
    session[:principal] = "workflow-private-principal"
    response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'"
    render :inline => <<~HTML
      <!doctype html><html><head><title>Rails workflow fixture</title>
      <%= csrf_meta_tags %></head><body>
      <%= handrail_bug_reporter :endpoint => '/fixture/api/mobile-bug-reports',
        :allow_screenshots => true, :history_page_size => 1,
        :context => { :route => '/checkout', :app_version => '1.2.3' } %>
      </body></html>
    HTML
  end

  def asset
    send_file File.expand_path("../../../../app/assets/javascripts/handrail_bug_reporter.js", __dir__),
      :type => "application/javascript", :disposition => "inline"
  end
end
