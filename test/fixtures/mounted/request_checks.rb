require "support/no_network"
require "minitest/autorun"
require "rack/mock"
require File.expand_path("config/application", File.dirname(__FILE__))

MountedHost::Application.initialize!

require File.expand_path("forwarding_support", File.dirname(__FILE__))

class MountedForwardingChecks < Minitest::Test
  include MountedForwardingSupport

  def test_submission_preserves_wire_identity_and_binds_credentials
    response = call_app("POST", ROOT_PATH, JSON.generate(wire),
      "HTTP_AUTHORIZATION" => "Bearer caller", "HTTP_X_HANDRAIL_BUG_REPORT_TOKEN" => "caller-report",
      "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "caller-session")
    assert_equal 201, response[0], response[2]
    assert_equal({ "bug_id" => "bug-123" }, JSON.parse(response[2]))
    assert_private(response)
    assert_equal 1, @calls.length
    sent = JSON.parse(@calls.first[:body])
    %w[title description event_id platform reporter_sdk_runtime reporter_sdk_package reporter_sdk_version reporter_sdk_commit reporter_sdk_ref screenshot].each do |key|
      assert_equal wire[key], sent[key], key
    end
    assert_equal "intentional-profile", sent["profile_key"]
    assert_equal "server/project + one", sent["project_id"]
    assert_equal "staging", sent["environment"]
    assert_equal({ "notify_on_resolution" => true, "consent_version" => "v2" }, sent["reporter_notification"])
    %w[automation_requests application_session_token report_token authorization authentication x-handrail-application-session-token reportToken].each { |key| refute sent.key?(key) }
    nested = sent.fetch("metadata").fetch("safe").first
    assert_equal({ "count" => 3, "apiKey" => "[REDACTED]", "profile_key" => "[REDACTED]", "password" => "[REDACTED]" }, nested)
    assert_equal({ "authorization" => "Bearer hbr_server_fixture", "accept" => "application/json",
      "content-type" => "application/json", "x-handrail-application-session-token" => "fixture-principal-1" }, @calls.first[:headers])
  end

  def test_policy_only_forwards_authoritative_query_and_host_context
    @responses << { :status => 200, :body => '{"enabled":true}' }
    response = call_app("GET", ROOT_PATH + "/policy?project_id=spoof&environment=prod&arbitrary=1&bad[=x", "",
      "HTTP_AUTHORIZATION" => "caller", "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "caller-session")
    assert_equal 200, response[0], response[2]
    assert_private(response)
    assert_equal({ "enabled" => true }, JSON.parse(response[2]))
    assert_equal 1, @calls.length
    request = @calls.first
    assert_equal "/prefix/api/mobile-bug-reports/policy", request[:uri].path
    assert_equal({ "project_id" => "server/project + one", "environment" => "staging" }, URI.decode_www_form(request[:uri].query).to_h)
    assert_equal "GET", request[:method]
    assert_nil request[:body]
    refute_includes request[:headers].values, "caller"
    assert_equal "fixture-principal-1", request[:headers]["x-handrail-application-session-token"]
  end

  def test_unauthenticated_policy_does_not_derive_a_session_from_headers
    response = call_app("GET", ROOT_PATH + "/policy", "", "HTTP_COOKIE" => "",
      "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "caller-session")
    assert_equal 201, response[0]
    refute @calls.first[:headers].key?("x-handrail-application-session-token")
  end

  def test_missing_invalid_and_another_session_csrf_tokens_are_denied
    ["", "invalid", @csrf.reverse].each do |token|
      assert_rejected(403, call_app("POST", ROOT_PATH, JSON.generate(wire), "HTTP_X_CSRF_TOKEN" => token))
    end
    assert_rejected(403, call_app("POST", ROOT_PATH, JSON.generate(wire), "HTTP_COOKIE" => ""))
    body = wire.merge("authenticity_token" => @csrf)
    assert_rejected(403, call_app("POST", ROOT_PATH, JSON.generate(body), "HTTP_X_CSRF_TOKEN" => ""))
  end

  def test_cross_site_and_invalid_origins_are_denied_for_reads_and_writes
    [{ "HTTP_ORIGIN" => "https://evil.example" }, { "HTTP_ORIGIN" => "null" },
      { "HTTP_ORIGIN" => "https://host.example.evil" }, { "HTTP_ORIGIN" => "https://host.example:444" },
      { "HTTP_SEC_FETCH_SITE" => "cross-site" }].each do |headers|
      assert_rejected(403, call_app("POST", ROOT_PATH, JSON.generate(wire), headers))
      assert_rejected(403, call_app("GET", ROOT_PATH + "/policy", "", headers))
    end
  end

  def test_absent_origin_still_requires_valid_rails_csrf
    assert_rejected(403, call_app("POST", ROOT_PATH, "{}", "HTTP_ORIGIN" => nil, "HTTP_X_CSRF_TOKEN" => ""))
    assert_equal 201, call_app("POST", ROOT_PATH, "{}", "HTTP_ORIGIN" => nil)[0]
  end

  def test_declared_oversize_is_rejected_without_a_body_read
    input = BoundedInput.new("{}")
    response = call_app("POST", ROOT_PATH, "", {}, LIMIT + 1, input)
    assert_rejected(413, response)
    assert_equal 0, input.bytes_read
  end

  def test_actual_oversize_with_absent_zero_and_understated_lengths
    bytes = '{"description":"' + "x" * LIMIT + '"}'
    [:absent, 0, 2].each do |length|
      input = BoundedInput.new(bytes)
      assert_rejected(413, call_app("POST", ROOT_PATH, "", {}, length, input))
      assert_equal LIMIT + 1, input.bytes_read
      assert_operator input.read_sizes.max, :<=, 16_384
    end
  end

  def test_multibyte_limit_counts_bytes_and_accepts_exact_limit
    prefix, suffix = '{"description":"', '"}'
    available = LIMIT - prefix.bytesize - suffix.bytesize
    bytes = prefix + "é" * (available / 2) + "x" * (available % 2) + suffix
    assert_equal LIMIT, bytes.bytesize
    response = call_app("POST", ROOT_PATH, bytes, {}, :absent, BoundedInput.new(bytes))
    assert_equal 201, response[0], response[2]
    assert_equal JSON.parse(bytes)["description"], JSON.parse(@calls.first[:body])["description"]
    @calls.clear
    @resolved.clear
    bytes = bytes.sub(/"}\z/, 'é"}')
    assert_operator bytes.length, :<, LIMIT
    assert_rejected(413, call_app("POST", ROOT_PATH, bytes, {}, 1, BoundedInput.new(bytes)))
  end

  def test_invalid_json_and_nonobject_values_are_rejected
    ["", "{", "[]", "null", "true", "123", '"text"', "{\"x\":NaN}", "{\"x\":\"\xff\"}".b,
      "[" * 110 + "]" * 110].each do |bytes|
      assert_rejected(400, call_app("POST", ROOT_PATH, bytes))
    end
  end

  def test_wrong_content_types_and_invalid_lengths_are_rejected
    ["text/plain", "application/x-www-form-urlencoded", "multipart/form-data"].each do |type|
      assert_rejected(415, call_app("POST", ROOT_PATH, "{}", "CONTENT_TYPE" => type))
    end
    ["-1", "abc", "1.1"].each { |length| assert_rejected(400, call_app("POST", ROOT_PATH, "{}", {}, length)) }
  end

  def test_unsupported_methods_and_children_do_not_forward
    %w[GET HEAD PUT PATCH DELETE OPTIONS].each { |method| assert_rejected(405, call_app(method, ROOT_PATH), method == "HEAD") }
    %w[POST HEAD PUT DELETE OPTIONS].each { |method| assert_rejected(405, call_app(method, ROOT_PATH + "/policy"), method == "HEAD") }
    %w[/bugs/123/subscription/extra /policy.json /unknown].each do |path|
      assert_rejected(404, call_app("POST", ROOT_PATH + path, "{}"))
    end
  end

  def test_retry_resolves_fresh_credentials_and_reuses_serialized_body_without_subscription
    @responses << { :status => 503, :body => '{"error":"private-diagnostic"}' }
    response = call_app("POST", ROOT_PATH, JSON.generate(wire))
    assert_equal 201, response[0], response[2]
    assert_private(response)
    assert_equal 2, @calls.length
    assert_equal ["fixture-principal", "fixture-principal"], @resolved
    assert_equal ["fixture-principal-1", "fixture-principal-2"], @calls.map { |request| request[:headers]["x-handrail-application-session-token"] }
    assert_same @calls[0][:body], @calls[1][:body]
    assert @calls[0][:body].frozen?
    assert_equal ["/prefix/api/mobile-bug-reports"] * 2, @calls.map { |request| request[:uri].path }
  end

  def test_notification_consent_is_opt_in_and_normalized_without_side_effects
    [nil, [], true, { "notify_on_resolution" => "true" }, { "notify_on_resolution" => false },
      { "notify_on_resolution" => true }, { "notify_on_resolution" => true, "consent_version" => "\u00a0\ufeff" }].each do |preference|
      @calls.clear
      response = call_app("POST", ROOT_PATH, JSON.generate(wire.merge("reporter_notification" => preference)))
      assert_equal 201, response[0], response[2]
      assert_equal 1, @calls.length
      sent = JSON.parse(@calls.first[:body])
      if preference.is_a?(Hash) && preference["notify_on_resolution"] == true
        assert_equal({ "notify_on_resolution" => true, "consent_version" => "v1" }, sent["reporter_notification"])
      else
        refute sent.key?("reporter_notification")
      end
    end
  end

  def test_upstream_errors_redirects_and_unreadable_successes_are_generic
    [400, 401, 403, 429, 500, 302, 200].each do |status|
      @calls.clear
      @responses = [{ :status => status, :body => "private-diagnostic", :headers => { "set-cookie" => "evil=1" } }] * 2
      response = call_app("POST", ROOT_PATH, "{}")
      assert_equal 502, response[0], response[2]
      assert_equal({ "error" => "bug_reporter_upstream_failed" }, JSON.parse(response[2]))
      assert_private(response)
      refute_includes response[2], "private-diagnostic"
    end
  end

  def test_unconfigured_and_disabled_mounts_fail_closed
    Rails.application.config.handrail_bug_reporter_factory = nil
    assert_rejected(503, call_app("POST", ROOT_PATH, "{}"))
    configure(:enabled => false)
    assert_rejected(404, call_app("GET", ROOT_PATH + "/policy"))
    configure(:report_token => nil)
    assert_rejected(503, call_app("GET", ROOT_PATH + "/policy"))
  end

  def test_network_and_boundary_failures_are_generic
    [IOError.new("private-network-message"), RuntimeError.new("private-boundary-message")].each do |error|
      @responses = [error, error]
      response = call_app("POST", ROOT_PATH, "{}")
      assert_equal 502, response[0], response[2]
      assert_equal({ "error" => "bug_reporter_upstream_failed" }, JSON.parse(response[2]))
      assert_private(response)
    end
  end
end
