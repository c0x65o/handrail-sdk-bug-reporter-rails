require "test_helper"

class ForwardingTest < ScaffoldTestCase
  def test_mounted_requests_in_an_isolated_real_rails_host
    output = run_ruby('require File.expand_path("test/fixtures/mounted/request_checks")',
      "RAILS_ENV" => "test", "RACK_ENV" => "test")
    assert_match(/0 failures, 0 errors/, output)
  end
end
