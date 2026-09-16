require "logger"
require "rails"
require "action_controller/railtie"
require "handrail/bug_reporter"
require_relative "../../../../app/helpers/handrail/bug_reporter_helper"

module WorkflowHost
  class Application < Rails::Application
    config.load_defaults ENV["HANDRAIL_TEST_RAILS_DEFAULTS"] unless ENV["HANDRAIL_TEST_RAILS_DEFAULTS"].to_s.empty?
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.cache_classes = true
    config.secret_key_base = "workflow-cookie-signing-sentinel-" * 8
    config.logger = Logger.new($stderr)
    config.log_level = :warn
    config.hosts = ["127.0.0.1"]
    config.session_store :cookie_store, :key => "_workflow_host", :httponly => true
    config.action_controller.allow_forgery_protection = true
    # This fixture defines controllers before boot. Apply its explicit policy
    # after Rails installs the load_defaults CSRF callbacks on the base class.
    config.after_initialize do
      WorkflowController.protect_from_forgery :with => :exception, :except => :asset
      WorkflowController.skip_forgery_protection :only => :asset
    end
  end
end

class WorkflowController < ActionController::Base
  helper Handrail::BugReporterHelper

  def show
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

  # Test-only session transition, protected by real Rails CSRF. No QA accounts.
  def change_session
    state = params[:state]
    return head :bad_request unless %w[admin nonadmin anonymous revoked].include?(state)
    session[:role] = state
    session[:principal] = state == "anonymous" ? nil : "workflow-private-principal"
    render :json => { :state => state }
  end

  def asset
    send_file File.expand_path("../../../../app/assets/javascripts/handrail_bug_reporter.js", __dir__),
      :type => "application/javascript", :disposition => "inline"
  end
end
