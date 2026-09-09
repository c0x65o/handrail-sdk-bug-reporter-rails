require "minitest/autorun"
require "handrail/bug_reporter/client"
require_relative "support/no_network"

class HistoryArchiveTest < Minitest::Test
  SDK = Handrail::BugReporter
  TOKEN = "hbr_archive_report_secret"
  SESSION = "archive-session-secret"
  TIMESTAMP = "2026-08-17T13:00:00.000Z"
  OPERATIONS = [:archive_bug, :restore_bug, :archive_closed_bugs].freeze

  def setup
    @calls = []
    @status = 200
    @headers = { "x-request-id" => "archive-request-1" }
    @body = result_body(:archive_bug)
  end

  # JS v0.4.49 bugArchiveResult/bugArchiveClosedResult at
  # 96b293248611594c388d0fab3af63b1b2d1aae5c, with Rails-safe IDs.
  def result_body(operation, id = "bug-123")
    return { "contract_version" => "v1", "archived_count" => 35 } if operation == :archive_closed_bugs
    { "contract_version" => "v1", "bug_id" => id,
      "archived" => operation == :archive_bug,
      "archived_at" => operation == :archive_bug ? TIMESTAMP : nil }
  end

  def configuration(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/prefix/api",
      :project_id => " project &+/雪 ", :environment => " STAGING &+ ",
      :report_token => TOKEN }.merge(options))
  end

  def client(config = configuration, options = {})
    http = lambda do |*args|
      @calls << args
      { :status => @status, :body => JSON.generate(@body), :headers => @headers }
    end
    SDK::Factory.new(config, { :http => http,
      :resolve_application_session_token => lambda { |_| SESSION } }.merge(options)).for_request(:host_request)
  end

  def invoke(reporter, operation, id = "bug-123")
    operation == :archive_closed_bugs ? reporter.archive_closed_bugs : reporter.send(operation, id)
  end

  def assert_rejected
    error = assert_raises(SDK::Error) { yield }
    assert_equal :tracking_rejected, error.code
    assert_nil error.cause
    error
  end

  def assert_frozen_tree(value)
    assert value.frozen?
    return unless value.is_a?(Hash)
    value.each do |key, child|
      assert_kind_of Symbol, key
      assert_frozen_tree(key)
      assert_frozen_tree(child)
    end
  end

  def test_exact_http_methods_paths_and_configuration_authority
    reporter = client
    OPERATIONS.zip(["PUT", "DELETE", "POST"]).each do |operation, method|
      @body = result_body(operation, " bug 雪+😀?project_id=evil&environment=production ")
      invoke(reporter, operation, " \ufeffbug 雪+😀?project_id=evil&environment=production\u00a0 ")
      uri, actual_method, headers, body = @calls.last
      path = operation == :archive_closed_bugs ? "/mine/archive-closed" :
        "/bugs/bug%20%E9%9B%AA%2B%F0%9F%98%80%3Fproject_id%3Devil%26environment%3Dproduction/archive"
      assert_equal "https", uri.scheme
      assert_equal "handrail.example", uri.host
      assert_equal "/prefix/api/mobile-bug-reports" + path, uri.path
      assert_equal "project_id=project+%26%2B%2F%E9%9B%AA&environment=staging+%26%2B", uri.query
      assert_nil uri.fragment
      assert_equal method, actual_method
      assert_equal "Bearer #{TOKEN}", headers["authorization"]
      assert_equal SESSION, headers["x-handrail-application-session-token"]
      assert_nil body
    end
    assert_equal 3, @calls.length
  end

  def test_normalized_frozen_projections_discard_unrecognized_response_fields
    reporter = client
    OPERATIONS.each do |operation|
      @body = result_body(operation, " \ufeffbug-123\u00a0 ").merge("private" => { "data" => "ignored" })
      @body["archived_at"] = " #{TIMESTAMP} " if operation == :archive_bug
      result = invoke(reporter, operation, " bug-123 ")
      expected = operation == :archive_closed_bugs ? { :contract_version => "v1", :archived_count => 35 } :
        { :contract_version => "v1", :bug_id => "bug-123", :archived => operation == :archive_bug,
          :archived_at => operation == :archive_bug ? TIMESTAMP : nil }
      assert_equal expected, result
      assert_frozen_tree(result)
    end
  end

  def test_bulk_count_uses_existing_js_number_integer_conventions_including_zero
    { 0 => 0, 35 => 35, 2.0 => 2, "3" => 3, " 2e1 " => 20, "0x10" => 16,
      "0b10" => 2, "0o10" => 8, nil => 0, false => 0, true => 1, "" => 0,
      "\ufeff\u00a0" => 0, [] => 0, ["2"] => 2, [nil] => 0 }.each do |count, expected|
      @body = result_body(:archive_closed_bugs).merge("archived_count" => count)
      assert_equal expected, client.archive_closed_bugs[:archived_count]
    end
    [-1, -0.1, 0.5, "2.5", "bad", "Infinity", "NaN", "1e999", {}, [1, 2], [true]].each do |count|
      @body = result_body(:archive_closed_bugs).merge("archived_count" => count)
      assert_rejected { client.archive_closed_bugs }
    end
    @body = { "contract_version" => "v1" }
    assert_rejected { client.archive_closed_bugs }
  end

  def test_object_and_v1_envelopes_are_required_for_every_operation
    OPERATIONS.each do |operation|
      [nil, [], true, false, 1, "result", {}].each do |value|
        @body = value
        assert_rejected { invoke(client, operation) }
      end
      [nil, "", "v2", " v1 ", 1, true, [], {}].each do |version|
        @body = result_body(operation).merge("contract_version" => version)
        assert_rejected { invoke(client, operation) }
      end
      @body = result_body(operation)
      @body.delete("contract_version")
      assert_rejected { invoke(client, operation) }
    end
  end

  def test_single_result_fields_and_requested_id_state_must_match
    [:archive_bug, :restore_bug].each do |operation|
      { "bug_id" => [nil, "", " \ufeff\u00a0 ", false, 1, [], {}, "another-bug", "BUG-123"],
        "archived" => [nil, "true", "false", 0, 1, [], {}] }.each do |key, values|
        values.each do |value|
          @body = result_body(operation).merge(key => value)
          error = assert_rejected { invoke(client, operation) }
          assert_equal 200, error.status_code
          assert_equal "archive-request-1", error.request_id
        end
        @body = result_body(operation)
        @body.delete(key)
        assert_rejected { invoke(client, operation) }
      end
      # An internally valid result for the opposite state must still fail.
      @body = result_body(operation == :archive_bug ? :restore_bug : :archive_bug)
      assert_rejected { invoke(client, operation) }
    end
  end

  def test_timestamp_state_consistency_matches_js_nullable_string_rules
    [nil, "", " \ufeff\u00a0 ", false, 1, [], {}].each do |timestamp|
      @body = result_body(:archive_bug).merge("archived_at" => timestamp)
      assert_rejected { client.archive_bug("bug-123") }
      @body = result_body(:restore_bug).merge("archived_at" => timestamp)
      assert_nil client.restore_bug("bug-123")[:archived_at]
    end
    @body = result_body(:archive_bug)
    @body.delete("archived_at")
    assert_rejected { client.archive_bug("bug-123") }
    @body = result_body(:restore_bug)
    @body.delete("archived_at")
    assert_nil client.restore_bug("bug-123")[:archived_at]
    @body["archived_at"] = TIMESTAMP
    assert_rejected { client.restore_bug("bug-123") }
  end

  def test_malformed_json_and_encoding_are_sanitized_with_request_correlation
    [nil, "", "not-json #{TOKEN}", "{", "\xff".dup.force_encoding("ASCII-8BIT")].each do |bytes|
      reporter = client(configuration, :http => lambda { |*_| { :status => 200, :body => bytes, :headers => @headers } })
      OPERATIONS.each do |operation|
        error = assert_rejected { invoke(reporter, operation) }
        assert_equal 200, error.status_code
        assert_equal "archive-request-1", error.request_id
        refute_includes error.message, TOKEN
      end
    end
    bytes = JSON.generate(result_body(:archive_bug, "bug-雪")).force_encoding("ASCII-8BIT")
    reporter = client(configuration, :http => lambda { |*_| { :status => 200, :body => bytes, :headers => {} } })
    assert_equal "bug-雪", reporter.archive_bug("bug-雪")[:bug_id]
  end

  def test_unsafe_ids_are_rejected_before_identity_resolution_or_http
    resolutions = 0
    reporter = client(configuration, :resolve_application_session_token => lambda { |_| resolutions += 1; SESSION })
    ids = [nil, false, true, 1, [], {}, "", " \u00a0", ".", "..", " ../ ", "bug/123", "bug\\123",
      "/absolute", "//evil.example", "https://evil.example", "%2e%2e", "%2F", "%5C", "%00", "%252e%252e",
      "bug%20id", "\xff".dup.force_encoding("UTF-8"), "\x00".dup.force_encoding("UTF-16LE")]
    (0..31).to_a.concat([127]).each do |code|
      ids.concat([code.chr + "bug", "bug" + code.chr, "bu" + code.chr + "g"])
    end
    [:archive_bug, :restore_bug].each do |operation|
      ids.each { |id| assert_rejected { invoke(reporter, operation, id) } }
    end
    assert_equal 0, resolutions
    assert_empty @calls
    assert_empty NoNetwork::ATTEMPTS
  end

  def test_each_operation_refreshes_identity_across_requests_and_retries
    OPERATIONS.each do |operation|
      @calls.clear
      @body = result_body(operation)
      sleeps, resolutions = [], []
      http = lambda do |*args|
        @calls << args
        { :status => @calls.length == 1 ? 503 : 200, :body => JSON.generate(@body), :headers => @headers }
      end
      factory = SDK::Factory.new(configuration(:max_attempts => 2, :retry_delay_ms => 10),
        :http => http, :sleeper => lambda { |seconds| sleeps << seconds },
        :resolve_application_session_token => lambda { |request| resolutions << request; "#{request}-#{resolutions.length}" })
      alice = factory.for_request(:alice)
      invoke(alice, operation)
      invoke(alice, operation)
      invoke(factory.for_request(:bob), operation)
      assert_equal [:alice, :alice, :alice, :bob], resolutions
      assert_equal ["alice-1", "alice-2", "alice-3", "bob-4"],
        @calls.map { |call| call[2]["x-handrail-application-session-token"] }
      assert_equal [0.01], sleeps
      assert_equal 1, @calls.map { |call| [call[0].to_s, call[1], call[3]] }.uniq.length
    end
  end

  def test_authorization_and_ownership_rejections_preserve_sanitized_diagnostics
    { 401 => "bug_history_identity_required", 403 => "bug_not_owned", 404 => "bug_not_found" }.each do |status, code|
      @status = status
      @body = { "error" => { "code" => code, "message" => "Denied #{SESSION} #{TOKEN}" } }
      OPERATIONS.each do |operation|
        error = assert_rejected { invoke(client, operation) }
        assert_equal status, error.status_code
        assert_equal code, error.upstream_code
        assert_equal "archive-request-1", error.request_id
        assert_equal "Denied [REDACTED] [REDACTED]", error.upstream_message
        [error.message, error.inspect, error.to_json].each do |text|
          refute_includes text, SESSION
          refute_includes text, TOKEN
        end
      end
    end
    assert_equal 9, @calls.length
  end

  def test_network_failures_map_to_tracking_unavailable
    reporter = client(configuration, :http => lambda { |*_| raise IOError, SESSION })
    OPERATIONS.each do |operation|
      error = assert_raises(SDK::Error) { invoke(reporter, operation) }
      assert_equal :tracking_unavailable, error.code
      assert_nil error.status_code
      assert_nil error.cause
      refute_includes error.message, SESSION
    end
  end

  def test_disabled_or_invalid_configuration_performs_no_work
    resolutions = 0
    [configuration(:enabled => false), configuration(:project_id => nil), configuration(:report_token => nil)].each do |config|
      reporter = client(config, :resolve_application_session_token => lambda { |_| resolutions += 1; SESSION })
      OPERATIONS.each do |operation|
        error = assert_raises(SDK::Error) { invoke(reporter, operation) }
        assert_equal :invalid_configuration, error.code
      end
    end
    assert_equal 0, resolutions
    assert_empty @calls
  end
end
