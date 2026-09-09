require "logger"
require "rails/engine"
require "action_dispatch"
require "handrail/bug_reporter/forwarding_guard"

module Handrail
  module BugReporter
    class Engine < ::Rails::Engine
      isolate_namespace Handrail::BugReporter

      initializer "handrail.bug_reporter.view_helper" do
        require_relative "../../../app/helpers/handrail/bug_reporter_helper"
        ActiveSupport.on_load(:action_controller) do
          helper Handrail::BugReporterHelper
        end
      end

      initializer "handrail.bug_reporter.assets" do |app|
        if app.config.respond_to?(:assets) && app.config.assets.respond_to?(:precompile)
          app.config.assets.precompile += ["handrail_bug_reporter.js"]
        end
      end

      # Runs only inside an explicit host mount, before controller instrumentation
      # or CSRF verification can trigger Rails' JSON parameter parser.
      middleware.use Handrail::BugReporter::ForwardingGuard
    end
  end
end
