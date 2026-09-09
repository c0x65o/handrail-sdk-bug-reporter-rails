require "json"

# Only the outbound HTTP service is scripted. No database or repository layer.
# Shapes copied from JS test/react-ui.test.mjs and test/reporter.test.mjs;
# runtime execution never reads the sibling checkout.
class WorkflowHTTP
  ROOT = "/api/mobile-bug-reports".freeze
  BUG_ID = "bug-canonical.123".freeze
  TIME = "2026-08-13T18:00:00.000Z".freeze
  REPORT_TOKEN = "hbr_workflow_server_only_sentinel".freeze
  SESSION_TOKEN = "workflow_application_session_server_only_sentinel".freeze

  def initialize(scenario, audit)
    @scenario, @audit = scenario, audit
    @submitted, @archived = false, false
  end

  def record(value)
    File.open(@audit, "a") { |file| file.puts(JSON.generate(value)) }
  end

  def resolve(request)
    principal = request.session[:principal]
    record(:kind => "identity", :principal => principal)
    principal == "workflow-private-principal" ? SESSION_TOKEN : nil
  end

  def bug(id = BUG_ID)
    { :id => id, :title => "Bug #{id}", :severity => "sev3", :environment => "staging",
      :status => "reported", :status_group => "in_progress", :reported_app_version => "1.2.3",
      :reported_app_flavor => nil, :reported_route => "/checkout",
      :status_rollup => { :stage => "submitted", :label => "Submitted", :terminal => false,
        :raw_status => "reported", :workflow_state => "reported", :environment => nil,
        :version => nil, :updated_at => TIME },
      :archived => @archived, :archived_at => @archived ? TIME : nil,
      :occurrence_count => 1, :reporter_occurrence_count => 1,
      :first_reported_at => TIME, :last_reported_at => TIME, :created_at => TIME,
      :updated_at => TIME, :fixed_at => nil, :closed_at => nil }
  end

  def call(uri, method, headers, bytes, _timeouts)
    body = bytes && JSON.parse(bytes)
    query = URI.decode_www_form(uri.query.to_s).to_h
    record(:kind => "http", :url => uri.to_s, :method => method, :headers => headers, :body => body)
    raise "Unexpected boundary host" unless uri.host == "handrail.invalid"
    raise "Missing server identity" unless headers["authorization"] == "Bearer #{REPORT_TOKEN}" &&
      headers["x-handrail-application-session-token"] == SESSION_TOKEN
    status = 200
    response = case [method, uri.path]
    when ["GET", ROOT + "/policy"]
      { :schema_version => 1, :project_id => "project-123", :environment => "staging",
        :reporter => { :identity_verified => true, :access_level => "user", :role => "contributor" },
        :ask_options => [], :automation_policy => { :schema_version => 3,
          :automatic_fix_max_risk => "high", :production_max_risk_by_impact => {
            :critical => "moderate", :high => "low", :moderate => "none", :low => "none" } },
        :reporter_notifications => { :available => true, :recipient_hint => "j***@example.com",
          :lifecycles => ["fixed"] } }
    when ["POST", ROOT]
      if @scenario == "lifecycle_retry" && !@failed_once
        @failed_once = true
        return { :status => 503, :body => JSON.generate(:error => "fixture_transient"), :headers => {} }
      end
      @submitted = true
      status = 201
      # An unrelated intake identifier must never become a child-route bug ID.
      { :bug_id => BUG_ID, :id => "intake-not-a-bug-id" }
    when ["POST", ROOT + "/bugs/#{BUG_ID}/subscription"]
      raise "Subscription preceded acceptance" unless @submitted
      if @scenario == "subscription_failure"
        status = 422
        { :error => "fixture_subscription_unavailable" }
      else
        { :notification_subscription => { :active => true, :created => true,
          :recipient_hint => "j***@example.com", :subscribed_at => TIME } }
      end
    when ["GET", ROOT + "/mine"]
      # The opaque cursor carries the original query, just as the upstream
      # history contract does; loadMoreBugs sends only limit + cursor.
      if query["cursor"]
        raise "Unexpected cursor" unless query["cursor"] == "opaque-page-2+cursor="
        query = query.merge("search" => "checkout", "status_group" => "in_progress",
          "sort" => "oldest", "visibility" => "active")
      end
      paged = @scenario == "history" && !@submitted && query["visibility"] != "archived"
      more = paged && !query["cursor"]
      bugs = if paged
        [bug(query["cursor"] ? "bug-page.2" : BUG_ID)]
      elsif @submitted || @archived
        [bug]
      else
        []
      end
      { :contract_version => "v1", :bugs => bugs,
        :summary => { :total => paged ? 2 : bugs.length, :needs_attention => 0,
          :in_progress => paged ? 2 : bugs.length, :closed => 0, :not_reproduced => 0 },
        :query => { :search => query["search"], :status_group => query["status_group"],
          :sort => query.fetch("sort", "newest"), :visibility => query.fetch("visibility", "active") },
        :pagination => { :limit => 1, :filtered_count => paged ? 2 : bugs.length,
          :has_more => more, :next_cursor => more ? "opaque-page-2+cursor=" : nil } }
    when ["GET", ROOT + "/bugs/#{BUG_ID}"]
      { :contract_version => "v1", :bug => bug }
    when ["PUT", ROOT + "/bugs/#{BUG_ID}/archive"], ["DELETE", ROOT + "/bugs/#{BUG_ID}/archive"]
      @archived = method == "PUT"
      { :contract_version => "v1", :bug_id => BUG_ID, :archived => @archived,
        :archived_at => @archived ? TIME : nil }
    else
      raise "Unexpected HTTP fixture request: #{method} #{uri.path}"
    end
    { :status => status, :body => JSON.generate(response), :headers => {} }
  rescue StandardError => error
    record(:kind => "fixture_error", :message => error.message)
    raise
  end
end
