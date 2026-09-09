require "minitest/autorun"
require "handrail/bug_reporter/client"

class NotificationTest < Minitest::Test
  SDK = Handrail::BugReporter
  TOKEN = "hbr_notification_credential"
  PRIVATE = "caller-private@example.test"
  WARNING = "The report was sent, but update notifications could not be enabled."

  def setup
    @calls, @resolved, @sleeps = [], [], []
    @request = Object.new
  end

  def config(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/prefix/api",
      :project_id => " configured-project ", :environment => " StAgInG ",
      :report_token => TOKEN }.merge(options))
  end

  def report(notification = { :notify_on_resolution => true })
    { :title => "Broken button", :description => "Clicking does nothing.", :notification => notification }
  end

  def response(body, status = 201)
    { :status => status, :body => JSON.generate(body) }
  end

  def active(options = {})
    { "notification_subscription" => { "active" => true, "created" => true,
      "recipient_hint" => " a***@example.test ", "subscribed_at" => " 2026-09-09T12:00:00Z " }.merge(options) }
  end

  def client(options = {}, resolver = nil, &boundary)
    resolver ||= lambda { |_request| "fresh-session-#{@resolved.length}" }
    SDK::Factory.new(config(options),
      :sleeper => lambda { |delay| @sleeps << delay },
      :resolve_application_session_token => lambda { |request|
        assert_same @request, request
        @resolved << request
        resolver.call(request)
      },
      :http => lambda { |*args|
        @calls << args
        boundary ? boundary.call(*args) : response(@calls.length == 1 ? { "bug_id" => "bug-123" } : active)
      }).for_request(@request)
  end

  def assert_submitted(result, bug_id = "bug-123", status = 202)
    assert result.submitted?
    assert_equal :submitted, result.status
    assert_equal status, result.status_code
    bug_id.nil? ? assert_nil(result.bug_id) : assert_equal(bug_id, result.bug_id)
    assert result.frozen?
  end

  def assert_warning(result)
    assert_nil result.notification_subscription
    assert_equal WARNING, result.notification_warning
    assert result.notification_warning.frozen?
  end

  def test_accepted_report_subscribes_with_only_consent_and_configured_scope
    input = report(:notify_on_resolution => true, :consent_version => " v2 ",
      :recipient => PRIVATE, :email => PRIVATE, :report_token => PRIVATE,
      :application_session_token => PRIVATE, :project_id => "attacker", :environment => "production")
    input.merge!(:email => PRIVATE, :report_token => PRIVATE, :application_session_token => PRIVATE,
      :project_id => "attacker", :environment => "production", :reporter_notification => { :email => PRIVATE })
    result = client.submit(input)
    assert_submitted(result, "bug-123", 201)
    assert_nil result.notification_warning
    subscription = result.notification_subscription
    assert_equal true, subscription.active
    assert_equal true, subscription.created
    assert_equal "a***@example.test", subscription.recipient_hint
    assert_equal "2026-09-09T12:00:00Z", subscription.subscribed_at
    assert_equal 2, @calls.length
    uri, method, headers, bytes = @calls.last
    assert_equal "/prefix/api/mobile-bug-reports/bugs/bug-123/subscription", uri.path
    assert_equal({ "project_id" => "configured-project", "environment" => "staging" }, URI.decode_www_form(uri.query).to_h)
    assert_equal "POST", method
    assert_equal "Bearer #{TOKEN}", headers["authorization"]
    assert_equal "fresh-session-2", headers["x-handrail-application-session-token"]
    consent = { "notify_on_resolution" => true, "consent_version" => "v2" }
    assert_equal({ "reporter_notification" => consent }, JSON.parse(bytes))
    intake = JSON.parse(@calls.first[3])
    assert_equal consent, intake["reporter_notification"]
    assert_equal "configured-project", intake["project_id"]
    assert_equal "staging", intake["environment"]
    @calls.each { |call| refute_includes call[3], PRIVATE }
    assert_equal ["fresh-session-1", "fresh-session-2"], @calls.map { |call| call[2]["x-handrail-application-session-token"] }
  end

  def test_absent_false_and_nonboolean_preferences_never_send_consent_or_child
    [nil, false, true, [], "true", {}, { :notify_on_resolution => false },
      { :notify_on_resolution => "true" }, { :notify_on_resolution => 1 },
      { :notify_on_resolution => [] }, { :notify_on_resolution => {} }].each do |preference|
      before = @calls.length
      result = client { |*_| response({ "bug_id" => "bug-123" }, 202) }.submit(report(preference))
      assert_submitted(result)
      assert_nil result.notification_subscription
      assert_nil result.notification_warning
      assert_equal before + 1, @calls.length
      refute JSON.parse(@calls.last[3]).key?("reporter_notification")
    end
    result = client.submit(report.tap { |input| input.delete(:notification) })
    assert_nil result.notification_warning
    refute JSON.parse(@calls.last[3]).key?("reporter_notification")
    assert_equal @calls.length, @resolved.length
  end

  def test_string_keys_and_consent_default_custom_and_trim_semantics
    [nil, false, 2, [], {}, "", " \t\u00a0\ufeff", " \u2000v2\ufeff ", "\u0085v3\u0085"].each do |version|
      before = @calls.length
      result = client { |*_| response(@calls.length == before + 1 ? { "bug_id" => "bug-123" } : active) }.
        submit({ "title" => "Broken", "description" => "Details",
          "notification" => { "notify_on_resolution" => true, "consent_version" => version } })
      assert result.notification_subscription
      expected = version == " \u2000v2\ufeff " ? "v2" : (version == "\u0085v3\u0085" ? version : "v1")
      @calls.last(2).each do |call|
        assert_equal expected, JSON.parse(call[3])["reporter_notification"]["consent_version"]
      end
    end
  end

  def test_rejected_and_unavailable_children_preserve_intake_acceptance
    [401, 403, 422, 503, :network, :unexpected].each do |failure|
      before = @calls.length
      reporter = client(:max_attempts => 3) do |*args|
        next response({ "bug_id" => "bug-123", "intake" => true }, 202) if @calls.length == before + 1
        raise EOFError, PRIVATE if failure == :network
        raise PRIVATE if failure == :unexpected
        response({ "error" => { "message" => PRIVATE, "code" => PRIVATE } }, failure)
      end
      output, errors = capture_io do
        result = reporter.submit(report)
        assert_submitted(result)
        assert_warning(result)
        assert_equal({ "bug_id" => "bug-123", "intake" => true }, result.response)
      end
      assert_empty output
      assert_empty errors
      attempts = [503, :network].include?(failure) ? 3 : 1
      assert_equal before + 1 + attempts, @calls.length
      assert_equal 1, @calls.drop(before).count { |call| !call[0].path.end_with?("/subscription") }
    end
  end

  def test_intake_and_child_retries_keep_distinct_stable_bodies_and_prepare_once
    hooks = 0
    input = report(:notify_on_resolution => true, :consent_version => " v2 ")
    reporter = client(:max_attempts => 3) do |*args|
      input[:notification][:consent_version].replace("mutated")
      input[:notification][:notify_on_resolution] = false
      raise EOFError, PRIVATE if [1, 3].include?(@calls.length)
      response(@calls.length == 2 ? { "bug_id" => "bug-123" } : active, 202)
    end
    hook = lambda { |fields|
      hooks += 1
      fields.merge("title" => "Redacted title", "reporter_notification" => { "email" => PRIVATE })
    }
    result = reporter.submit(input.merge(:metadata => { :password => PRIVATE }), :redaction_hooks => [hook])
    assert_submitted(result)
    assert result.notification_subscription
    assert_equal 1, hooks
    assert_equal 4, @calls.length
    assert_same @calls[0][3], @calls[1][3]
    assert_same @calls[2][3], @calls[3][3]
    assert @calls.all? { |call| call[3].frozen? }
    assert_equal [0.25, 0.25], @sleeps
    assert_equal (1..4).map { |n| "fresh-session-#{n}" }, @calls.map { |call| call[2]["x-handrail-application-session-token"] }
    intake = JSON.parse(@calls[0][3])
    assert_equal intake["event_id"], JSON.parse(@calls[1][3])["event_id"]
    assert_equal "Redacted title", intake["title"]
    assert_equal "[REDACTED]", intake["metadata"]["password"]
    @calls.each { |call| assert_equal "v2", JSON.parse(call[3])["reporter_notification"]["consent_version"] }
  end

  def test_hook_cannot_grant_consent
    result = client.submit(report(nil), :redaction_hooks => [lambda { |fields|
      fields.merge("notification" => { "notify_on_resolution" => true },
        "reporter_notification" => { "notify_on_resolution" => true })
    }])
    assert_nil result.notification_subscription
    assert_nil result.notification_warning
    assert_equal 1, @calls.length
    refute JSON.parse(@calls.first[3]).key?("reporter_notification")
  end

  def test_inline_active_is_used_without_child_even_without_bug_id
    result = client { |*_| response(active, 202) }.submit(report)
    assert_submitted(result, nil)
    assert result.notification_subscription.active
    assert_nil result.notification_warning
    assert_equal 1, @calls.length
  end

  def test_inline_inactive_or_invalid_warns_without_fallback
    [nil, false, [], "active", {}, { "active" => false }, { "active" => "true" }, { "active" => 1 }].each do |inline|
      before = @calls.length
      result = client { |*_| response({ "bug_id" => "bug-123", "notification_subscription" => inline }, 202) }.submit(report)
      assert_submitted(result)
      assert_warning(result)
      assert_equal before + 1, @calls.length
    end
  end

  def test_missing_or_unsafe_canonical_ids_warn_without_child_or_id_fallback
    [nil, 1, "", " ", ".", "..", "a/b", "a\\b", "%2f", "%252f", "a\nb", "a\0b", "\tbug-123"].each do |id|
      before = @calls.length
      body = { "bug_id" => id, "event_id" => "event", "id" => "other", "bugId" => "camel", "report" => { "bug_id" => "nested" } }
      result = client { |*_| response(body, 202) }.submit(report)
      assert result.submitted?
      assert_equal 202, result.status_code
      assert_equal body, result.response
      assert_warning(result)
      assert_equal before + 1, @calls.length
    end
  end

  def test_safe_special_characters_are_encoded_as_one_path_segment
    result = client { |*_| response(@calls.length == 1 ? { "bug_id" => " bug ?#☃ " } : active, 202) }.submit(report)
    assert_submitted(result, "bug ?#☃")
    assert result.notification_subscription
    assert_equal "/prefix/api/mobile-bug-reports/bugs/bug%20%3F%23%E2%98%83/subscription", @calls.last[0].path
    assert_nil @calls.last[0].fragment
  end

  def test_malformed_or_inactive_child_response_warns_without_retry
    [nil, "", "not JSON #{PRIVATE}", "null", "[]", "true", "42", '{}',
      JSON.generate(active("active" => false)), JSON.generate(active("active" => "true")),
      "\xff".force_encoding("UTF-8"), '{"notification_subscription":{"active":true,"recipient_hint":"'.b + "\xff".b + '"}}',
      "[" * 110 + "]" * 110].each do |bytes|
      before = @calls.length
      result = client(:max_attempts => 3) { |*args|
        @calls.length == before + 1 ? response({ "bug_id" => "bug-123" }, 202) : { :status => 200, :body => bytes }
      }.submit(report)
      assert_submitted(result)
      assert_warning(result)
      assert_equal before + 2, @calls.length
    end
    assert_empty @sleeps
  end

  def test_subscription_normalization_is_strict_and_immutable
    result = client { |*_| response(active("created" => "true", "recipient_hint" => [], "subscribed_at" => " "), 202) }.submit(report)
    subscription = result.notification_subscription
    assert_equal false, subscription.created
    assert_nil subscription.recipient_hint
    assert_nil subscription.subscribed_at
    assert subscription.frozen?
    result = client { |*_| response(active, 202) }.submit(report)
    subscription = result.notification_subscription
    assert subscription.recipient_hint.frozen?
    assert subscription.subscribed_at.frozen?
    assert_raises(RuntimeError) { subscription.recipient_hint.replace("changed") }
    assert_raises(RuntimeError) { subscription.instance_variable_set(:@active, false) }
    assert_raises(RuntimeError) { result.instance_variable_set(:@notification_warning, "changed") }
  end

  def test_inspection_and_serialization_never_expose_upstream_or_caller_data
    result = client { |*_| response(active("recipient_hint" => PRIVATE, "subscribed_at" => TOKEN).
      merge("bug_id" => PRIVATE, "echo" => "fresh-session-1"), 202) }.submit(report)
    [result, result.notification_subscription].each do |object|
      [object.inspect, object.to_s, object.as_json, object.to_json, JSON.generate(object)].each do |surface|
        [PRIVATE, TOKEN, "fresh-session-1"].each { |value| refute_includes surface, value }
      end
    end
  end

  def test_resolver_exception_on_child_does_not_reuse_identity_or_escape
    resolver = lambda { |_request| @resolved.length == 1 ? "intake-session" : raise(PRIVATE) }
    result = client({ :max_attempts => 3 }, resolver) { |*args|
      @calls.length == 1 ? response({ "bug_id" => "bug-123" }, 202) : response({ "error" => PRIVATE }, 401)
    }.submit(report)
    assert_submitted(result)
    assert_warning(result)
    assert_equal 2, @resolved.length
    refute @calls.last[2].key?("x-handrail-application-session-token")
  end

  def test_disabled_and_rejected_or_malformed_intake_never_attempt_child
    result = client(:enabled => false).submit(report)
    assert_equal :disabled, result.status
    assert_nil result.notification_subscription
    assert_nil result.notification_warning
    assert_empty @calls
    assert_empty @resolved
    [[422, '{}', :submission_rejected], [200, 'null', :malformed_response]].each do |status, bytes, code|
      before = @calls.length
      error = assert_raises(SDK::Error) do
        client { |*_| { :status => status, :body => bytes } }.submit(report)
      end
      assert_equal code, error.code
      assert_equal before + 1, @calls.length
    end
  end
end
