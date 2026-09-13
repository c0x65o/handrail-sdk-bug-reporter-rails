require "support/no_network"
require "minitest/autorun"
require "rack/mock"
require_relative "config/application"
MountedHost::Application.initialize!
require_relative "forwarding_support"

class MountedAcceptedResponseChecks < Minitest::Test
  include MountedForwardingSupport

  def test_all_routes_preserve_acceptance_and_valid_wire_bytes_without_retry
    configure({}, :authorize_request => lambda { |_| true })
    routes = [["POST", ""], ["GET", "/policy"], ["GET", "/mine"],
      ["GET", "/bugs/bug-123"], ["POST", "/bugs/bug-123/subscription"],
      ["PUT", "/bugs/bug-123/archive"], ["DELETE", "/bugs/bug-123/archive"],
      ["POST", "/mine/archive-closed"]]
    bodies = [nil, "", "accepted but not JSON hbr_private_diagnostic", "\xff".b,
      "null", "false", "42", '"accepted"', "[]",
      '{"bug_id":"canonical-id","event_id":"other-id","precise":0.12345678901234567890123456789,"integer":9007199254740993}']
    routes.each do |method, path|
      bodies.each_with_index do |bytes, index|
        [200, 201, 202, 204, 205].each do |status|
          @calls.clear
          @resolved.clear
          @responses = [{ :status => status, :body => bytes }]
          result = call_app(method, ROOT_PATH + path, JSON.generate(wire))
          assert_equal status, result[0], [method, path, bytes].inspect
          expected = [204, 205].include?(status) || index < 2 ? "" : index < 4 ? "null" : bytes
          assert_equal expected, result[2]
          assert_equal 1, @calls.length
          assert_equal 1, @resolved.length
          assert_equal "private, no-store", result[1]["cache-control"]
          refute_includes result[2], "hbr_private_diagnostic"
          if method == "POST" && path == ""
            assert_equal "browser-event-id", JSON.parse(@calls.first[:body])["event_id"]
          end
        end
      end
    end
  end
end
