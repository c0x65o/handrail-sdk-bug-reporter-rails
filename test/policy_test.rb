require "minitest/autorun"
require "minitest/mock"
require "handrail/bug_reporter/client"

class PolicyTest < Minitest::Test
  SDK = Handrail::BugReporter
  # Exact validPolicy fixture from JS v0.4.49 test/reporter.test.mjs at
  # 96b293248611594c388d0fab3af63b1b2d1aae5c. Mutations below are fixed cases.
  FIXTURE = File.read(File.expand_path("fixtures/js_v0.4.49_policy.json", File.dirname(__FILE__))).freeze

  class Clock
    attr_accessor :now
    attr_reader :sleeps

    def initialize
      @now, @sleeps = 0.0, []
    end

    def call
      @now
    end

    def sleep(seconds)
      @sleeps << seconds
      @now += seconds
    end
  end

  def setup
    @clock = Clock.new
  end

  def config(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/api",
      :project_id => " project-123 ", :environment => " StAgInG ",
      :report_token => "hbr_test_report" }.merge(options))
  end

  def fixture
    JSON.parse(FIXTURE)
  end

  def response(body = FIXTURE, status = 200)
    { :status => status, :body => body, :headers => {} }
  end

  def factory(options = {}, configuration = config)
    SDK::Factory.new(configuration, { :clock => @clock,
      :sleeper => @clock.method(:sleep), :http => lambda { |*_| response } }.merge(options))
  end

  def parse(body)
    SDK::Policy.parse(body, :project_id => "project-123", :environment => "staging")
  end

  def test_valid_js_fixture_is_an_immutable_projection
    input = fixture
    policy = parse(input)
    assert_equal 1, policy.schema_version
    assert_equal "project-123", policy.project_id
    assert_equal "staging", policy.environment
    assert_equal true, policy.identity_verified
    assert_equal "full_access", policy.access_level
    assert_equal "maintainer", policy.role
    assert_equal [], policy.ask_options
    assert_equal({ :schema_version => 3, :automatic_fix_max_risk => "high",
      :production_max_risk_by_impact => { :critical => "moderate", :high => "low", :moderate => "none", :low => "none" } }, policy.automation_policy)
    assert_equal({ :available => true, :recipient_hint => "r***@example.com", :lifecycles => ["fixed"] }, policy.reporter_notifications)
    [policy, policy.project_id, policy.environment, policy.access_level, policy.role,
      policy.ask_options, policy.automation_policy, policy.automation_policy[:production_max_risk_by_impact],
      policy.reporter_notifications, policy.reporter_notifications[:recipient_hint],
      policy.reporter_notifications[:lifecycles], policy.reporter_notifications[:lifecycles][0]].each do |value|
      assert value.frozen?
    end
    input["reporter"]["role"].replace("requester")
    input["reporter_notifications"]["lifecycles"][0].replace("deployed")
    assert_equal "maintainer", policy.role
    assert_equal ["fixed"], policy.reporter_notifications[:lifecycles]
  end

  def test_strict_schema_project_environment_reporter_and_ask_shapes
    [nil, [], true, 1, "policy"].each { |body| assert_nil parse(body) }
    { "schema_version" => [nil, "1", true, 2], "project_id" => [nil, "wrong-project", " project-123", 123],
      "environment" => [nil, "production", [], 1], "reporter" => [nil, [], true],
      "ask_options" => [nil, {}, "fix"] }.each do |key, values|
      values.each { |value| assert_nil parse(fixture.merge(key => value)), [key, value].inspect }
    end
    assert parse(fixture.merge("environment" => " StAgInG "))
    [nil, false, 1, "true", [], {}].each do |value|
      body = fixture
      body["reporter"]["identity_verified"] = value
      assert_nil parse(body)
    end
  end

  def test_role_and_access_allowlists
    ["default", "user", "full_access"].each do |access|
      ["requester", "contributor", "maintainer"].each do |role|
        body = fixture
        body["reporter"].merge!("access_level" => " #{access} ", "role" => " #{role} ")
        assert_equal access, parse(body).access_level
        assert_equal role, parse(body).role
      end
    end
    [nil, "", "owner", "admin", "Maintainer", {}, 1].each do |role|
      body = fixture
      body["reporter"]["role"] = role
      assert_nil parse(body).role
    end
    [nil, "", "admin", "FULL_ACCESS", {}, true].each do |access|
      body = fixture
      body["reporter"]["access_level"] = access
      assert_nil parse(body)
    end
  end

  def test_legacy_and_unknown_asks_are_always_empty
    body = fixture.merge("ask_options" => [nil, [], true, { "key" => "fix" },
      { "key" => "deploy" }, { "key" => "ask_to_fix" }, { "key" => "ask_to_deploy" }, { "key" => "unknown" }])
    assert_equal [], parse(body).ask_options
  end

  def test_optional_automation_requires_schema_three_and_every_valid_risk
    [nil, [], true, {}, { "schema_version" => 2 }, { "schema_version" => "3" }].each do |value|
      assert_nil parse(fixture.merge("automation_policy" => value)).automation_policy
    end
    ["automatic_fix_max_risk", "critical", "high", "moderate", "low"].each do |key|
      [nil, "", "extreme", "HIGH", true, {}, []].each do |value|
        body = fixture
        record = body["automation_policy"]
        record = record["production_max_risk_by_impact"] unless key == "automatic_fix_max_risk"
        record[key] = value
        assert_nil parse(body).automation_policy
      end
    end
    ["none", "low", "moderate", "high"].each do |risk|
      body = fixture
      body["automation_policy"]["automatic_fix_max_risk"] = " #{risk} "
      body["automation_policy"]["production_max_risk_by_impact"].keys.each do |impact|
        body["automation_policy"]["production_max_risk_by_impact"][impact] = " #{risk} "
      end
      assert_equal risk, parse(body).automation_policy[:automatic_fix_max_risk]
      assert_equal [risk], parse(body).automation_policy[:production_max_risk_by_impact].values.uniq
    end
  end

  def test_notification_eligibility_hints_and_lifecycles
    [nil, [], {}, true].each do |value|
      assert_equal({ :available => false, :recipient_hint => nil, :lifecycles => [] },
        parse(fixture.merge("reporter_notifications" => value)).reporter_notifications)
    end
    [nil, false, 1, "true", true].each do |available|
      notification = parse(fixture.merge("reporter_notifications" => {
        "available" => available, "recipient_hint" => " r***@example.com ",
        "lifecycles" => ["fixed", "deployed", "fixed", "FIXED", " deployed ", nil, {}]
      })).reporter_notifications
      assert_equal available == true, notification[:available]
      if available == true
        assert_equal "r***@example.com", notification[:recipient_hint]
      else
        assert_nil notification[:recipient_hint]
      end
      assert_equal ["fixed", "deployed", "fixed"], notification[:lifecycles]
    end
    [nil, " ", 1, {}].each do |hint|
      assert_nil parse(fixture.merge("reporter_notifications" => {
        "available" => true, "recipient_hint" => hint, "lifecycles" => "fixed"
      })).reporter_notifications[:recipient_hint]
    end
  end

  def test_discovery_get_encodes_authoritative_binding_and_refreshes_identity
    calls, tokens = [], [" first-session ", "second-session"]
    configuration = config(:project_id => "project &?/+123", :environment => " StAgInG &+ ")
    body = JSON.generate(fixture.merge("project_id" => configuration.project_id, "environment" => configuration.environment))
    reporter = factory({ :resolve_application_session_token => lambda { |request| assert_equal :host, request; tokens.shift },
      :http => lambda { |*args| calls << args; response(body) } }, configuration).for_request(:host)
    2.times { assert reporter.discover_policy }
    assert_equal ["first-session", "second-session"], calls.map { |call| call[2]["x-handrail-application-session-token"] }
    calls.each do |uri, method, headers, bytes, timeouts|
      assert_equal "GET", method
      assert_equal "/api/mobile-bug-reports/policy", uri.path
      assert_equal "project_id=project+%26%3F%2F%2B123&environment=staging+%26%2B", uri.query
      assert_nil bytes
      assert_equal "Bearer hbr_test_report", headers["authorization"]
      assert_operator timeouts[:request_timeout], :<=, 5
    end
  end

  def test_disabled_and_misconfigured_clients_do_no_discovery_work
    [config(:enabled => false), config(:project_id => nil), config(:report_token => nil), config(:api_base_url => nil)].each do |configuration|
      reporter = factory({ :http => lambda { |*_| flunk "HTTP called" },
        :resolve_application_session_token => lambda { |_| flunk "resolver called" } }, configuration).for_request
      assert_nil reporter.discover_policy
    end
  end

  def test_invalid_json_and_policies_fall_back_without_affecting_ordinary_requests
    ["not json", "null", "[]", JSON.generate(fixture.merge("project_id" => "other")),
      JSON.generate(fixture.merge("reporter" => { "identity_verified" => false, "access_level" => "default" }))].each do |body|
      reporter = factory(:http => lambda { |_, method, *rest| method == "GET" ? response(body) : response('{"bug_id":"bug-123"}', 201) }).for_request
      assert_nil reporter.discover_policy
      assert_equal 201, reporter.request(:method => "POST", :body => '{"title":"Ordinary report"}').status_code
    end
  end

  def test_json_failure_does_not_trigger_hydration_retry
    calls = 0
    reporter = factory(:resolve_application_session_token => lambda { |_| nil },
      :http => lambda { |*_| calls += 1; response("not JSON") }).for_request
    assert_nil reporter.discover_policy
    assert_equal 1, calls
    assert_empty @clock.sleeps
  end

  def test_resolver_failure_returns_nil_and_ordinary_requests_still_work
    calls, resolving = [], 0
    reporter = factory(:resolve_application_session_token => lambda { |_| resolving += 1; raise "private resolver failure" },
      :http => lambda { |*args| calls << args; response }).for_request
    assert_nil reporter.discover_policy
    assert_empty calls
    assert_equal :ok, reporter.request(:method => "POST", :body => "{}").status
    assert_equal 2, resolving
    assert_nil calls.first[2]["x-handrail-application-session-token"]
  end

  def test_identity_hydration_uses_both_js_delays_and_fresh_tokens
    tokens, calls = [nil, nil, "hydrated-session"], []
    reporter = factory(:resolve_application_session_token => lambda { |_| tokens.shift },
      :http => lambda { |_, _, headers, *rest|
        calls << headers["x-handrail-application-session-token"]
        response(headers["x-handrail-application-session-token"] ? FIXTURE : JSON.generate(fixture.merge("reporter" => {
          "identity_verified" => false, "access_level" => "default" })))
      }).for_request
    assert reporter.discover_policy
    assert_equal [nil, nil, "hydrated-session"], calls
    assert_equal [0.1, 0.25], @clock.sleeps
  end

  def test_exhausted_failures_and_permanent_statuses_have_bounded_attempts
    [400, 401, 403, 404, 503, nil].each do |status|
      calls = 0
      reporter = factory(:resolve_application_session_token => lambda { |_| "session" },
        :http => lambda { |*_| calls += 1; raise IOError unless status; response("{}", status) }).for_request
      assert_nil reporter.discover_policy
      assert_equal (status.nil? || status == 503 ? 3 : 1), calls
    end
    calls = 0
    reporter = factory(:http => lambda { |*_| calls += 1; response("{}", 503) }).for_request
    assert_nil reporter.discover_policy
    assert_equal 1, calls
  end

  def test_one_default_deadline_covers_resolvers_http_transport_retries_and_hydration
    calls, resolutions, timeouts = 0, 0, []
    reporter = factory({ :resolve_application_session_token => lambda { |_|
        resolutions += 1; @clock.now += 0.5; "session-#{resolutions}"
      }, :http => lambda { |_, _, headers, _, limits|
        calls += 1; assert_equal "session-#{calls}", headers["x-handrail-application-session-token"]
        timeouts << limits[:request_timeout]; @clock.now += 0.5; response("{}", 503)
      } }, config(:max_attempts => 2, :retry_delay_ms => 1000)).for_request
    assert_nil reporter.discover_policy
    assert_equal 3, calls
    assert_equal 3, resolutions
    assert_in_delta 5, @clock.now, 0.0001
    assert_equal 3, @clock.sleeps.length
    [1, 0.1, 0.9].zip(@clock.sleeps).each { |expected, actual| assert_in_delta expected, actual, 0.0001 }
    [4.5, 2.5, 1.4].zip(timeouts).each { |expected, actual| assert_in_delta expected, actual, 0.01 }
  end

  def test_expiry_after_resolver_prevents_http
    reporter = factory(:resolve_application_session_token => lambda { |_| @clock.now += 5; "late-session" },
      :http => lambda { |*_| flunk "late HTTP" }).for_request
    assert_nil reporter.discover_policy
  end

  def test_expiry_after_http_prevents_parsing
    reporter = factory(:http => lambda { |*_| @clock.now += 5; response }).for_request
    JSON.stub(:parse, lambda { |*_| flunk "late JSON parsing" }) do
      assert_nil reporter.discover_policy
    end
  end

  def test_expiry_during_json_and_policy_parsing_never_returns_late_policy
    body = fixture
    reporter = factory.for_request
    JSON.stub(:parse, lambda { |_| @clock.now += 5; body }) do
      SDK::Policy.stub(:parse, lambda { |*_| flunk "late policy parsing" }) { assert_nil reporter.discover_policy }
    end
    valid = parse(body)
    SDK::Policy.stub(:parse, lambda { |*_| @clock.now += 5; valid }) { assert_nil reporter.discover_policy }
    assert reporter.discover_policy
  end

  def test_expiry_during_identity_backoff_prevents_another_resolver_or_http_call
    resolutions, calls = 0, 0
    reporter = factory(:resolve_application_session_token => lambda { |_| resolutions += 1; nil },
      :http => lambda { |*_| calls += 1; response(JSON.generate(fixture.merge("reporter" => {
        "identity_verified" => false, "access_level" => "default" }))) }).for_request
    assert_nil reporter.discover_policy(:timeout_ms => 50)
    assert_equal 1, resolutions
    assert_equal 1, calls
    assert_equal 1, @clock.sleeps.length
    assert_operator @clock.sleeps.first, :<=, 0.05
  end

  def test_stalled_resolver_is_interrupted_without_late_http_and_submission_recovers
    calls, finished, resolving = 0, false, 0
    reporter = factory(:resolve_application_session_token => lambda { |_|
        resolving += 1
        if resolving == 1
          begin
            sleep 10
          ensure
            finished = true
          end
        end
        "fresh-session"
      }, :http => lambda { |*_| calls += 1; response }).for_request
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_nil reporter.discover_policy(:timeout_ms => 20)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
    assert finished
    assert_equal 0, calls
    assert_equal :ok, reporter.request(:method => "POST", :body => "{}").status
    assert_equal 1, calls
  end

  def test_stalled_http_and_backoff_are_interrupted_even_with_a_static_injected_clock
    [:http, :sleeper].each do |boundary|
      calls = 0
      options = { :http => lambda { |*_| calls += 1; response("{}", 503) } }
      options[boundary] = lambda { |*_| sleep 10; response }
      reporter = factory(options, config(:max_attempts => 2)).for_request
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_nil reporter.discover_policy(:timeout_ms => 20)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.5
      assert_equal 1, calls if boundary == :sleeper
    end
  end

  def test_timeout_override_normalization_and_effective_http_limit
    [[nil, 5000], ["20", 5000], [true, 5000], [Float::INFINITY, 5000], [Float::NAN, 5000],
      [-1, 1], [0, 1], [1.5, 2], [20.4, 20], [50_000, 30_000]].each do |input, expected|
      assert_equal expected, SDK::Policy.timeout_ms(input)
    end
    limits = nil
    reporter = factory(:http => lambda { |_, _, _, _, timeouts| limits = timeouts; response }).for_request
    assert reporter.discover_policy(:timeout_ms => 100)
    limits.each_value { |value| assert_operator value, :<=, 0.1; assert_operator value, :>, 0 }
  end

  def test_concurrent_request_clients_share_no_policy_or_resolved_credentials
    entered, release = Queue.new, Queue.new
    shared = factory(:resolve_application_session_token => lambda { |request| request[:session] },
      :http => lambda { |_, _, headers, *rest|
        token = headers["x-handrail-application-session-token"]
        entered << token
        release.pop
        body = fixture
        body["reporter"]["role"] = token == "session-A" ? "maintainer" : "requester"
        response(JSON.generate(body))
      })
    clients = [shared.for_request(:session => "session-A"), shared.for_request(:session => "session-B")]
    original_state = clients.map { |client| client.instance_variables.sort }
    threads = clients.map { |client| Thread.new { client.discover_policy } }
    assert_equal ["session-A", "session-B"], [entered.pop, entered.pop].sort
    2.times { release << true }
    assert_equal ["maintainer", "requester"], threads.map { |thread| thread.value.role }
    assert_equal original_state, clients.map { |client| client.instance_variables.sort }
    assert_equal [:@configuration, :@resolver, :@transport].sort, shared.instance_variables.sort
    assert_equal [:@clock, :@configuration, :@http, :@sleeper].sort,
      shared.instance_variable_get(:@transport).instance_variables.sort
  ensure
    threads.each { |thread| thread.kill if thread.alive? } if threads
  end
end
