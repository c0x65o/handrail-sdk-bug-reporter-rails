Handrail::BugReporter::Engine.routes.draw do
  post "/", :to => "reports#create", :format => false
  get "/policy", :to => "reports#policy", :format => false
  get "/mine", :to => "reports#history", :format => false
  get "/bugs/:bug_id", :to => "reports#history", :format => false, :constraints => { :bug_id => /[^\/]+/ }
  post "/bugs/:bug_id/subscription", :to => "reports#subscription", :format => false, :constraints => { :bug_id => /[^\/]+/ }
  put "/bugs/:bug_id/archive", :to => "reports#archive", :format => false, :constraints => { :bug_id => /[^\/]+/ }
  delete "/bugs/:bug_id/archive", :to => "reports#archive", :format => false, :constraints => { :bug_id => /[^\/]+/ }
  post "/mine/archive-closed", :to => "reports#archive", :format => false
end
