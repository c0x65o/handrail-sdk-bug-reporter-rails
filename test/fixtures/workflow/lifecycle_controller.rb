# Fixture-only variants. The original workflow page remains unchanged.
class LifecycleController < WorkflowController
  def show
    session[:principal] = "workflow-private-principal"
    response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'"
    @navigation = %w[ordinary turbo turbolinks].include?(params[:navigation]) ? params[:navigation] : "ordinary"
    @variant = params[:variant]
    @loading = params[:loading]
    @options = { :endpoint => @variant == "second" ? "/alternate/api/mobile-bug-reports" : "/fixture/api/mobile-bug-reports",
      :label => @variant == "second" ? "Report from second page" : "Report a bug",
      :context => { :title => "Fixture report", :description => "Fixture details", :app_version => "2.0.0" } }
    @options[:context][:route] = "/explicit-public-route" if @variant == "explicit"
    @options.merge!(:mode => "custom-launcher", :launcher_id => "host-help") if @variant == "custom"
    @options[:enabled] = false if @variant == "disabled"
    render :inline => <<~HTML
      <!doctype html><html><head><title>Adapter fixture</title><%= csrf_meta_tags %>
      <% unless @navigation == 'ordinary' %><script src="/lifecycle/assets/<%= @navigation %>.js" defer></script><% end %>
      <% if @loading == 'initial' %><script src="/javascripts/handrail_bug_reporter.js"></script><% end %>
      <script src="/lifecycle/assets/host.js" defer></script></head>
      <body data-fixture-page="<%= @variant %>">
      <h1>Adapter <%= @variant %></h1><p id="host-content">Host content stays owned by the host.</p>
      <nav><a id="next-page" href="/lifecycle/<%= @navigation %>/second?query_sentinel=private#fragment_sentinel">Next page</a>
      <a id="first-page" href="/lifecycle/<%= @navigation %>/first">First page</a></nav>
      <% if @variant == 'custom' %><button type="button" id="host-help" class="host-style" style="color: rgb(30, 40, 50)"><span>Host Help</span></button><% end %>
      <% unless @variant == 'marker-free' %>
        <%= handrail_bug_reporter(@options).gsub(/<script.*?<\/script>/m, '').html_safe %>
      <% end %>
      <% unless %w[initial late].include?(@loading) %><script src="/javascripts/handrail_bug_reporter.js" defer></script><% end %>
      </body></html>
    HTML
  end

  # This POST itself requires the old valid token. Reset the real session token,
  # then let Rails commit the new token/session normally; no verifier bypass.
  def rotate
    reset_csrf_token(request)
    render :json => { :token => form_authenticity_token }
  end

  def asset
    paths = {
      "turbo" => "node_modules/@hotwired/turbo/dist/turbo.es2017-umd.js",
      "turbolinks" => "node_modules/turbolinks/dist/turbolinks.js",
      "host" => "test/fixtures/workflow/lifecycle_host.js"
    }
    path = paths[params[:name]]
    return head :not_found unless path
    send_file File.expand_path("../../../" + path, __dir__), :type => "application/javascript", :disposition => "inline"
  end
end
