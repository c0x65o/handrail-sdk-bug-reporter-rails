require_relative "../lifecycle_controller"
Rails.application.routes.draw do
  root :to => "workflow#show"
  get "/javascripts/handrail_bug_reporter.js", :to => "workflow#asset"
  get "/lifecycle/assets/:name.js", :to => "lifecycle#asset"
  post "/lifecycle/rotate", :to => "lifecycle#rotate"
  get "/lifecycle/:navigation/:variant", :to => "lifecycle#show"
  mount Handrail::BugReporter::Engine => "/fixture/api/mobile-bug-reports"
  mount Handrail::BugReporter::Engine => "/alternate/api/mobile-bug-reports", :as => "alternate_reporter"
end
