require "support/no_network"
require "minitest/autorun"
require "rack/mock"
require File.expand_path("config/application", File.dirname(__FILE__))
MountedHost::Application.initialize!
require File.expand_path("forwarding_support", File.dirname(__FILE__))

class MountedAuthorizationChecks < Minitest::Test
  include MountedForwardingSupport
  ROUTES = [
    ["POST", ""], ["GET", "/policy"], ["GET", "/mine"],
    ["GET", "/bugs/bug-123"], ["PUT", "/bugs/bug-123/archive"],
    ["DELETE", "/bugs/bug-123/archive"], ["POST", "/mine/archive-closed"],
    ["POST", "/bugs/bug-123/subscription"]
  ].freeze

  def authorize_admin
    configure({}, :authorize_request => lambda { |request| request.session[:principal] == "fixture-principal" })
  end

  def each_route(headers = {})
    ROUTES.each do |method, path|
      @calls.clear
      @resolved.clear
      yield call_app(method, ROOT_PATH + path, JSON.generate(wire), headers), method
    end
  end

  def test_admin_has_access_to_all_routes_with_trusted_identity
    authorize_admin
    each_route do |response|
      assert_equal 201, response[0], response[2]
      assert_equal 1, @calls.length
      assert_equal "fixture-principal-1", @calls.first[:headers]["x-handrail-application-session-token"]
      assert_private(response)
    end
  end

  def test_anonymous_and_nonadmin_cannot_forward_even_with_forged_identity
    authorize_admin
    forged = { "HTTP_X_HANDRAIL_APPLICATION_SESSION_TOKEN" => "fixture-principal",
      "HTTP_AUTHORIZATION" => "Bearer fixture-principal", "HTTP_COOKIE" => "" }
    each_route(forged) { |response| assert_rejected(403, response) }
    member = call_app("GET", "/fixture-member-session")
    @cookie = Array(member[1]["set-cookie"] || member[1]["Set-Cookie"]).first.split(";", 2).first
    @csrf = JSON.parse(member[2]).fetch("csrf")
    each_route(forged.reject { |key, _| key == "HTTP_COOKIE" }) do |response|
      assert_rejected(403, response)
      assert_equal "bug_reporting_forbidden", JSON.parse(response[2])["error"]
    end
  end

  def test_invalid_false_truthy_and_raising_authorizers_fail_closed
    [nil, false, "true", lambda { |_| nil }, lambda { |_| "true" },
      lambda { |_| raise "private authorization failure" }].each do |authorizer|
      configure({}, :authorize_request => authorizer)
      each_route do |response|
        assert_rejected(403, response)
        refute_includes response[2], "private authorization failure"
      end
    end
  end

  def test_permanent_and_transient_upstream_errors_on_every_authorized_route
    authorize_admin
    ROUTES.each do |method, path|
      [422, 503].each do |status|
        @calls.clear
        @resolved.clear
        @responses = [{ :status => status, :body => '{"error":"private-upstream-detail"}' }] * 2
        response = call_app(method, ROOT_PATH + path, JSON.generate(wire))
        assert_equal status, response[0]
        assert_equal({ "error" => "bug_reporting_rejected" }, JSON.parse(response[2]))
        assert_equal(status == 422 ? 1 : 2, @calls.length)
        assert_equal @calls.length, @resolved.length
        assert_private(response)
      end
    end
  end

  def test_authorization_is_fresh_and_does_not_replace_csrf
    allowed = true
    configure({}, :authorize_request => lambda { |_| allowed })
    assert_equal 201, call_app("GET", ROOT_PATH + "/policy")[0]
    allowed = false
    each_route { |response| assert_rejected(403, response) }
    allowed = true
    each_route("HTTP_X_CSRF_TOKEN" => "invalid") do |response, method|
      if method != "GET"
        assert_rejected(403, response)
      else
        assert_equal 201, response[0]
      end
    end
  end

  def test_omitted_authorizer_retains_legacy_contract_and_needs_external_guard
    configure
    each_route do |response|
      assert_equal 201, response[0]
      assert_equal 1, @calls.length
    end
    each_route("HTTP_COOKIE" => "") do |response, method|
      if method == "GET"
        assert_equal 201, response[0]
        assert_equal 1, @calls.length
      else
        assert_rejected(403, response)
      end
    end
  end

  def test_resolver_fallback_is_not_host_authorization_or_proof_of_ownership
    configure({}, :authorize_request => lambda { |_| true },
      :resolve_application_session_token => lambda { |_| raise "private resolver failure" })
    each_route do |response|
      assert_equal 201, response[0]
      assert_equal 1, @calls.length
      refute @calls.first[:headers].key?("x-handrail-application-session-token")
      refute_includes response[2], "private resolver failure"
    end
  end
end
