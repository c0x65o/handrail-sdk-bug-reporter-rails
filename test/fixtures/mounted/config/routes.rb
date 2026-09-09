Rails.application.routes.draw do
  get "/fixture-session", :to => "session_fixture#show"
  mount Handrail::BugReporter::Engine => "/api/mobile-bug-reports"
end
