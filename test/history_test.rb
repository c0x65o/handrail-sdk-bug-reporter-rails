require "minitest/autorun"
require "handrail/bug_reporter/client"
require_relative "support/no_network"

class HistoryTest < Minitest::Test
  SDK = Handrail::BugReporter
  # Exact trackedBug()/resolutionJourney() fixtures from JS v0.4.49,
  # test/reporter.test.mjs at 96b293248611594c388d0fab3af63b1b2d1aae5c.
  FIXTURE = File.read(File.expand_path("fixtures/js_v0.4.49_history.json", File.dirname(__FILE__))).freeze
  TOKEN = "hbr_history_report_secret"
  SESSION = "history-session-secret"

  def setup
    @calls = []
    @body = page
    @status = 200
    @headers = { "x-request-id" => "history-request-1" }
  end

  def fixture
    JSON.parse(FIXTURE)
  end

  def bug
    fixture["bug"]
  end

  def journey
    fixture["journey"]
  end

  def page
    { "contract_version" => "v1", "bugs" => [bug],
      "summary" => { "total" => 3, "needs_attention" => 1, "in_progress" => 2, "closed" => 0, "not_reproduced" => 0 },
      "query" => { "search" => "checkout", "status_group" => "in_progress", "sort" => "oldest", "visibility" => "active" },
      "pagination" => { "limit" => 10, "filtered_count" => 2, "has_more" => true, "next_cursor" => "opaque-page-2" } }
  end

  def configuration(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/prefix/api",
      :project_id => " project-123 ", :environment => " StAgInG ", :report_token => TOKEN }.merge(options))
  end

  def client(config = configuration, options = {})
    http = lambda do |*args|
      @calls << args
      { :status => @status, :body => JSON.generate(@body), :headers => @headers }
    end
    SDK::Factory.new(config, { :http => http,
      :resolve_application_session_token => lambda { |_| SESSION } }.merge(options)).for_request(:host_request)
  end

  def detail(record = bug)
    { "contract_version" => "v1", "bug" => record }
  end

  def assert_rejected
    error = assert_raises(SDK::Error) { yield }
    assert_equal :tracking_rejected, error.code
    assert_nil error.cause
    error
  end

  def assert_frozen_tree(value)
    assert value.frozen?
    case value
    when Hash then value.each { |key, child| assert_frozen_tree(key); assert_frozen_tree(child) }
    when Array then value.each { |child| assert_frozen_tree(child) }
    end
  end

  def test_owned_page_and_detail_preserve_server_metadata_and_freeze_projections
    @body["bugs"][0].merge!("status_group" => "in_progress", "reported_app_version" => "2.24.1",
      "reported_route" => "/checkout", "reported_app_flavor" => "web", "resolution_journey" => journey)
    result = client.list_bugs
    record = result[:bugs][0]
    assert_equal "bug-123", record[:id]
    assert_equal "high", record[:impact]
    assert_equal "sev2", record[:severity]
    assert_equal "fixing", record[:status_rollup][:stage]
    assert_equal "in_progress", record[:status_group]
    assert_equal 3, record[:occurrence_count]
    assert_equal 2, record[:reporter_occurrence_count]
    assert_equal "2.24.1", record[:reported_app_version]
    assert_equal "/checkout", record[:reported_route]
    assert_equal "web", record[:reported_app_flavor]
    assert_equal "2026-08-13T18:00:00.000Z", record[:last_reported_at]
    assert_equal({ :search => "checkout", :status_group => "in_progress", :sort => "oldest", :visibility => "active" }, result[:query])
    assert_equal 3, result[:summary][:total]
    assert_equal 2, result[:pagination][:filtered_count]
    assert_frozen_tree(result)
    @body = detail(@body["bugs"][0])
    assert_equal record, client.get_bug("bug-123")
    @body["bug"]["title"].replace("Changed after parse")
    assert_equal "Checkout failure", record[:title]
  end

  def test_encoded_query_and_cursor_round_trip_with_configuration_authority
    cursor = "opaque+/= ?&%#雪"
    @body["pagination"]["next_cursor"] = cursor
    config = configuration(:project_id => " project &+/雪 ", :environment => " STAGING &+ ")
    reporter = client(config)
    first = reporter.list_bugs(:limit => 10, :cursor => cursor, :search => " \ufeffa+b %_?&雪 \u00a0",
      :status_group => "in_progress", :sort => "oldest", :visibility => "archived",
      :project_id => "attacker", "environment" => "production", :url => "https://evil.example",
      :headers => { "authorization" => "attacker" }, :profile_key => "someone-else")
    reporter.list_bugs("cursor" => first[:pagination][:next_cursor])
    uri, method, headers, body = @calls[0]
    assert_equal "/prefix/api/mobile-bug-reports/mine", uri.path
    assert_equal "GET", method
    assert_nil body
    assert_equal "Bearer #{TOKEN}", headers["authorization"]
    assert_equal "project_id=project+%26%2B%2F%E9%9B%AA&environment=staging+%26%2B&limit=10&cursor=opaque%2B%2F%3D+%3F%26%25%23%E9%9B%AA&search=a%2Bb+%25_%3F%26%E9%9B%AA&status_group=in_progress&sort=oldest&visibility=archived", uri.query
    assert_equal cursor, URI.decode_www_form(@calls[1][0].query).to_h["cursor"]
    @body = detail
    reporter.get_bug("bug-123")
    assert_equal({ "project_id" => config.project_id, "environment" => config.environment }, URI.decode_www_form(@calls.last[0].query).to_h)
  end

  def test_blank_search_is_omitted_and_js_utf16_search_bound_is_enforced
    [nil, "", " \t\n", "\ufeff\u00a0\u3000"].each do |search|
      client.list_bugs(:search => search, :sort => "", :visibility => nil, :cursor => "")
      assert_equal %w[project_id environment], URI.decode_www_form(@calls.last[0].query).map(&:first)
    end
    ["x" * 200, "😀" * 100].each { |search| client.list_bugs(:search => search) }
    ["x" * 201, "😀" * 101, true, false, 1, [], {}, "\xff".dup.force_encoding("UTF-8")].each do |search|
      count = @calls.length
      assert_rejected { client.list_bugs(:search => search) }
      assert_equal count, @calls.length
    end
  end

  def test_list_option_validation_and_allowlists
    { :status_group => %w[needs_attention in_progress closed not_reproduced],
      :sort => %w[newest oldest], :visibility => %w[active archived all] }.each do |key, values|
      values.each do |value|
        client.list_bugs(key => value)
        assert_equal value, URI.decode_www_form(@calls.last[0].query).to_h[key.to_s]
      end
      ["unknown", " #{values[0]} ", 1, true, [], {}].each do |value|
        count = @calls.length
        assert_rejected { client.list_bugs(key => value) }
        assert_equal count, @calls.length
      end
    end
    ["20", true, [], Float::INFINITY, Float::NAN].each do |limit|
      assert_rejected { client.list_bugs(:limit => limit) }
    end
    [1, 50, 20.0, 100].each do |limit|
      client.list_bugs(:limit => limit)
      assert_equal limit.to_s, URI.decode_www_form(@calls.last[0].query).to_h["limit"]
    end
    [false, 1, [], {}, "\xff".dup.force_encoding("UTF-8")].each do |cursor|
      assert_rejected { client.list_bugs(:cursor => cursor) }
    end
    [nil, false, 1, []].each { |options| assert_rejected { client.list_bugs(options) } }
  end

  def test_safe_ids_are_one_encoded_path_segment
    @body = detail
    { " bug 雪+😀 " => "bug%20%E9%9B%AA%2B%F0%9F%98%80",
      "a b+c" => "a%20b%2Bc", "bug.v1" => "bug.v1", "bug?x=#@:&" => "bug%3Fx%3D%23%40%3A%26" }.each do |id, encoded|
      assert_equal "bug-123", client.get_bug(id)[:id]
      assert_equal "/prefix/api/mobile-bug-reports/bugs/#{encoded}", @calls.last[0].path
    end
  end

  def test_unsafe_ids_are_rejected_before_resolving_identity_or_http
    reporter = client(configuration, :resolve_application_session_token => lambda { |_| flunk "resolver must not run" })
    [nil, false, 1, [], {}, "", " \u00a0", ".", "..", " ../ ", "bug/123", "bug\\123",
      "/absolute", "//evil.example", "https://evil.example", "%2e%2e", "%2F", "%5C", "%00", "%252e%252e",
      "bug%20id", "bug\x00id", "bug\nid", "bug\rid", "bug\tid", "bug\x7fid", "\nbug", "bug\r", "bug\t",
      "\xff".dup.force_encoding("UTF-8")].each do |id|
      assert_rejected { reporter.get_bug(id) }
    end
    assert_empty @calls
  end

  def test_older_server_defaults_and_missing_discovery
    @body.delete("summary")
    @body.delete("query")
    @body["pagination"].delete("filtered_count")
    record = @body["bugs"][0]
    %w[archived archived_at occurrence_count reporter_occurrence_count].each { |key| record.delete(key) }
    result = client.list_bugs
    assert_nil result[:summary]
    assert_nil result[:query]
    assert_nil result[:pagination][:filtered_count]
    record = result[:bugs][0]
    assert_equal false, record[:archived]
    assert_equal "in_progress", record[:status_group]
    assert_equal 1, record[:occurrence_count]
    assert_equal 1, record[:reporter_occurrence_count]
    [:archived_at, :resolution_journey, :reported_app_version, :reported_route, :reported_app_flavor].each { |key| assert_nil record[key] }
    assert_nil record[:status_rollup][:reverification_status]
    @body = page
    @body["query"].delete("visibility")
    assert_equal "active", client.list_bugs[:query][:visibility]
  end

  def test_rollup_drives_groups_without_inference_from_status_or_journey
    %w[submitted verifying verified fixing fixed deployed closed not_reproduced wont_fix needs_attention].each do |stage|
      [true, false].each do |terminal|
        record = bug
        record["status"] = "server-owned-custom-status"
        record["status_rollup"].merge!("stage" => stage, "terminal" => terminal, "raw_status" => "custom-raw")
        record["resolution_journey"] = journey
        @body = detail(record)
        parsed = client.get_bug("bug-123")
        group = %w[needs_attention not_reproduced].include?(stage) ? stage : (terminal ? "closed" : "in_progress")
        assert_equal group, parsed[:status_group]
        assert_equal "server-owned-custom-status", parsed[:status]
        assert_equal "custom-raw", parsed[:status_rollup][:raw_status]
        assert_nil parsed[:status_rollup][:version]
      end
    end
  end

  def test_archive_and_status_group_consistency
    [{ "archived" => true, "archived_at" => nil }, { "archived" => false, "archived_at" => "2026-08-17" },
      { "archived" => nil }, { "archived" => "false" }, { "status_group" => "closed" }, { "status_group" => "unknown" }].each do |fields|
      @body = detail(bug.merge(fields))
      assert_rejected { client.get_bug("bug-123") }
    end
    @body = detail(bug.merge("archived" => true, "archived_at" => " 2026-08-17 "))
    assert_equal true, client.get_bug("bug-123")[:archived]
    assert_equal "2026-08-17", client.get_bug("bug-123")[:archived_at]
    @body["bug"]["archived_at"] = nil
    @body = page.merge("bugs" => [@body["bug"]])
    assert_rejected { client.list_bugs }
  end

  def test_js_impact_aliases_counts_and_optional_rollup_defaults
    { "sev1" => "critical", "HIGH" => "high", "Medium" => "moderate", "sev4" => "low" }.each do |value, impact|
      @body = detail(bug.merge("canonical_impact" => " #{value} "))
      assert_equal impact, client.get_bug("bug-123")[:impact]
    end
    { nil => 0, false => 0, true => 1, "3" => 3, "0x10" => 16, "" => 0, [] => 0,
      ["2"] => 2, "2.5" => 2.5, -1 => 1, "bad" => 1, {} => 1 }.each do |value, expected|
      @body = detail(bug.merge("occurrence_count" => value, "reporter_occurrence_count" => value))
      result = client.get_bug("bug-123")
      assert_equal expected, result[:occurrence_count]
      assert_equal expected, result[:reporter_occurrence_count]
    end
    # JS preserves each count independently; it does not impose a relation.
    @body = detail(bug.merge("occurrence_count" => 2, "reporter_occurrence_count" => 5))
    assert_equal 5, client.get_bug("bug-123")[:reporter_occurrence_count]
    %w[in_progress passed failed unknown].each do |status|
      @body["bug"]["status_rollup"]["reverification_status"] = status
      actual = client.get_bug("bug-123")[:status_rollup][:reverification_status]
      status == "unknown" ? assert_nil(actual) : assert_equal(status, actual)
    end
  end

  def test_malformed_core_records_reject_both_list_and_detail
    mutations = []
    %w[id title severity environment status].each do |key|
      [nil, " ", false, 1, [], {}].each { |value| mutations << bug.merge(key => value) }
    end
    [nil, [], {}, true].each { |value| mutations << bug.merge("status_rollup" => value) }
    %w[stage label raw_status terminal].each do |key|
      [nil, "", 1, [], {}].each do |value|
        record = bug
        record["status_rollup"][key] = value
        mutations << record
      end
    end
    mutations << bug.merge("canonical_impact" => "unknown")
    mutations << bug.merge("severity" => "unknown")
    record = bug
    record["status_rollup"]["stage"] = "invented"
    mutations << record
    mutations.each do |record|
      @body = detail(record)
      assert_rejected { client.get_bug("bug-123") }
      @body = page.merge("bugs" => [record])
      assert_rejected { client.list_bugs }
    end
  end

  def test_v1_envelopes_and_pagination_validation
    [nil, [], true, {}, { "contract_version" => "v2" }, { "contract_version" => 1 }].each do |value|
      @body = value
      assert_rejected { client.list_bugs }
      assert_rejected { client.get_bug("bug-123") }
    end
    { "contract_version" => [nil, "v2", 1], "bugs" => [nil, {}, "bugs"],
      "pagination" => [nil, [], true] }.each do |key, values|
      values.each do |value|
        @body = page.merge(key => value)
        assert_rejected { client.list_bugs }
      end
    end
    { "limit" => [nil, 0, -1, 51, 1.1, "bad"], "has_more" => [nil, 1, "true"],
      "next_cursor" => [nil, "", " ", 1, {}] }.each do |key, values|
      values.each do |value|
        @body = page
        @body["pagination"][key] = value
        assert_rejected { client.list_bugs }
      end
    end
    [1, 50, "20"].each do |limit|
      @body = page
      @body["pagination"]["limit"] = limit
      assert_equal limit.to_i, client.list_bugs[:pagination][:limit]
    end
    @body = page
    @body["pagination"].merge!("has_more" => false, "next_cursor" => nil)
    assert_nil client.list_bugs[:pagination][:next_cursor]
  end

  def test_summary_and_query_must_be_paired_and_counts_must_match_filter
    mutations = []
    %w[summary query].each do |key|
      body = page
      body.delete(key)
      mutations << body
      [nil, [], {}].each { |value| mutations << page.merge(key => value) }
    end
    %w[total needs_attention in_progress closed not_reproduced].each do |key|
      [-1, 0.5, "bad", {}, 99].each do |value|
        body = page
        body["summary"][key] = value
        mutations << body
      end
    end
    { "search" => ["", "x" * 201, false], "status_group" => ["", "unknown", 1],
      "sort" => [nil, "latest"], "visibility" => [nil, "hidden"] }.each do |key, values|
      values.each do |value|
        body = page
        body["query"][key] = value
        mutations << body
      end
      body = page
      body["query"].delete(key)
      mutations << body unless key == "visibility"
    end
    [nil, -1, 0.5, "bad", 3].each do |value|
      body = page
      body["pagination"]["filtered_count"] = value
      mutations << body
    end
    mutations.each do |body|
      @body = body
      assert_rejected { client.list_bugs }
    end
    @body = page
    @body["query"].merge!("status_group" => nil, "search" => nil)
    @body["pagination"]["filtered_count"] = 3
    assert_equal 3, client.list_bugs[:pagination][:filtered_count]
    @body["bugs"] = []
    @body["summary"].keys.each { |key| @body["summary"][key] = 0 }
    @body["pagination"].merge!("filtered_count" => 0, "has_more" => false, "next_cursor" => nil)
    assert_empty client.list_bugs[:bugs]
    @body["summary"].keys.each { |key| @body["summary"][key] = "0" }
    assert_equal 0, client.list_bugs[:summary][:total]
  end

  def test_optional_journey_preserves_explicit_timing_versions_and_next_step
    record = journey
    record["next_step"] = { "kind" => "read_only_runtime_diagnosis", "label" => "Read-only diagnosis required",
      "summary" => "A safe state comparison is needed." }
    @body = detail(bug.merge("resolution_journey" => record))
    result = client.get_bug("bug-123")[:resolution_journey]
    assert_equal "Confirmed resolved", result[:headline]
    assert_equal 600_000, result[:total_duration_ms]
    assert_equal 6, result[:milestones].length
    assert_equal 0, result[:milestones][0][:duration_ms]
    assert_equal 60_000, result[:milestones][1][:duration_ms]
    assert_equal "staging", result[:release_environment]
    assert_equal "1.4.0", result[:released_version]
    assert_equal "read_only_runtime_diagnosis", result[:next_step][:kind]
    assert_frozen_tree(result)
    %w[read_only_runtime_diagnosis scoped_diagnosis owner_decision].each do |kind|
      record["next_step"]["kind"] = kind
      assert_equal kind, client.get_bug("bug-123")[:resolution_journey][:next_step][:kind]
    end
    [nil, {}, { "kind" => "unsafe", "label" => "bad", "summary" => "bad" }].each do |value|
      record["next_step"] = value
      assert_nil client.get_bug("bug-123")[:resolution_journey][:next_step]
    end
    record["total_duration_ms"] = nil
    record["milestones"].each { |milestone| milestone["duration_ms"] = nil }
    assert_nil client.get_bug("bug-123")[:resolution_journey][:total_duration_ms]
    %w[complete current upcoming stopped].each do |state|
      record["milestones"][0]["state"] = state
      assert_equal state, client.get_bug("bug-123")[:resolution_journey][:milestones][0][:state]
    end
  end

  def test_malformed_optional_journeys_fall_back_without_discarding_core_history
    mutations = [nil, [], true, {}, journey.merge("schema_version" => 2), journey.merge("schema_version" => "1")]
    { "headline" => [nil, ""], "outcome" => [nil, "unknown"], "handling" => [nil, "unknown-value"],
      "automatic_fix_authorized" => [nil, 1], "automatic_delivery_authorized" => [nil, "true"],
      "approval_required" => [nil, "false"], "milestones" => [nil, [], [{}]],
      "total_duration_ms" => [-1, "bad", {}] }.each do |key, values|
      values.each { |value| mutations << journey.merge(key => value) }
      record = journey
      record.delete(key)
      mutations << record
    end
    { "key" => [nil, "unknown", "confirmed"], "label" => [nil, ""], "state" => [nil, "unknown"],
      "duration_ms" => [-1, "bad", {}] }.each do |key, values|
      values.each do |value|
        record = journey
        record["milestones"][0][key] = value
        mutations << record
      end
      record = journey
      record["milestones"][0].delete(key)
      mutations << record
    end
    record = journey
    record["milestones"] << record["milestones"][0].dup
    mutations << record
    mutations.each do |projection|
      @body = detail(bug.merge("resolution_journey" => projection))
      result = client.get_bug("bug-123")
      assert_equal "bug-123", result[:id]
      assert_nil result[:resolution_journey]
      @body = page.merge("bugs" => [@body["bug"]])
      assert_nil client.list_bugs[:bugs][0][:resolution_journey]
    end
  end

  def test_unauthorized_responses_preserve_status_and_sanitized_diagnostics
    [401, 403].each do |status|
      @status = status
      @body = { "code" => "bug_history_identity_required", "error" => "Denied #{SESSION} #{TOKEN}" }
      [:list_bugs, :get_bug].each do |operation|
        args = operation == :get_bug ? ["bug-123"] : []
        error = assert_rejected { client.send(operation, *args) }
        assert_equal status, error.status_code
        assert_equal "bug_history_identity_required", error.upstream_code
        assert_equal "history-request-1", error.request_id
        assert_equal "Denied [REDACTED] [REDACTED]", error.upstream_message
        [error.message, error.inspect, error.to_json].each do |text|
          refute_includes text, SESSION
          refute_includes text, TOKEN
        end
      end
    end
  end

  def test_retry_refreshes_request_scoped_identity_without_mutating_query
    sleeps, sessions = [], 0
    config = configuration(:max_attempts => 2, :retry_delay_ms => 10)
    http = lambda do |*args|
      @calls << args
      { :status => @calls.length == 1 ? 503 : 200, :body => JSON.generate(@body), :headers => {} }
    end
    factory = SDK::Factory.new(config, :http => http, :sleeper => lambda { |seconds| sleeps << seconds },
      :resolve_application_session_token => lambda { |request| sessions += 1; "#{request}-#{sessions}" })
    factory.for_request(:alice).list_bugs(:cursor => "opaque+/=")
    @body = detail
    factory.for_request(:bob).get_bug("bug-123")
    assert_equal [0.01], sleeps
    assert_equal @calls[0][0].to_s, @calls[1][0].to_s
    assert_equal ["alice-1", "alice-2", "bob-3"], @calls.map { |call| call[2]["x-handrail-application-session-token"] }
    assert @calls.all? { |call| call[1] == "GET" && call[3].nil? }
  end

  def test_network_failures_use_tracking_unavailable
    reporter = client(configuration, :http => lambda { |*_| raise IOError, SESSION })
    error = assert_raises(SDK::Error) { reporter.list_bugs }
    assert_equal :tracking_unavailable, error.code
    assert_nil error.status_code
    assert_nil error.cause
    refute_includes error.message, SESSION
  end

  def test_malformed_json_and_non_object_successes_are_rejected_safely
    [nil, "", "not-json #{TOKEN}", "null", "[]", "true", "{", "\xff".dup.force_encoding("ASCII-8BIT")].each do |bytes|
      reporter = client(configuration, :http => lambda { |*_| { :status => 200, :body => bytes, :headers => @headers } })
      error = assert_rejected { reporter.list_bugs }
      assert_equal 200, error.status_code
      assert_equal "history-request-1", error.request_id
      refute_includes error.message, TOKEN
    end
    @body["bugs"][0]["title"] = "Unicode 雪 😀"
    bytes = JSON.generate(@body).force_encoding("ASCII-8BIT")
    reporter = client(configuration, :http => lambda { |*_| { :status => 200, :body => bytes, :headers => {} } })
    assert_equal "Unicode 雪 😀", reporter.list_bugs[:bugs][0][:title]
  end

  def test_disabled_or_misconfigured_history_performs_no_work
    [configuration(:enabled => false), configuration(:project_id => nil), configuration(:report_token => nil)].each do |config|
      reporter = client(config, :resolve_application_session_token => lambda { |_| flunk "resolver must not run" })
      [:list_bugs, :get_bug].each do |operation|
        args = operation == :get_bug ? ["bug-123"] : []
        error = assert_raises(SDK::Error) { reporter.send(operation, *args) }
        assert_equal :invalid_configuration, error.code
      end
    end
    assert_empty @calls
  end
end
