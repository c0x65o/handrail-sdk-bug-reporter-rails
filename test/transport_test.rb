require "minitest/autorun"
require "handrail/bug_reporter/client"

class TransportTest < Minitest::Test
  SDK = Handrail::BugReporter
  TOKEN = "hbr_report_test_credential"
  SESSION = "session-test-credential"

  def config(options = {})
    SDK::Configuration.new({ :api_base_url => "https://handrail.example/prefix/api",
      :project_id => " project-1 ", :environment => " StAgInG ", :report_token => TOKEN }.merge(options))
  end

  def response(status = 200, body = "{}", headers = {})
    { :status => status, :body => body, :headers => headers }
  end

  def client(configuration = config, options = {})
    SDK::Factory.new(configuration, options).for_request
  end

  def error_for(reporter, options = {})
    assert_raises(SDK::Error) { reporter.request(**{ :method => "POST", :body => "{}" }.merge(options)) }
  end

  def test_endpoint_normalization
    ["", "/", "///", "/api", "/api/", "/api//mobile-bug-reports///"].each do |suffix|
      c = config(:api_base_url => " https://HANDRAIL.example#{suffix} ")
      assert_equal :ready, c.status
      assert_equal "https://handrail.example/api/mobile-bug-reports", c.endpoints[:reports]
      assert_equal c.endpoints[:reports] + "/policy", c.endpoints[:policy]
      assert_equal c.endpoints[:reports] + "/mine", c.endpoints[:mine]
      assert_equal c.endpoints[:reports] + "/bugs", c.endpoints[:bugs]
    end
    ["/prefix", "/prefix/", "//prefix///api//", "/prefix/api/mobile-bug-reports/"].each do |suffix|
      assert_equal "https://handrail.example/prefix/api/mobile-bug-reports", config(:api_base_url => "https://handrail.example#{suffix}").endpoints[:reports]
    end
    assert_equal "http://localhost:3210/api/mobile-bug-reports", config(:api_base_url => "http://localhost:3210").endpoints[:reports]
    assert_equal "https://[::1]:444/api/mobile-bug-reports", config(:api_base_url => "https://[::1]:444").endpoints[:reports]
  end

  def test_invalid_endpoint_inputs_never_reach_network_or_expose_input
    [nil, "", "/api", "//handrail.example/api", "ftp://handrail.example", "https:/handrail.example",
      "https://user:#{TOKEN}@handrail.example", "https://#{TOKEN}@handrail.example",
      "https://handrail.example?", "https://handrail.example#", "https://handrail.example/api?q=1",
      "https://handrail.example/api#fragment", "https://handrail.example/has space", "https://",
      "https://handrail.example:70000", "https://handrail.example\\evil", "https://handrail.example/a/../api",
      "https://handrail.example/%2e%2e/api", "https://handrail.example/%2Fapi", "https://handrail.example/\napi"].each do |url|
      c = config(:api_base_url => url)
      assert_equal :misconfigured, c.status, url.inspect
      reporter = client(c, :http => lambda { |*_| flunk "network called" })
      error = error_for(reporter)
      assert_equal :invalid_configuration, error.code
      assert_nil error.cause
      refute_includes [c.inspect, c.snapshot, error.inspect, error.message].inspect, TOKEN
    end
  end

  def test_disabled_and_missing_configuration_do_not_resolve_identity_or_send
    boundary = lambda { |*_| flunk "HTTP called" }
    resolver = lambda { |*_| flunk "identity resolved" }
    c = config(:enabled => false, :api_base_url => nil)
    factory = SDK::Factory.new(c, :http => boundary, :resolve_application_session_token => resolver)
    result = factory.for_request.request(:method => "POST")
    assert_equal :disabled, result.status
    assert_equal 0, result.attempts
    assert_nil result.body
    [:project_id, :environment, :report_token].each do |key|
      assert_equal :misconfigured, config(key => " ").status
    end
    assert_equal :misconfigured, config(:report_token_header => "cookie").status
    assert_equal :misconfigured, config(:report_token => "token\r\ninjected").status
    assert_equal :misconfigured, config(:report_token => "two tokens").status
  end

  def test_configuration_is_immutable_and_binding_cannot_be_overridden_per_request
    project, environment, token = " project-1 ", " STAGING ", TOKEN.dup
    c = config(:project_id => project, :environment => environment, :report_token => token)
    project.replace("other"); environment.replace("production"); token.replace("different")
    assert_equal "project-1", c.project_id
    assert_equal "staging", c.environment
    assert c.frozen?
    assert c.endpoints.frozen?
    assert c.endpoints.values.all?(&:frozen?)
    assert c.project_id.frozen?
    assert c.snapshot.frozen?
    refute c.respond_to?(:report_token)
    calls = []
    reporter = client(c, :http => lambda { |*args| calls << args; response })
    reporter.request(:method => "POST", :body => '{"event_id":"stable"}')
    assert_equal "Bearer #{TOKEN}", calls.first[2]["authorization"]
    assert_raises(ArgumentError) { reporter.request(:method => "POST", :project_id => "other") }
  end

  def test_token_modes_only_forward_explicit_headers
    ["authorization", "x-handrail-bug-report-token"].each do |mode|
      calls = []
      request = { :cookie => "host-secret-cookie", :authorization => "host-secret-auth", :session => SESSION }
      factory = SDK::Factory.new(config(:report_token_header => mode),
        :resolve_application_session_token => lambda { |req| " #{req[:session]} " },
        :http => lambda { |*args| calls << args; response })
      factory.for_request(request).request(:method => "POST", :body => "{}")
      assert_equal({ "accept" => "application/json", "content-type" => "application/json",
        mode => (mode == "authorization" ? "Bearer #{TOKEN}" : TOKEN),
        "x-handrail-application-session-token" => SESSION }, calls.first[2])
      refute_includes factory.inspect, "host-secret"
    end
  end

  def test_retry_normalization_and_timeout_bounds
    { nil => 1, 0 => 1, -9 => 1, 1 => 1, 2 => 2, 3 => 3, 90 => 3,
      2.0 => 2, 2.5 => 1, "3" => 1, Float::INFINITY => 1, Float::NAN => 1 }.each do |input, expected|
      assert_equal expected, config(:max_attempts => input).max_attempts
    end
    { nil => 250, "500" => 250, -10 => 0, 0 => 0, 123.5 => 123.5, 90_000 => 30_000,
      Float::INFINITY => 250, Float::NAN => 250 }.each do |input, expected|
      assert_equal expected, config(:retry_delay_ms => input).retry_delay_ms
    end
    assert_equal({ :open_timeout => 5, :read_timeout => 10, :write_timeout => 10, :request_timeout => 30 }, config.timeouts)
    assert_equal({ :open_timeout => 0.001, :read_timeout => 60, :write_timeout => 10, :request_timeout => 120 },
      config(:open_timeout => -1, :read_timeout => 999, :write_timeout => Float::NAN, :request_timeout => 999).timeouts)
  end

  def test_default_one_attempt_and_opt_in_backoff_with_clock
    calls, sleeps = [], []
    http = lambda { |*args| calls << args; response(503) }
    error_for(client(config, :http => http, :sleeper => lambda { |_| flunk "slept" }))
    assert_equal 1, calls.length
    calls.clear
    reporter = client(config(:max_attempts => 99), :http => http, :sleeper => lambda { |seconds| sleeps << seconds })
    error_for(reporter)
    assert_equal 3, calls.length
    assert_equal [0.25, 0.5], sleeps
    sleeps.clear
    error_for(client(config(:max_attempts => 3, :retry_delay_ms => 99_999), :http => http, :sleeper => lambda { |seconds| sleeps << seconds }))
    assert_equal [30.0, 60.0], sleeps
    ticks = [5.0, 5.125]
    result = client(config, :http => lambda { |*_| response }, :clock => lambda { ticks.shift }).request(:method => "GET")
    assert_equal 125.0, result.elapsed_ms
  end

  def test_every_transient_status_retries_and_success_stops
    SDK::Transport::TRANSIENT_STATUSES.each do |status|
      calls = 0
      reporter = client(config(:max_attempts => 3), :sleeper => lambda { |_| },
        :http => lambda { |*_| calls += 1; response(calls == 1 ? status : 201) })
      result = reporter.request(:method => "POST", :body => "{}")
      assert_equal 2, calls
      assert_equal 201, result.status_code
      assert_equal 2, result.attempts
    end
    [301, 302, 303, 307, 308, 400, 401, 403, 404, 409, 422, 501].each do |status|
      calls = 0
      reporter = client(config(:max_attempts => 3), :sleeper => lambda { |_| flunk "slept" },
        :http => lambda { |*_| calls += 1; response(status, "{}", "location" => "https://evil.example") })
      assert_equal status, error_for(reporter).status_code
      assert_equal 1, calls
    end
  end

  def test_network_failures_retry_but_tls_and_programming_errors_do_not
    [Net::OpenTimeout, Net::ReadTimeout, EOFError, IOError, SocketError, Errno::ECONNRESET,
      Errno::ECONNREFUSED, Errno::EPIPE, Errno::ETIMEDOUT].each do |klass|
      calls = 0
      reporter = client(config(:max_attempts => 3), :sleeper => lambda { |_| },
        :http => lambda { |*_| calls += 1; raise klass, TOKEN })
      error = error_for(reporter)
      assert_equal 3, calls
      assert_equal "Bug reporting request failed.", error.message
      assert_nil error.cause
      refute_includes error.full_message, TOKEN if error.respond_to?(:full_message)
    end
    [OpenSSL::SSL::SSLError, ArgumentError, Net::HTTPBadResponse].each do |klass|
      calls = 0
      reporter = client(config(:max_attempts => 3), :sleeper => lambda { |_| flunk "slept" },
        :http => lambda { |*_| calls += 1; raise klass, SESSION })
      error = error_for(reporter)
      assert_equal 1, calls
      assert_nil error.cause
    end
  end

  def test_stable_body_bytes_and_fresh_identity_per_attempt
    calls, sessions = [], ["first-session", "second-session", nil]
    body = "{\n\"event_id\":\"stable-123\",\"message\":\"snowman ☃\"}\n"
    original = body.dup
    factory = SDK::Factory.new(config(:max_attempts => 3), :sleeper => lambda { |_| },
      :resolve_application_session_token => lambda { |_| sessions.shift },
      :http => lambda { |*args| calls << args; body.replace("caller changed it"); response(calls.length < 3 ? 503 : 200) })
    factory.for_request(Object.new).request(:method => "POST", :body => body)
    assert_equal [original, original, original], calls.map { |call| call[3] }
    assert_equal 1, calls.map { |call| call[3].object_id }.uniq.size
    assert calls.all? { |call| call[3].frozen? }
    assert_equal ["first-session", "second-session", nil], calls.map { |call| call[2]["x-handrail-application-session-token"] }
    assert sessions.empty?
  end

  def test_interleaved_request_identity_isolation_and_vanilla_fallback
    calls = []
    resolver = lambda { |req| raise "private #{TOKEN}" if req[:raises]; req[:session] }
    http = lambda { |*args| calls << args; Fiber.yield; response }
    factory = SDK::Factory.new(config, :http => http, :resolve_application_session_token => resolver)
    requests = [{ :session => "session-A" }, { :session => "session-B" }, { :session => nil },
      { :session => " " }, { :raises => true }, { :session => "bad\nheader" }, { :session => Object.new }]
    clients = requests.map { |req| factory.for_request(req) }
    fibers = clients.map { |reporter| Fiber.new { reporter.request(:method => "GET") } }
    fibers.each(&:resume)
    fibers.reverse_each(&:resume)
    assert_equal ["session-A", "session-B", nil, nil, nil, nil, nil], calls.map { |call| call[2]["x-handrail-application-session-token"] }
    assert_equal [:@configuration, :@resolver, :@transport].sort, factory.instance_variables.sort
    assert_equal [:@clock, :@configuration, :@http, :@sleeper].sort, factory.instance_variable_get(:@transport).instance_variables.sort
    clients.each { |reporter| refute_match(/session-A|session-B|private|hbr_/, reporter.inspect) }
  end

  def test_cross_origin_and_path_escape_are_rejected_before_sending
    reporter = client(config, :http => lambda { |*_| flunk "sent credentials" })
    ["https://evil.example/prefix/api/mobile-bug-reports", "http://handrail.example/prefix/api/mobile-bug-reports",
      "https://handrail.example:444/prefix/api/mobile-bug-reports", "https://user:pass@handrail.example/prefix/api/mobile-bug-reports",
      "https://handrail.example/prefix/api/mobile-bug-reports-other", "https://handrail.example/prefix/api/mobile-bug-reports/../other",
      "https://handrail.example/prefix/api/mobile-bug-reports/%2e%2e/other", "//evil.example/path"].each do |url|
      error_for(reporter, :url => url)
    end
    calls = []
    reporter = client(config, :http => lambda { |*args| calls << args; response })
    reporter.request(:method => "GET", :url => config.endpoints[:bugs] + "/bug-1?project_id=project-1&environment=staging")
    assert_equal "/prefix/api/mobile-bug-reports/bugs/bug-1", calls.first[0].path
  end

  def test_diagnostics_redact_all_fields_before_truncating_and_never_expose_raw_response
    body = JSON.generate(:error => { :code => TOKEN, :message => "x" * 490 + TOKEN + "\n" + SESSION,
      :request_id => SESSION }, :request => "private request payload")
    reporter = SDK::Factory.new(config, :resolve_application_session_token => lambda { |_| SESSION },
      :http => lambda { |*_| response(422, body, "X-Request-ID" => TOKEN) }).for_request(:private_session)
    error = error_for(reporter)
    assert_nil error.upstream_code
    assert_nil error.request_id
    assert_equal "x" * 490 + "[REDACTED]", error.upstream_message
    assert_operator error.upstream_message.length, :<=, 500
    refute_match(/hbr_|session-test|private request|private_session/, [error.inspect, error.message, error.instance_variables.map { |key| error.instance_variable_get(key) }].inspect)
    assert_nil error.cause
    refute error.respond_to?(:body)
  end

  def test_diagnostic_bounds_shapes_controls_and_header_fallback
    body = JSON.generate(:error => { :code => "C" * 200, :message => "hello\nworld\u0000 " + "x" * 700,
      :request_id => "R" * 300 })
    error = error_for(client(config, :http => lambda { |*_| response(400, body) }))
    assert_equal "C" * 120, error.upstream_code
    assert_equal "R" * 200, error.request_id
    assert_equal 500, error.upstream_message.length
    refute_match(/[\x00-\x1f\x7f]/, error.upstream_message)
    ["not JSON", "[]", "null", "{", "x" * 16_385, JSON.generate(:message => "x" * 16_384)].each do |raw|
      error = error_for(client(config, :http => lambda { |*_| response(400, raw, "x-handrail-request-id" => "safe-id") }))
      assert_nil error.upstream_message
      assert_equal "safe-id", error.request_id
    end
    [TOKEN, SESSION, "bad\nid", "bad id", "hbr_unknown_secret"].each do |id|
      reporter = SDK::Factory.new(config, :resolve_application_session_token => lambda { |_| SESSION },
        :http => lambda { |*_| response(400, JSON.generate(:code => id, :message => "Bearer unknown-session"), "x-request-id" => id) }).for_request
      error = error_for(reporter)
      assert_nil error.request_id
      assert_nil error.upstream_code
      assert_equal "Bearer [REDACTED]", error.upstream_message
    end
  end

  def test_retry_diagnostics_redact_prior_session_tokens_and_error_causes
    sessions, calls = ["prior-secret", "new-secret"], 0
    factory = SDK::Factory.new(config(:max_attempts => 2), :resolve_application_session_token => lambda { |_| sessions.shift },
      :sleeper => lambda { |_| }, :http => lambda { |*_| calls += 1; response(503, JSON.generate(:message => "prior-secret new-secret #{TOKEN}")) })
    begin
      raise "host exception contains #{TOKEN}"
    rescue RuntimeError
      error = error_for(factory.for_request)
      assert_nil error.cause
      assert_equal "[REDACTED] [REDACTED] [REDACTED]", error.upstream_message
    end
  end

  def test_inspection_and_structured_logging_never_walk_private_state
    c = config
    factory = SDK::Factory.new(c, :http => lambda { |*_| response(200, "private upstream #{TOKEN}") })
    reporter = factory.for_request(:session => SESSION, :cookie => "private cookie")
    result = reporter.request(:method => "GET")
    error = error_for(client(c, :http => lambda { |*_| raise TOKEN }))
    [c, factory, reporter, result, error, SDK::Transport.new(c), SDK::Transport::NetHTTP.new].each do |object|
      [object.inspect, object.to_s, object.as_json, JSON.generate(object)].each do |representation|
        refute_match(/#{TOKEN}|#{SESSION}|private upstream|private cookie/, representation)
      end
    end
  end

  class HTTPConnection
    attr_accessor :use_ssl, :verify_mode, :verify_hostname, :open_timeout, :read_timeout,
      :write_timeout, :max_retries
    attr_reader :requests

    def initialize
      @requests = []
    end

    def start
      yield self
    end

    def request(request)
      @requests << request
      result = Net::HTTPFound.new("1.1", "302", "Found")
      result["location"] = "https://evil.example"
      result.instance_variable_set(:@read, true)
      result.body = "{}"
      result
    end
  end

  def test_net_http_boundary_sets_tls_timeouts_and_zero_retries_without_following_redirects
    connection, destinations = HTTPConnection.new, []
    boundary = SDK::Transport::NetHTTP.new(lambda { |*args| destinations << args; connection })
    c = config(:open_timeout => 2, :read_timeout => 3, :write_timeout => 4)
    error = error_for(client(c, :http => boundary))
    assert_equal 302, error.status_code
    assert_equal [["handrail.example", 443]], destinations
    assert_equal true, connection.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, connection.verify_mode
    assert_equal true, connection.verify_hostname
    assert_equal [2, 3, 4], [connection.open_timeout, connection.read_timeout, connection.write_timeout]
    assert_equal 0, connection.max_retries
    assert_equal 1, connection.requests.length
    assert_equal "POST", connection.requests.first.method
    assert_equal "{}", connection.requests.first.body
    assert_nil connection.requests.first["cookie"]
  end

  def test_total_timeout_bounds_legacy_writes
    connection = HTTPConnection.new
    def connection.request(_request)
      sleep 1
    end
    boundary = SDK::Transport::NetHTTP.new(lambda { |*_| connection })
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = error_for(client(config(:request_timeout => 0.01), :http => boundary))
    assert_equal :request_failed, error.code
    assert_nil error.cause
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - before, :<, 0.5
  end

  def test_legacy_hidden_retry_guard_prevents_a_second_transport_start
    http = SDK::Transport::SingleAttemptHTTP.new("handrail.example", 443, nil)
    # Permit the first begin_transport without a socket; the second must stop
    # before Net::HTTP can reconnect or send. This also exercises the guard on
    # current Ruby independently of max_retries=0.
    socket = Object.new
    def socket.closed?; false; end
    http.instance_variable_set(:@socket, socket)
    request = Net::HTTP::Get.new("/api/mobile-bug-reports")
    http.send(:begin_transport, request)
    assert_raises(EOFError) { http.send(:begin_transport, request) }
  end
end
