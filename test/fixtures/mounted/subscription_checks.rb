require "support/no_network"
require "minitest/autorun"
require "rack/mock"
require File.expand_path("config/application", File.dirname(__FILE__))
require File.expand_path("forwarding_support", File.dirname(__FILE__))

MountedHost::Application.initialize!

class SessionFixtureController
  def show
    session[:principal] = params[:fixture_principal] == "bob" ? "bob" : "alice"
    render :json => { :csrf => form_authenticity_token }
  end
end

# This isolated fixture must never invoke public parent submission, even when a
# child fails. The HTTP boundary below also proves no parent intake is repeated.
class Handrail::BugReporter::Client
  class << self
    attr_accessor :parent_submit_calls
  end

  def submit(*args)
    self.class.parent_submit_calls += 1
    raise "Parent submission must not run"
  end
end

class MountedSubscriptionChecks < Minitest::Test
  include MountedForwardingSupport

  PATH = ROOT_PATH + "/bugs/bug-123/subscription"
  PRIVATE_VALUES = %w[recipient-sentinel@example.test body-private-sentinel
    header-private-sentinel exception-private-sentinel hbr_server_fixture alice-1 alice-2].freeze

  def setup
    super
    SDK::Client.parent_submit_calls = 0
    @logs = StringIO.new
    @original_logger = SDK::ReportsController.logger
    SDK::ReportsController.logger = Logger.new(@logs)
    SDK::ReportsController.logger.formatter = lambda { |_severity, _time, _progname, message| message.to_s + "\n" }
  end

  def teardown
    assert_equal 0, SDK::Client.parent_submit_calls
    assert @calls.all? { |sent| sent[:method] == "POST" && sent[:uri].path.end_with?("/subscription") }
    PRIVATE_VALUES.each { |value| refute_includes @logs.string, value }
    SDK::ReportsController.logger = @original_logger
  end

  def consent(version = "v1")
    { "reporter_notification" => { "notify_on_resolution" => true, "consent_version" => version } }
  end

  def post_consent(body = consent, headers = {}, path = PATH)
    call_app("POST", path, JSON.generate(body), headers)
  end

  def events
    @logs.string.lines.select { |line| line.start_with?("{\"schema_version\"") }.map { |line| JSON.parse(line) }
  end

  def assert_failure(response, status, stage, code)
    assert_equal status, response[0], response[2]
    assert_equal({ "error" => code }, JSON.parse(response[2]))
    assert_private(response)
    assert_equal [{ "schema_version" => 1, "component" => "handrail_bug_reporter_proxy",
      "event" => "bug_notification.forward_failed", "stage" => stage, "status" => status,
      "consent_validated" => true, "upstream_response_received" => stage != "upstream_unavailable" }], events
    PRIVATE_VALUES.each { |value| refute_includes response[2], value }
  end

  def test_default_and_custom_consent_use_javascript_trim_semantics
    versions = { nil => "v1", "" => "v1", " \t\r\n\u00a0\ufeff" => "v1", false => "v1",
      2 => "v1", [] => "v1", {} => "v1", " \u2000v2\ufeff " => "v2", "\u0085v3\u0085" => "\u0085v3\u0085" }
    versions.each do |value, expected|
      body = consent(value)
      body["reporter_notification"].delete("consent_version") if value.nil?
      response = post_consent(body)
      assert_equal 201, response[0], response[2]
      assert_equal consent(expected), JSON.parse(@calls.last[:body])
    end
    assert_equal 201, post_consent(consent(nil))[0]
    assert_equal consent, JSON.parse(@calls.last[:body])
    assert_empty events
  end

  def test_only_normalized_consent_is_sent_with_configured_scope
    body = wire.merge("recipient" => PRIVATE_VALUES[0], "identity" => PRIVATE_VALUES[1])
    body["reporter_notification"].merge!("recipient" => PRIVATE_VALUES[0], "application_session_token" => PRIVATE_VALUES[1])
    response = post_consent(body, { "HTTP_AUTHORIZATION" => PRIVATE_VALUES[2],
      "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => PRIVATE_VALUES[2],
      "HTTP_X_HANDRAIL_BUG_REPORT_TOKEN" => PRIVATE_VALUES[2] },
      PATH + "?project_id=spoof&environment=production&recipient=spoof&application_session_token=spoof&bad[=x")
    assert_equal 201, response[0], response[2]
    assert_equal 1, @calls.length
    sent = @calls.first
    assert_equal consent("v2"), JSON.parse(sent[:body])
    assert_equal "/prefix/api/mobile-bug-reports/bugs/bug-123/subscription", sent[:uri].path
    assert_equal({ "project_id" => "server/project + one", "environment" => "staging" }, URI.decode_www_form(sent[:uri].query).to_h)
    assert_equal({ "authorization" => "Bearer hbr_server_fixture", "accept" => "application/json",
      "content-type" => "application/json", "x-handrail-application-session-token" => "alice-1" }, sent[:headers])
    assert_private(response)
  end

  def test_success_preserves_json_bytes_status_and_private_headers
    bytes = '{ "subscribed":true, "version":2, "future":[null,false,12345678901234567890.123456789] }'
    @responses << { :status => 202, :body => bytes, :headers => { "set-cookie" => "evil=1", "authorization" => PRIVATE_VALUES[2] } }
    response = post_consent
    assert_equal 202, response[0]
    assert_equal bytes, response[2]
    assert_private(response)
    assert_empty events
  end

  def test_invalid_consent_and_json_never_resolve_identity_or_call_http
    inputs = [nil, [], true, 1, "text", {}, { "reporter_notification" => nil },
      { "reporter_notification" => [] }, { "reporter_notification" => true }]
    [nil, false, "true", 1, [], {}].each do |value|
      inputs << { "reporter_notification" => { "notify_on_resolution" => value } }
    end
    inputs.each { |body| assert_rejected(400, post_consent(body)) }
    ["", "{", '{"x":NaN}', "{\"x\":\"\xff\"}".b, "[" * 110 + "]" * 110].each do |bytes|
      assert_rejected(400, call_app("POST", PATH, bytes))
    end
    assert_empty events
  end

  def test_csrf_is_mandatory_even_when_host_protection_is_disabled
    refute Rails.application.config.action_controller.allow_forgery_protection
    ["", "invalid", @csrf.reverse].each do |token|
      assert_rejected(403, post_consent(consent, "HTTP_X_CSRF_TOKEN" => token))
    end
    assert_rejected(403, post_consent(consent, "HTTP_COOKIE" => ""))
    body = consent.merge("authenticity_token" => @csrf)
    assert_rejected(403, post_consent(body, { "HTTP_X_CSRF_TOKEN" => "" }, PATH + "?authenticity_token=" + @csrf))
    assert_rejected(403, post_consent(consent, "HTTP_ORIGIN" => nil, "HTTP_X_CSRF_TOKEN" => ""))
    assert_equal 201, post_consent(consent, "HTTP_ORIGIN" => nil)[0]
  end

  def test_origin_and_fetch_site_enforcement
    [{ "HTTP_ORIGIN" => "https://evil.example" }, { "HTTP_ORIGIN" => "null" },
      { "HTTP_ORIGIN" => "https://host.example.evil" }, { "HTTP_ORIGIN" => "https://host.example:444" },
      { "HTTP_SEC_FETCH_SITE" => "cross-site" }].each do |headers|
      assert_rejected(403, post_consent(consent, headers))
    end
  end

  def test_json_content_type_and_declared_length_enforcement
    [nil, "text/plain", "application/x-www-form-urlencoded", "multipart/form-data"].each do |type|
      assert_rejected(415, post_consent(consent, "CONTENT_TYPE" => type))
    end
    ["-1", "abc", "1.1"].each do |length|
      assert_rejected(400, call_app("POST", PATH, JSON.generate(consent), {}, length))
    end
    input = BoundedInput.new("{}")
    assert_rejected(413, call_app("POST", PATH, "", {}, LIMIT + 1, input))
    assert_equal 0, input.bytes_read
    assert_equal 201, post_consent(consent, "CONTENT_TYPE" => "application/json; charset=utf-8")[0]
  end

  def test_bounded_actual_body_with_absent_zero_and_understated_lengths
    bytes = JSON.generate(consent.merge("ignored" => "x" * LIMIT))
    [:absent, 0, 2].each do |length|
      input = BoundedInput.new(bytes)
      assert_rejected(413, call_app("POST", PATH, "", {}, length, input))
      assert_equal LIMIT + 1, input.bytes_read
      assert_operator input.read_sizes.max, :<=, 16_384
    end
  end

  def test_exact_multibyte_body_limit_is_accepted_and_excess_rejected
    bytes = JSON.generate(consent.merge("ignored" => ""))
    available = LIMIT - bytes.bytesize
    bytes = JSON.generate(consent.merge("ignored" => "é" * (available / 2) + "x" * (available % 2)))
    assert_equal LIMIT, bytes.bytesize
    response = call_app("POST", PATH, bytes, {}, :absent, BoundedInput.new(bytes))
    assert_equal 201, response[0], response[2]
    assert_equal consent, JSON.parse(@calls.first[:body])
    @calls.clear
    @resolved.clear
    bytes = bytes.sub(/"}\z/, 'é"}')
    assert_operator bytes.length, :<, LIMIT
    assert_rejected(413, call_app("POST", PATH, bytes, {}, 1, BoundedInput.new(bytes)))
  end

  def test_safe_bug_ids_are_encoded_once_and_preserve_dots
    { "bug%2D123" => "bug-123", "bug.json" => "bug.json", "a%2Eb" => "a.b",
      "%20bug%20" => "bug", "a+b" => "a%2Bb", "a%20b" => "a%20b", "caf%C3%A9" => "caf%C3%A9" }.each do |incoming, expected|
      response = post_consent(consent, {}, ROOT_PATH + "/bugs/" + incoming + "/subscription")
      assert_equal 201, response[0], response[2]
      assert_equal "/prefix/api/mobile-bug-reports/bugs/" + expected + "/subscription", @calls.last[:uri].path
      assert_nil @calls.last[:uri].fragment
    end
  end

  def test_unsafe_bug_ids_and_extra_path_segments_never_reach_http
    %w[% %2 %GG %FF %C0%AF %20 %09 . .. %2e %2e%2e %252e%252e
      a%2Fb a%2fb a%252Fb a%5Cb a%3Fb a%23b a%25b a%00b a%0Ab a%0Db].each do |id|
      assert_rejected(404, post_consent(consent, {}, ROOT_PATH + "/bugs/" + id + "/subscription"))
    end
    %w[/bugs//subscription /bugs/a/subscription/extra /bugs/a/subscription.json].each do |path|
      assert_rejected(404, post_consent(consent, {}, ROOT_PATH + path))
    end
    # This is the existing detail resource named "subscription", not a child.
    assert_rejected(405, post_consent(consent, {}, ROOT_PATH + "/bugs/subscription"))
  end

  def test_only_post_is_mounted
    %w[GET HEAD PUT PATCH DELETE OPTIONS].each do |method|
      response = call_app(method, PATH, JSON.generate(consent))
      assert_rejected(405, response, method == "HEAD")
      assert_equal "POST", response[1]["allow"] || response[1]["Allow"]
    end
  end

  def test_retries_and_requests_resolve_fresh_host_identity
    @responses << { :status => 503, :body => PRIVATE_VALUES.join(" ") }
    assert_equal 201, post_consent[0]
    assert_equal ["alice", "alice"], @resolved
    assert_equal ["alice-1", "alice-2"], @calls.map { |sent| sent[:headers]["x-handrail-application-session-token"] }
    assert_same @calls[0][:body], @calls[1][:body]
    assert @calls[0][:body].frozen?
    login = call_app("GET", "/fixture-session?fixture_principal=bob", "", "HTTP_COOKIE" => "")
    bob_cookie = Array(login[1]["set-cookie"] || login[1]["Set-Cookie"]).first.split(";", 2).first
    bob_csrf = JSON.parse(login[2]).fetch("csrf")
    @responses << { :status => 403, :body => PRIVATE_VALUES.join(" ") }
    assert_failure(post_consent(consent, "HTTP_COOKIE" => bob_cookie, "HTTP_X_CSRF_TOKEN" => bob_csrf),
      403, "upstream_rejected", "bug_reporting_rejected")
    assert_equal 201, post_consent[0]
    assert_equal ["alice", "alice", "bob", "alice"], @resolved
    assert_equal ["alice-1", "alice-2", "bob-3", "alice-4"], @calls.map { |sent| sent[:headers]["x-handrail-application-session-token"] }
    @calls.clear
    @resolved.clear
    assert_rejected(403, post_consent(consent, "HTTP_COOKIE" => bob_cookie))
  end

  def test_all_upstream_rejections_preserve_status_and_log_only_safe_checkpoints
    [302, 400, 401, 403, 422, 429, 500, 503].each do |status|
      @calls.clear
      @logs.truncate(0)
      @logs.rewind
      diagnostic = JSON.generate("error" => { "code" => PRIVATE_VALUES[1], "message" => PRIVATE_VALUES.join(" "), "request_id" => PRIVATE_VALUES[0] })
      @responses = [{ :status => status, :body => diagnostic, :headers => { "x-request-id" => PRIVATE_VALUES[2] } }] * 2
      assert_failure(post_consent, status, "upstream_rejected", "bug_reporting_rejected")
      assert_equal SDK::Transport::TRANSIENT_STATUSES.include?(status) ? 2 : 1, @calls.length
    end
  end

  def test_unavailable_network_and_boundary_errors_are_generic_and_private
    [IOError.new(PRIVATE_VALUES[3]), RuntimeError.new(PRIVATE_VALUES[3])].each do |error|
      @calls.clear
      @logs.truncate(0)
      @logs.rewind
      @responses = [error, error]
      assert_failure(post_consent, 502, "upstream_unavailable", "bug_reporting_unavailable")
      assert_equal error.is_a?(IOError) ? 2 : 1, @calls.length
    end
  end

  def test_unreadable_successes_are_child_failures_without_parent_intake
    [nil, "", PRIVATE_VALUES.join(" "), "{\"x\":\"\xff\"}".b].each do |bytes|
      @calls.clear
      @logs.truncate(0)
      @logs.rewind
      @responses = [{ :status => 200, :body => bytes, :headers => { "x-request-id" => PRIVATE_VALUES[2] } }]
      assert_failure(post_consent, 502, "response_unreadable", "bug_reporting_unavailable")
      assert_equal 1, @calls.length
    end
  end

  def test_unconfigured_and_disabled_mounts_fail_closed_without_http
    Rails.application.config.handrail_bug_reporter_factory = nil
    assert_rejected(503, post_consent)
    configure(:enabled => false)
    assert_rejected(404, post_consent)
    configure(:report_token => nil)
    assert_rejected(503, post_consent)
    assert_empty events
  end
end
