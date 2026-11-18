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

class MountedInformationRequestChecks < Minitest::Test
  include MountedForwardingSupport

  PATH = ROOT_PATH + "/bugs/bug-123/information-requests/rfi-1/answer"
  UPSTREAM = "/prefix/api/mobile-bug-reports/bugs/bug-123/information-requests/rfi-1/answer"
  ACCEPTED = '{"contract_version":"v1","bug_id":"bug-123","information_request_id":"rfi-1","answered":true,"replayed":false,"analysis_resumed":true}'

  def post_answer(body = { "option" => "Card" }, headers = {}, path = PATH)
    call_app("POST", path, JSON.generate(body), headers)
  end

  def test_answer_is_stripped_scoped_and_forwarded_with_report_and_session_tokens
    @responses << { :status => 200, :body => ACCEPTED }
    body = { "option" => " Card ", "answer" => " Saved card ", "project_id" => "spoof",
      "information_request_id" => "rfi-other", "application_session_token" => "json-session", "extra" => { "x" => 1 } }
    response = post_answer(body, { "HTTP_AUTHORIZATION" => "Bearer caller",
      "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "caller", "HTTP_X_HANDRAIL_BUG_REPORT_TOKEN" => "caller" },
      PATH + "?project_id=spoof&environment=production&application_session_token=spoof")
    assert_equal 200, response[0], response[2]
    assert_equal ACCEPTED, response[2]
    assert_private(response)
    assert_equal 1, @calls.length
    sent = @calls.first
    assert_equal "POST", sent[:method]
    assert_equal UPSTREAM, sent[:uri].path
    assert_equal({ "project_id" => "server/project + one", "environment" => "staging" }, URI.decode_www_form(sent[:uri].query).to_h)
    assert_equal({ "option" => "Card", "answer" => "Saved card" }, JSON.parse(sent[:body]))
    assert_equal({ "authorization" => "Bearer hbr_server_fixture", "accept" => "application/json",
      "content-type" => "application/json", "x-handrail-application-session-token" => "alice-1" }, sent[:headers])
  end

  def test_option_only_and_answer_only_bodies
    [[{ "option" => "Card" }, { "option" => "Card" }], [{ "answer" => "Saved card" }, { "answer" => "Saved card" }],
      [{ "option" => "", "answer" => "Saved card" }, { "answer" => "Saved card" }]].each do |body, expected|
      @calls.clear
      response = post_answer(body)
      assert_equal 201, response[0], response[2]
      assert_equal expected, JSON.parse(@calls.first[:body])
    end
  end

  def test_invalid_answer_bodies_never_resolve_identity_or_call_http
    [{}, { "option" => nil, "answer" => nil }, { "option" => " ", "answer" => "﻿" }, { "option" => 1 },
      { "answer" => ["text"] }, { "option" => { "x" => 1 } }, { "unrelated" => "x" }].each do |body|
      response = post_answer(body)
      assert_equal 400, response[0], response[2]
      assert_equal({ "error" => "Choose an option or write an answer.", "code" => "information_request_answer_invalid" },
        JSON.parse(response[2]))
      assert_private(response)
      assert_empty @calls
    end
    [nil, [], "text", 1].each { |body| assert_rejected(400, post_answer(body)) }
    ["", "{", "\xff".b].each { |bytes| assert_rejected(400, call_app("POST", PATH, bytes)) }
  end

  def test_handrail_errors_pass_through_status_and_error_code
    { 400 => ["Choose one of the offered options or write an answer.", "information_request_answer_invalid"],
      404 => ["The question was not found.", "information_request_not_found"],
      409 => ["This question was already answered.", "information_request_already_answered"] }.each do |status, (message, code)|
      @calls.clear
      @responses = [{ :status => status, :body => JSON.generate("error" => message, "code" => code) }]
      response = post_answer
      assert_equal status, response[0]
      assert_equal({ "error" => message, "code" => code }, JSON.parse(response[2]))
      assert_private(response)
      assert_equal 1, @calls.length
    end
    @calls.clear
    @responses = [{ :status => 409, :body => "not json hbr_server_fixture" }]
    response = post_answer
    assert_equal 409, response[0]
    assert_equal({ "error" => "bug_reporting_rejected", "code" => "bug_reporting_rejected" }, JSON.parse(response[2]))
    @responses = [{ :status => 409, :body => JSON.generate("error" => "Denied hbr_server_fixture alice-3", "code" => "x") }]
    response = post_answer
    refute_includes response[2], "hbr_server_fixture"
    @responses = [IOError.new("private network failure")] * 2
    response = post_answer
    assert_equal 502, response[0]
    assert_equal({ "error" => "bug_reporting_unavailable", "code" => "bug_reporting_unavailable" }, JSON.parse(response[2]))
    refute_includes response[2], "private network failure"
  end

  def test_csrf_is_mandatory_even_when_host_protection_is_disabled
    refute Rails.application.config.action_controller.allow_forgery_protection
    ["", "invalid", @csrf.reverse].each do |token|
      assert_rejected(403, post_answer({ "option" => "Card" }, "HTTP_X_CSRF_TOKEN" => token))
    end
    assert_rejected(403, post_answer({ "option" => "Card" }, "HTTP_COOKIE" => ""))
    assert_rejected(403, post_answer({ "option" => "Card", "authenticity_token" => @csrf }, "HTTP_X_CSRF_TOKEN" => ""))
  end

  def test_origin_content_type_and_method_enforcement
    [{ "HTTP_ORIGIN" => "https://evil.example" }, { "HTTP_SEC_FETCH_SITE" => "cross-site" }].each do |headers|
      assert_rejected(403, post_answer({ "option" => "Card" }, headers))
    end
    [nil, "text/plain", "application/x-www-form-urlencoded"].each do |type|
      assert_rejected(415, post_answer({ "option" => "Card" }, "CONTENT_TYPE" => type))
    end
    assert_rejected(413, call_app("POST", PATH, "", {}, LIMIT + 1, BoundedInput.new("{}")))
    %w[GET HEAD PUT PATCH DELETE OPTIONS].each do |method|
      response = call_app(method, PATH, JSON.generate("option" => "Card"))
      assert_rejected(405, response, method == "HEAD")
      assert_equal "POST", response[1]["allow"] || response[1]["Allow"]
    end
  end

  def test_ids_are_single_encoded_segments_and_unsafe_ids_never_reach_http
    { "bug%2D123" => "bug-123", "bug.json" => "bug.json", "a+b" => "a%2Bb", "caf%C3%A9" => "caf%C3%A9" }.each do |incoming, expected|
      @calls.clear
      response = post_answer({ "option" => "Card" }, {}, ROOT_PATH + "/bugs/" + incoming + "/information-requests/" + incoming + "/answer")
      assert_equal 201, response[0], response[2]
      assert_equal "/prefix/api/mobile-bug-reports/bugs/#{expected}/information-requests/#{expected}/answer", @calls.first[:uri].path
    end
    @calls.clear
    @resolved.clear
    %w[% %2 %GG %20 . .. %2e%2e a%2Fb a%5Cb a%3Fb a%23b a%25b a%00b].each do |id|
      assert_rejected(404, post_answer({ "option" => "Card" }, {}, ROOT_PATH + "/bugs/" + id + "/information-requests/rfi-1/answer"))
      assert_rejected(404, post_answer({ "option" => "Card" }, {}, ROOT_PATH + "/bugs/bug-123/information-requests/" + id + "/answer"))
    end
    %w[/bugs/bug-123/information-requests /bugs/bug-123/information-requests/rfi-1
      /bugs/bug-123/information-requests//answer /bugs//information-requests/rfi-1/answer
      /bugs/bug-123/information-requests/rfi-1/answer/extra /bugs/bug-123/information-requests/rfi-1/answer.json
      /bugs/bug-123/information-requests/rfi-1/withdraw].each do |path|
      assert_rejected(404, post_answer({ "option" => "Card" }, {}, ROOT_PATH + path))
    end
  end

  def test_unconfigured_disabled_and_unauthorized_mounts_fail_closed_without_http
    Rails.application.config.handrail_bug_reporter_factory = nil
    assert_rejected(503, post_answer)
    configure(:enabled => false)
    assert_rejected(404, post_answer)
    configure({}, :authorize_request => lambda { |_| false })
    assert_rejected(403, post_answer)
  end
end
