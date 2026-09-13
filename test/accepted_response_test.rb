require "test_helper"

class AcceptedResponseTest < ScaffoldTestCase
  def test_mounted_success_statuses_and_exact_call_counts
    output = run_ruby('require File.expand_path("test/fixtures/mounted/accepted_response_checks")',
      "RAILS_ENV" => "test", "RACK_ENV" => "test")
    assert_match(/0 failures, 0 errors/, output)
  end
end
