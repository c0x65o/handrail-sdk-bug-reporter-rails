ReporterViewHost::Application.routes.draw do
  get "/view", :to => "reporter_views#index"
  post "/other/api/mobile-bug-reports", :to => "reporter_views#index"
  mount Handrail::BugReporter::Engine => "/feedback/api/mobile-bug-reports", :as => "reporter"
end
