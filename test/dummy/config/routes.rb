Rails.application.routes.draw do
  get "/fixture-session", :to => "compatibility_session#show"
  mount Handrail::BugReporter::Engine => "/api/mobile-bug-reports"
end
