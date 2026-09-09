Rails.application.routes.draw do
  get "/health", :to => lambda { |env|
    [200, { "content-type" => "text/html" }, ["<p>host only</p>"]]
  }
end
