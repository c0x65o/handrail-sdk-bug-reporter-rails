require "test_helper"

class SubscriptionRouteTest < ScaffoldTestCase
  def test_mounted_subscription_with_real_routing_sessions_and_csrf
    output = run_ruby('require File.expand_path("test/fixtures/mounted/subscription_checks")',
      "RAILS_ENV" => "test", "RACK_ENV" => "test")
    assert_match(/0 failures, 0 errors/, output)
  end
end
