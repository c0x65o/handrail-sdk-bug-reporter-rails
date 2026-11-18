require "minitest/autorun"
require "handrail/bug_reporter/client"
require_relative "support/no_network"

class InformationRequestTest < Minitest::Test
  SDK = Handrail::BugReporter
  TOKEN = "hbr_information_report_secret"
  SESSION = "information-session-secret"
  HISTORY = File.read(File.expand_path("fixtures/js_v0.4.49_history.json", File.dirname(__FILE__))).freeze
  QUESTION = { "id" => "rfi-1", "current_behavior" => "Checkout shows a spinner.",
    "question" => "Which payment method did you use?", "options" => ["Card", "PayPal", "Gift card"],
    "allows_written_answer" => true, "asked_at" => "2026-11-18T12:00:00.000Z", "response_allowed" => true }.freeze

  def setup
    @calls = []
    @status = 200
    @headers = { "x-request-id" => "answer-request-1" }
    @body = result_body
  end

  def result_body(bug_id = "bug-123", request_id = "rfi-1")
    { "contract_version" => "v1", "bug_id" => bug_id, "information_request_id" => request_id,
      "answered" => true, "replayed" => false, "analysis_resumed" => true }
  end

  def configuration(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/prefix/api",
      :project_id => " project &+/雪 ", :environment => " STAGING &+ ",
      :report_token => TOKEN }.merge(options))
  end

  def client(config = configuration, options = {})
    http = lambda do |*args|
      @calls << args
      { :status => @status, :body => @body.is_a?(String) ? @body : JSON.generate(@body), :headers => @headers }
    end
    SDK::Factory.new(config, { :http => http,
      :resolve_application_session_token => lambda { |_| SESSION } }.merge(options)).for_request(:host_request)
  end

  def answer(reporter = client, options = {})
    reporter.answer_information_request(**{ :bug_id => "bug-123", :request_id => "rfi-1", :option => "Card" }.merge(options))
  end

  def assert_rejected
    error = assert_raises(SDK::Error) { yield }
    assert_equal :tracking_rejected, error.code
    assert_nil error.cause
    error
  end

  def test_exact_path_body_headers_and_configuration_scope
    @body = result_body("bug 雪+?project_id=evil", "rfi-x?y")
    result = answer(client, :bug_id => " ﻿bug 雪+?project_id=evil ", :request_id => " rfi-x?y ",
      :option => " Card ", :answer => " It was a saved card. ")
    uri, method, headers, body = @calls.last
    assert_equal "POST", method
    assert_equal "handrail.example", uri.host
    assert_equal "/prefix/api/mobile-bug-reports/bugs/bug%20%E9%9B%AA%2B%3Fproject_id%3Devil" \
      "/information-requests/rfi-x%3Fy/answer", uri.path
    assert_equal "project_id=project+%26%2B%2F%E9%9B%AA&environment=staging+%26%2B", uri.query
    assert_equal({ "option" => "Card", "answer" => "It was a saved card." }, JSON.parse(body))
    assert_equal "Bearer #{TOKEN}", headers["authorization"]
    assert_equal SESSION, headers["x-handrail-application-session-token"]
    assert_equal "application/json", headers["content-type"]
    assert_equal 1, @calls.length
    assert_equal "bug 雪+?project_id=evil", result[:bug_id]
    assert_equal "rfi-x?y", result[:information_request_id]
  end

  def test_option_only_answer_only_and_both_send_only_supplied_fields
    [[{ :option => "Card" }, { "option" => "Card" }],
      [{ :option => nil, :answer => "Saved card" }, { "answer" => "Saved card" }],
      [{ :option => "  ", :answer => "Saved card" }, { "answer" => "Saved card" }],
      [{ :option => "PayPal", :answer => "Also tried card" }, { "option" => "PayPal", "answer" => "Also tried card" }]].each do |options, expected|
      result = answer(client, options)
      assert_equal expected, JSON.parse(@calls.last[3])
      assert_equal({ :contract_version => "v1", :bug_id => "bug-123", :information_request_id => "rfi-1",
        :answered => true, :replayed => false, :analysis_resumed => true }, result)
      assert result.frozen?
    end
  end

  def test_replayed_answers_project_nullable_analysis_resumed
    @body = result_body.merge("replayed" => true, "analysis_resumed" => nil, "private" => "ignored")
    result = answer
    assert_equal true, result[:replayed]
    assert_nil result[:analysis_resumed]
    refute result.key?(:private)
  end

  def test_missing_ids_or_answer_are_rejected_before_identity_or_http
    resolutions = 0
    reporter = client(configuration, :resolve_application_session_token => lambda { |_| resolutions += 1; SESSION })
    [nil, "", " ", ".", "..", "a/b", "a\\b", "a%2Fb", "a\u0000b", 1].each do |id|
      assert_rejected { answer(reporter, :bug_id => id) }
      assert_rejected { answer(reporter, :request_id => id) }
    end
    [{ :option => nil, :answer => nil }, { :option => "", :answer => " ﻿ " }, { :option => 1 },
      { :option => nil, :answer => ["text"] }, { :option => { "x" => 1 }, :answer => "text" },
      { :option => "\xff".dup.force_encoding("UTF-8") }].each do |options|
      assert_rejected { answer(reporter, options) }
    end
    assert_raises(ArgumentError) { reporter.answer_information_request(:bug_id => "bug-123") }
    assert_equal 0, resolutions
    assert_empty @calls
    assert_empty NoNetwork::ATTEMPTS
  end

  def test_result_must_be_v1_answered_and_match_requested_ids
    [nil, [], "ok", {}, result_body.merge("contract_version" => "v2"), result_body.merge("answered" => false),
      result_body.merge("replayed" => "false"), result_body.merge("analysis_resumed" => "yes"),
      result_body("bug-999"), result_body("bug-123", "rfi-2")].each do |body|
      @body = body
      error = assert_rejected { answer }
      assert_equal 200, error.status_code
      assert_equal "answer-request-1", error.request_id
    end
  end

  def test_upstream_rejections_keep_status_and_sanitized_code
    { 400 => "information_request_answer_invalid", 404 => "information_request_not_found",
      409 => "information_request_already_answered" }.each do |status, code|
      @status = status
      @body = { "error" => "Rejected #{TOKEN} #{SESSION}", "code" => code }
      error = assert_rejected { answer }
      assert_equal status, error.status_code
      assert_equal code, error.upstream_code
      assert_equal "Rejected [REDACTED] [REDACTED]", error.upstream_message
      refute_includes error.inspect, SESSION
    end
  end

  def test_network_failure_and_invalid_configuration
    error = assert_raises(SDK::Error) { answer(client(configuration, :http => lambda { |*_| raise IOError, SESSION })) }
    assert_equal :tracking_unavailable, error.code
    [configuration(:enabled => false), configuration(:report_token => nil)].each do |config|
      assert_equal :invalid_configuration, assert_raises(SDK::Error) { answer(client(config)) }.code
    end
  end

  def test_history_records_tolerate_and_project_information_requests
    bug = JSON.parse(HISTORY)["bug"]
    detail = lambda { |record| { "contract_version" => "v1", "bug" => record } }
    @body = detail.call(bug)
    assert_nil client.get_bug("bug-123")[:information_request]
    @body = detail.call(bug.merge("information_request" => nil))
    assert_nil client.get_bug("bug-123")[:information_request]
    @body = detail.call(bug.merge("information_request" => QUESTION.merge("future" => { "x" => 1 })))
    projected = client.get_bug("bug-123")[:information_request]
    assert_equal({ :id => "rfi-1", :current_behavior => "Checkout shows a spinner.",
      :question => "Which payment method did you use?", :asked_at => "2026-11-18T12:00:00.000Z",
      :options => ["Card", "PayPal", "Gift card"], :allows_written_answer => true, :response_allowed => true }, projected)
    assert projected.frozen?
    assert projected[:options].frozen?
    @body = detail.call(bug.merge("information_request" => QUESTION.merge("current_behavior" => nil)))
    assert_nil client.get_bug("bug-123")[:information_request][:current_behavior]
    # Malformed requests are dropped; the record itself stays valid.
    [[], "rfi-1", 1, true, {}, QUESTION.merge("id" => nil), QUESTION.merge("question" => " "),
      QUESTION.merge("id" => 7)].each do |value|
      @body = detail.call(bug.merge("information_request" => value))
      record = client.get_bug("bug-123")
      assert_equal "bug-123", record[:id]
      assert_nil record[:information_request]
    end
    @body = detail.call(bug.merge("information_request" => QUESTION.merge("options" => "Card")))
    assert_equal [], client.get_bug("bug-123")[:information_request][:options]
    @body = { "contract_version" => "v1", "bugs" => [bug.merge("information_request" => QUESTION), bug.merge("information_request" => [])],
      "pagination" => { "limit" => 10, "has_more" => false } }
    page = client.list_bugs
    assert_equal "rfi-1", page[:bugs][0][:information_request][:id]
    assert_nil page[:bugs][1][:information_request]
  end
end
