require "test_helper"

class AuthorizationTest < ScaffoldTestCase
  def test_host_authorization_on_every_reporter_route
    output = run_ruby('require File.expand_path("test/fixtures/mounted/authorization_checks")',
      "RAILS_ENV" => "test", "RACK_ENV" => "test")
    assert_match(/0 failures, 0 errors/, output)
  end
end
