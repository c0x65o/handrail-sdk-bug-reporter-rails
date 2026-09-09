require "minitest/autorun"
require "handrail/bug_reporter/client"

class SubmissionTest < Minitest::Test
  SDK = Handrail::BugReporter
  TOKEN = "hbr_submission_test_credential"
  SESSION = "session-submission-credential"
  NEXT_SESSION = "next-session-submission-credential"

  def setup
    @calls, @sleeps, @resolved = [], [], []
  end

  def config(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/prefix/api",
      :project_id => " configured-project ", :environment => " StAgInG ",
      :report_token => TOKEN }.merge(options))
  end

  def report(options = {})
    { :title => "Broken button", :description => "Clicking does nothing." }.merge(options)
  end

  def response(status = 201, body = '{"bug_id":"canonical-bug"}', headers = {})
    { :status => status, :body => body, :headers => headers }
  end

  def client(configuration = config, &boundary)
    boundary ||= lambda { |*_| response }
    request = Object.new
    SDK::Factory.new(configuration,
      :sleeper => lambda { |delay| @sleeps << delay },
      :resolve_application_session_token => lambda { |req|
        assert_same request, req
        @resolved << req
        @resolved.length == 1 ? SESSION : NEXT_SESSION
      },
      :http => lambda { |*args| @calls << args; boundary.call(*args) }).for_request(request)
  end

  def assert_safe(error)
    assert_equal "Bug reporting request failed.", error.message unless error.code == :invalid_configuration
    assert_nil error.cause
    surfaces = [error.message, error.to_s, error.inspect, error.as_json,
      error.to_json, JSON.generate(error), error.upstream_code,
      error.upstream_message, error.request_id]
    surfaces << error.full_message if error.respond_to?(:full_message)
    [TOKEN, SESSION, NEXT_SESSION].each { |secret| refute_includes surfaces.inspect, secret }
  end

  def assert_no_request
    assert_empty @calls
    assert_empty @resolved
    assert_empty @sleeps
  end

  def test_success_returns_canonical_id_and_deeply_immutable_parsed_response
    parsed = { "bug_id" => " canonical-bug ", "event_id" => "unrelated-event",
      "id" => "unrelated-id", "report" => { "bug_id" => "nested-id" },
      "details" => [{ "message" => "accepted ☃" }] }
    result = client { |*_| response(202, JSON.generate(parsed).b) }.submit(report)
    assert_equal :submitted, result.status
    assert result.submitted?
    assert_equal 202, result.status_code
    assert_equal "canonical-bug", result.bug_id
    assert_equal parsed, result.response
    assert result.frozen?
    assert result.bug_id.frozen?
    assert result.response.frozen?
    assert result.response["details"].frozen?
    assert result.response["details"][0].frozen?
    assert result.response["details"][0]["message"].frozen?
    assert result.response.keys.all?(&:frozen?)
    assert_raises(RuntimeError) { result.response["details"][0]["message"].replace("changed") }
    uri, method, headers, bytes = @calls.fetch(0)
    assert_equal "https://handrail.example/prefix/api/mobile-bug-reports", uri.to_s
    assert_equal "POST", method
    assert_equal "application/json", headers["content-type"]
    assert_equal "Bearer #{TOKEN}", headers["authorization"]
    assert_equal SESSION, headers["x-handrail-application-session-token"]
    assert_equal "Broken button", JSON.parse(bytes)["title"]
    assert_empty @sleeps
  end

  def test_canonical_id_never_falls_back_to_event_or_nested_or_unrelated_ids
    [nil, "", "  ", 123, [], {}].each do |bug_id|
      body = { "bug_id" => bug_id, "event_id" => "event", "id" => "id",
        "bugId" => "camel-id", "report" => { "bug_id" => "nested" } }
      assert_nil client { |*_| response(200, JSON.generate(body)) }.submit(report).bug_id
    end
    assert_nil client { |*_| response(200, '{}') }.submit(report).bug_id
  end

  def test_response_loss_retries_identical_bytes_with_one_generated_event_and_one_preparation
    input = report
    hook_calls = 0
    hook = lambda { |fields| hook_calls += 1; fields }
    reporter = client(config(:max_attempts => 3)) do |*args|
      assert args[3].frozen?
      input[:title] = "Mutated after send"
      raise EOFError, "Lost response #{TOKEN} #{SESSION}" if @calls.length == 1
      response
    end
    result = reporter.submit(input, :redaction_hooks => [hook])
    assert_equal :submitted, result.status
    assert_equal 2, @calls.length
    assert_equal 1, hook_calls
    assert_equal [0.25], @sleeps
    assert_same @calls[0][3], @calls[1][3]
    assert_equal @calls[0][3].bytes, @calls[1][3].bytes
    bodies = @calls.map { |call| JSON.parse(call[3]) }
    assert_equal 1, bodies.map { |body| body["event_id"] }.uniq.length
    assert_match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/, bodies[0]["event_id"])
    assert_equal ["Broken button", "Broken button"], bodies.map { |body| body["title"] }
    assert_equal [SESSION, NEXT_SESSION], @calls.map { |call| call[2]["x-handrail-application-session-token"] }
  end

  def test_disabled_returns_before_validation_hooks_identity_and_http
    result = client(config(:enabled => false, :api_base_url => nil)).submit(nil,
      :redaction_hooks => [lambda { |_| flunk "hook called" }])
    assert_equal :disabled, result.status
    refute result.submitted?
    assert_nil result.status_code
    assert_nil result.bug_id
    assert_nil result.response
    assert result.frozen?
    assert_no_request
  end

  def test_misconfiguration_precedes_invalid_report
    [:api_base_url, :project_id, :environment, :report_token].each do |key|
      error = assert_raises(SDK::Error) { client(config(key => nil)).submit(nil) }
      assert_equal :invalid_configuration, error.code
      assert_equal "Bug reporting is not configured.", error.message
      assert_safe(error)
    end
    assert_no_request
  end

  def test_invalid_reports_and_serialization_errors_never_resolve_or_send
    [nil, [], TOKEN, {}, report(:title => " "), report(:title => nil, :description => SESSION),
      report(:metadata => { :text => "\xff".force_encoding("UTF-8") })].each do |input|
      error = assert_raises(SDK::Error) { client.submit(input) }
      assert_equal :invalid_report, error.code
      assert_safe(error)
    end
    assert_no_request
  end

  def test_screenshot_input_cannot_grant_itself_permission
    io = Object.new
    read_called = false
    io.define_singleton_method(:read) { |_length| read_called = true; nil }
    input = report(:screenshot => { :data => io }, :allow_screenshots => true, :allowScreenshots => true)
    error = assert_raises(SDK::Error) { client.submit(input) }
    assert_equal :invalid_screenshot, error.code
    refute read_called
    assert_safe(error)
    assert_no_request
  end

  def test_invalid_screenshot_with_trusted_permission_fails_before_http
    error = assert_raises(SDK::Error) do
      client.submit(report(:screenshot => { :data => TOKEN + SESSION }), :allow_screenshots => true)
    end
    assert_equal :invalid_screenshot, error.code
    assert_safe(error)
    assert_no_request
  end

  def test_configured_binding_redaction_and_explicit_screenshot_consent_are_reused
    png = SDK::Screenshot::PNG_SIGNATURE + "fixture"
    input = report(:project_id => "attacker", :environment => "production", :event_id => "caller-event",
      :metadata => { :password => TOKEN, :safe => "keep" }, :screenshot => { :data => png },
      :automation_requests => ["ignored"], :notification => { :notifyOnResolution => true })
    hook = lambda { |fields| fields.merge("project_id" => "hook-project", "environment" => "hook-env",
      "event_id" => "hook-event", "description" => "Redacted description") }
    client.submit(input, :redaction_hooks => [hook], :allow_screenshots => true)
    body = JSON.parse(@calls.fetch(0)[3])
    assert_equal "configured-project", body["project_id"]
    assert_equal "staging", body["environment"]
    assert_equal "caller-event", body["event_id"]
    assert_equal "Redacted description", body["description"]
    assert_equal({ "password" => "[REDACTED]", "safe" => "keep" }, body["metadata"])
    assert_equal Base64.strict_encode64(png), body["screenshot_base64"]
    refute body.key?("automation_requests")
    refute body.key?("notification")
    assert_equal 1, @calls.length
  end

  def test_redaction_hook_failures_drop_secret_causes_before_http
    error = assert_raises(SDK::Error) do
      client.submit(report, :redaction_hooks => [lambda { |_| raise "#{TOKEN} #{SESSION}" }])
    end
    assert_equal :redaction_failed, error.code
    assert_safe(error)
    assert_no_request
  end

  def test_rejection_preserves_bounded_sanitized_diagnostics
    body = JSON.generate("error" => { "code" => "E" * 150,
      "message" => "#{TOKEN}\n#{SESSION}\t" + "m" * 600, "request_id" => "body-correlation" })
    error = assert_raises(SDK::Error) do
      client(config(:max_attempts => 3)) { |*_| response(422, body, "X-Request-ID" => "r" * 240) }.submit(report)
    end
    assert_equal :submission_rejected, error.code
    assert_equal 422, error.status_code
    assert_equal "E" * 120, error.upstream_code
    assert_equal 500, error.upstream_message.length
    assert_includes error.upstream_message, "[REDACTED]"
    refute_match(/[\x00-\x1f\x7f]/, error.upstream_message)
    assert_equal "r" * 200, error.request_id
    assert_safe(error)
    assert_equal 1, @calls.length
    assert_empty @sleeps
  end

  def test_rejected_secret_identifiers_fall_back_to_safe_correlation
    body = JSON.generate("code" => TOKEN, "message" => "#{TOKEN} #{SESSION}", "request_id" => "safe-body-id")
    error = assert_raises(SDK::Error) do
      client { |*_| response(403, body, "x-request-id" => SESSION) }.submit(report)
    end
    assert_nil error.upstream_code
    assert_equal "safe-body-id", error.request_id
    assert_safe(error)
  end

  def test_malformed_or_oversized_rejection_keeps_safe_header_id
    ["not JSON #{TOKEN} #{SESSION}", "x" * 16_385].each do |body|
      error = assert_raises(SDK::Error) do
        client { |*_| response(400, body, "x-handrail-request-id" => "header-correlation") }.submit(report)
      end
      assert_equal :submission_rejected, error.code
      assert_nil error.upstream_code
      assert_nil error.upstream_message
      assert_equal "header-correlation", error.request_id
      assert_safe(error)
    end
  end

  def test_exhausted_http_retries_remain_rejection_with_all_session_values_redacted
    body = JSON.generate("message" => "#{TOKEN} #{SESSION} #{NEXT_SESSION}")
    error = assert_raises(SDK::Error) do
      client(config(:max_attempts => 3)) { |*_| response(503, body, "x-request-id" => "retry-id") }.submit(report)
    end
    assert_equal :submission_rejected, error.code
    assert_equal 503, error.status_code
    assert_equal "retry-id", error.request_id
    assert_equal 3, @calls.length
    assert_equal [0.25, 0.5], @sleeps
    assert_equal 1, @calls.map { |call| call[3] }.uniq.length
    assert_safe(error)
  end

  def test_exhausted_network_failures_are_distinct_from_rejection
    error = assert_raises(SDK::Error) do
      client(config(:max_attempts => 3)) { |*_| raise EOFError, "#{TOKEN} #{SESSION}" }.submit(report)
    end
    assert_equal :request_failed, error.code
    assert_nil error.status_code
    assert_nil error.upstream_code
    assert_nil error.upstream_message
    assert_nil error.request_id
    assert_equal 3, @calls.length
    assert_equal [0.25, 0.5], @sleeps
    assert_safe(error)
  end

  def test_malformed_successes_raise_safe_errors_without_retrying_accepted_requests
    [nil, "", " ", "<html>#{TOKEN} #{SESSION}</html>", '{"secret":"' + TOKEN,
      "null", "[]", '"' + SESSION + '"', "42", "true", "\xff".force_encoding("UTF-8"),
      '{"bug_id":"'.b + "\xff".b + '"}', "[" * 110 + "]" * 110].each do |body|
      before = @calls.length
      error = assert_raises(SDK::Error) do
        client(config(:max_attempts => 3)) { |*_| response(200, body, "x-request-id" => "parse-id") }.submit(report)
      end
      assert_equal :malformed_response, error.code
      assert_equal 200, error.status_code
      assert_equal "parse-id", error.request_id
      assert_nil error.upstream_code
      assert_nil error.upstream_message
      assert_safe(error)
      assert_equal before + 1, @calls.length
    end
    assert_empty @sleeps
  end

  def test_malformed_response_secret_header_is_not_retained
    error = assert_raises(SDK::Error) do
      client { |*_| response(204, nil, "x-request-id" => TOKEN, "x-handrail-request-id" => SESSION) }.submit(report)
    end
    assert_equal :malformed_response, error.code
    assert_nil error.request_id
    assert_safe(error)
  end

  def test_result_inspection_and_serialization_do_not_print_upstream_data
    body = JSON.generate("bug_id" => TOKEN, "echo" => SESSION)
    result = client { |*_| response(200, body) }.submit(report)
    [result.inspect, result.to_s, result.as_json, result.to_json, JSON.generate(result)].each do |surface|
      refute_includes surface, TOKEN
      refute_includes surface, SESSION
    end
    assert_equal SESSION, result.response["echo"]
  end

  def test_shared_request_keeps_its_original_error_mapping
    error = assert_raises(SDK::Error) do
      client { |*_| response(422) }.request(:method => "POST", :body => "{}")
    end
    assert_equal :request_failed, error.code
    assert_equal 422, error.status_code
  end
end
