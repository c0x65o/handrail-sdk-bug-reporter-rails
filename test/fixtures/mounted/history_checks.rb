require "support/no_network"
require "minitest/autorun"
require "rack/mock"
require File.expand_path("config/application", File.dirname(__FILE__))
require File.expand_path("forwarding_support", File.dirname(__FILE__))

MountedHost::Application.initialize!

# Fixture-only selection of two host principals, stored in real signed sessions.
class SessionFixtureController
  def show
    session[:principal] = params[:fixture_principal] == "bob" ? "bob" : "alice"
    render :json => { :csrf => form_authenticity_token }
  end
end

class MountedHistoryChecks < Minitest::Test
  include MountedForwardingSupport

  ROUTES = [
    ["GET", "/mine", "/mine"],
    ["GET", "/bugs/bug-123", "/bugs/bug-123"],
    ["PUT", "/bugs/bug-123/archive", "/bugs/bug-123/archive"],
    ["DELETE", "/bugs/bug-123/archive", "/bugs/bug-123/archive"],
    ["POST", "/mine/archive-closed", "/mine/archive-closed"]
  ].freeze

  def test_allowed_routes_preserve_canonical_json_scope_and_identity
    detail = { "bug_id" => "bug-123", "status_version" => 2,
      "status" => { "group" => "closed", "label" => "Resolved", "version" => 3 },
      "summary" => { "version" => 1, "text" => "Canonical summary", "future_field" => [nil, false] },
      "journey" => { "version" => 1, "events" => [{ "kind" => "resolved", "at" => "2026-09-09" }] } }
    bodies = [{ "bugs" => [detail], "next_cursor" => "opaque", "version" => 4 }, detail,
      { "archived" => true, "bug" => detail }, { "archived" => false, "bug" => detail },
      { "archived_count" => 2, "version" => 1 }]
    ROUTES.each_with_index do |(method, path, upstream), index|
      @calls.clear
      @responses << { :status => 200, :body => JSON.generate(bodies[index]) }
      response = call_app(method, ROOT_PATH + path + "?project_id=evil&environment=production&limit=100&application_session_token=evil",
        '{"project_id":"evil","environment":"production","application_session_token":"evil"}',
        "HTTP_AUTHORIZATION" => "Bearer caller", "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "caller",
        "HTTP_X_HANDRAIL_BUG_REPORT_TOKEN" => "caller", "CONTENT_TYPE" => nil)
      assert_equal 200, response[0], response[2]
      assert_equal bodies[index], JSON.parse(response[2])
      assert_private(response)
      assert_equal 1, @calls.length
      sent = @calls.first
      assert_equal "/prefix/api/mobile-bug-reports" + upstream, sent[:uri].path
      assert_equal method, sent[:method]
      query = { "project_id" => "server/project + one", "environment" => "staging" }
      query["limit"] = "100" if path == "/mine"
      assert_equal query, URI.decode_www_form(sent[:uri].query).to_h
      assert_nil sent[:body]
      assert_equal({ "authorization" => "Bearer hbr_server_fixture", "accept" => "application/json",
        "x-handrail-application-session-token" => "alice-#{index + 1}" }, sent[:headers])
    end
  end

  def test_route_method_allowlist
    ROUTES.map { |route| route[1] }.uniq.each do |path|
      allowed = ROUTES.select { |route| route[1] == path }.map { |route| route[0] }
      (%w[GET POST PUT DELETE PATCH HEAD OPTIONS] - allowed).each do |method|
        response = call_app(method, ROOT_PATH + path)
        assert_rejected(405, response, method == "HEAD")
        assert_equal allowed.join(", "), response[1]["allow"] || response[1]["Allow"]
      end
    end
    %w[/mine.json /mine/extra /mine/archive-closed/extra /bugs /bugs/ /bugs//archive
      /bugs/a/other /bugs/a/archive/extra /bugs/a/subscription/extra].each do |path|
      %w[GET POST PUT DELETE].each { |method| assert_rejected(404, call_app(method, ROOT_PATH + path)) }
    end
  end

  def test_history_json_bytes_are_not_reserialized
    canonical = "{\n  \"summary\": {\"version\": 1, \"score\": 0.1234567890123456789}, \"journey\": []\n}"
    ROUTES.each do |method, path, _upstream|
      @responses << { :status => 200, :body => canonical }
      response = call_app(method, ROOT_PATH + path)
      assert_equal 200, response[0]
      assert_equal canonical, response[2]
    end
  end

  def test_history_query_is_flat_first_value_allowlist
    response = call_app("GET", ROOT_PATH + "/mine?limit=7&limit=8&cursor=&cursor=later&search=one+two%26three&search=later&status_group=closed&sort=oldest&visibility=archived&visibility=active&bad[=x&limit[]=99&profile_key=spoof")
    assert_equal 201, response[0], response[2]
    assert_equal({ "project_id" => "server/project + one", "environment" => "staging", "limit" => "7",
      "search" => "one two&three", "status_group" => "closed", "sort" => "oldest", "visibility" => "archived" },
      URI.decode_www_form(@calls.first[:uri].query).to_h)
    @calls.clear
    response = call_app("GET", ROOT_PATH + "/mine?limit=&cursor=&search=+&status_group=&sort=&visibility=")
    assert_equal 201, response[0]
    assert_equal({ "project_id" => "server/project + one", "environment" => "staging", "search" => " " },
      URI.decode_www_form(@calls.first[:uri].query).to_h)
  end

  def test_encoded_ids_remain_one_resource_segment_without_format_truncation
    { "bug%2D123" => "bug-123", "bug.json" => "bug.json", "a%2Eb" => "a.b",
      "%20bug%20" => "bug", "a+b" => "a%2Bb", "a%20b" => "a%20b",
      "caf%C3%A9" => "caf%C3%A9" }.each do |incoming, expected|
      [["GET", ""], ["PUT", "/archive"], ["DELETE", "/archive"]].each do |method, suffix|
        @calls.clear
        response = call_app(method, ROOT_PATH + "/bugs/" + incoming + suffix)
        assert_equal 201, response[0], "#{incoming}: #{response[2]}"
        assert_equal "/prefix/api/mobile-bug-reports/bugs/" + expected + suffix, @calls.first[:uri].path
        assert_nil @calls.first[:uri].fragment
      end
    end
  end

  def test_unsafe_or_malformed_ids_are_rejected_before_upstream
    %w[% %2 %GG %FF %C0%AF %20 %09 . .. %2e %2e%2e %252e%252e
      a%2Fb a%2fb a%252Fb a%5Cb a%3Fb a%23b a%25b a%00b a%0Ab a%0Db].each do |id|
      [["GET", ""], ["PUT", "/archive"], ["DELETE", "/archive"]].each do |method, suffix|
        assert_rejected(404, call_app(method, ROOT_PATH + "/bugs/" + id + suffix))
      end
    end
  end

  def test_archive_writes_are_bodyless_and_never_read_the_input
    input = Object.new
    def input.read(*args); raise "Archive body was read"; end
    ROUTES.reject { |route| route[0] == "GET" }.each do |method, path, _upstream|
      response = call_app(method, ROOT_PATH + path, "", {}, LIMIT + 1, input)
      assert_equal 201, response[0], response[2]
      assert_nil @calls.last[:body]
      refute @calls.last[:headers].key?("content-type")
      assert_private(response)
      response = call_app(method, ROOT_PATH + path, "", "CONTENT_TYPE" => nil)
      assert_equal 201, response[0], response[2]
      assert_nil @calls.last[:body]
    end
  end

  def test_each_archive_write_requires_a_valid_session_csrf_header
    refute Rails.application.config.action_controller.allow_forgery_protection
    ROUTES.reject { |route| route[0] == "GET" }.each do |method, path, _upstream|
      ["", "invalid", @csrf.reverse].each do |token|
        assert_rejected(403, call_app(method, ROOT_PATH + path, "", "HTTP_X_CSRF_TOKEN" => token))
      end
      assert_rejected(403, call_app(method, ROOT_PATH + path, "", "HTTP_COOKIE" => ""))
      assert_rejected(403, call_app(method, ROOT_PATH + path + "?authenticity_token=" + @csrf,
        JSON.generate("authenticity_token" => @csrf), "HTTP_X_CSRF_TOKEN" => ""))
      assert_rejected(403, call_app(method, ROOT_PATH + path, "", "HTTP_ORIGIN" => nil, "HTTP_X_CSRF_TOKEN" => ""))
    end
  end

  def test_same_origin_enforcement_for_all_history_routes
    ROUTES.each do |method, path, _upstream|
      [{ "HTTP_ORIGIN" => "https://evil.example" }, { "HTTP_ORIGIN" => "null" },
        { "HTTP_SEC_FETCH_SITE" => "cross-site" }].each do |headers|
        assert_rejected(403, call_app(method, ROOT_PATH + path, "", headers))
      end
    end
  end

  def test_request_identity_is_isolated_and_foreign_ownership_statuses_pass_through
    alice_cookie, alice_csrf = @cookie, @csrf
    login = call_app("GET", "/fixture-session?fixture_principal=bob", "", "HTTP_COOKIE" => "")
    bob_cookie = Array(login[1]["set-cookie"] || login[1]["Set-Cookie"]).first.split(";", 2).first
    bob_csrf = JSON.parse(login[2]).fetch("csrf")
    ROUTES.each do |method, path, _upstream|
      @calls.clear
      @resolved.clear
      [403, 401].each do |status|
        @responses << { :status => status, :body => '{"error":"hbr_server_fixture alice-1 private-diagnostic"}' }
        response = call_app(method, ROOT_PATH + path, "", "HTTP_COOKIE" => bob_cookie, "HTTP_X_CSRF_TOKEN" => bob_csrf)
        assert_equal status, response[0], response[2]
        assert_equal({ "error" => "bug_reporting_rejected" }, JSON.parse(response[2]))
        assert_private(response)
      end
      response = call_app(method, ROOT_PATH + path, "", "HTTP_COOKIE" => alice_cookie, "HTTP_X_CSRF_TOKEN" => alice_csrf)
      assert_equal 201, response[0]
      assert_equal ["bob", "bob", "alice"], @resolved
      assert_equal ["bob-1", "bob-2", "alice-3"], @calls.map { |sent| sent[:headers]["x-handrail-application-session-token"] }
    end
    @calls.clear
    @resolved.clear
    assert_rejected(403, call_app("PUT", ROOT_PATH + "/bugs/a/archive", "", "HTTP_COOKIE" => bob_cookie, "HTTP_X_CSRF_TOKEN" => alice_csrf))
  end

  def test_anonymous_reads_do_not_take_identity_from_caller_headers
    @responses << { :status => 401, :body => '{"error":"not_authenticated"}' }
    response = call_app("GET", ROOT_PATH + "/mine", "", "HTTP_COOKIE" => "",
      "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "spoof")
    assert_equal 401, response[0]
    refute @calls.first[:headers].key?("x-handrail-application-session-token")
    assert_private(response)
  end

  def test_every_history_retry_refreshes_the_same_request_identity
    ROUTES.each do |method, path, _upstream|
      @calls.clear
      @resolved.clear
      @responses << { :status => 503, :body => '{"error":"private-diagnostic"}' }
      response = call_app(method, ROOT_PATH + path)
      assert_equal 201, response[0], response[2]
      assert_equal ["alice", "alice"], @resolved
      assert_equal ["alice-1", "alice-2"], @calls.map { |sent| sent[:headers]["x-handrail-application-session-token"] }
      assert_equal @calls.first[:uri], @calls.last[:uri]
      assert @calls.all? { |sent| sent[:body].nil? }
      assert_private(response)
    end
  end

  def test_failures_still_return_private_generic_json
    [200, 302, 400, 500].each do |status|
      @responses = [{ :status => status, :body => "private-diagnostic" }] * 2
      response = call_app("GET", ROOT_PATH + "/mine")
      assert_equal 502, response[0]
      assert_equal({ "error" => "bug_reporter_upstream_failed" }, JSON.parse(response[2]))
      assert_private(response)
    end
    Rails.application.config.handrail_bug_reporter_factory = nil
    response = call_app("GET", ROOT_PATH + "/mine")
    assert_equal 503, response[0]
    assert_private(response)
  end
end
