module MountedForwardingSupport
  SDK = Handrail::BugReporter
  ROOT_PATH = "/api/mobile-bug-reports".freeze
  LIMIT = SDK::ForwardingGuard::MAX_BODY_BYTES

  class BoundedInput < StringIO
    attr_reader :bytes_read, :read_sizes

    def initialize(bytes)
      super(bytes)
      @bytes_read = 0
      @read_sizes = []
    end

    def read(length = nil, *args)
      raise "Unbounded request read" unless length
      @read_sizes << length
      chunk = super(length, *args)
      @bytes_read += chunk.bytesize if chunk
      chunk
    end
  end

  def setup
    @calls, @resolved, @responses = [], [], []
    configure
    login = call_app("GET", "/fixture-session")
    @cookie = Array(login[1]["set-cookie"] || login[1]["Set-Cookie"]).first
    assert_match(/httponly/i, @cookie)
    @csrf = JSON.parse(login[2]).fetch("csrf")
    @cookie = @cookie.split(";", 2).first
  end

  def configure(options = {})
    config = SDK::Configuration.new({ :api_base_url => "https://upstream.example/prefix/api",
      :project_id => "server/project + one", :environment => " StAgInG ",
      :report_token => "hbr_server_fixture", :max_attempts => 2, :retry_delay_ms => 0 }.merge(options))
    boundary = lambda do |uri, method, headers, body, _timeouts|
      @calls << { :uri => uri, :method => method, :headers => headers, :body => body }
      response = @responses.shift
      raise response if response.is_a?(Exception)
      response || { :status => 201, :body => '{"bug_id":"bug-123"}',
        :headers => { "set-cookie" => "evil=1", "authorization" => "upstream-secret",
          "x-handrail-application-session-token" => "upstream-session" } }
    end
    resolver = lambda do |request|
      principal = request.session[:principal]
      @resolved << principal
      principal && "#{principal}-#{@resolved.length}"
    end
    Rails.application.config.handrail_bug_reporter_factory = SDK::Factory.new(config,
      :http => boundary, :resolve_application_session_token => resolver)
  end

  def wire
    { "title" => "Browser title", "description" => "Browser description",
      "project_id" => "spoofed", "environment" => "production", "event_id" => "browser-event-id",
      "profile_key" => " intentional-profile ", "platform" => "web", "reporter_sdk_runtime" => "browser",
      "reporter_sdk_package" => "@handrail/bug-reporter", "reporter_sdk_version" => "0.4.49",
      "reporter_sdk_commit" => "browser-commit", "reporter_sdk_ref" => "browser-ref",
      "screenshot" => { "mime_type" => "image/png", "data" => "browser-bytes" },
      "reporter_notification" => { "notify_on_resolution" => true, "consent_version" => " v2 ", "extra" => true },
      "automation_requests" => { "anything" => true }, "application_session_token" => "json-session",
      "report_token" => "json-report", "authorization" => "json-auth", "authentication" => { "user" => "spoof" },
      "x-handrail-application-session-token" => "json-header-session", "reportToken" => "json-camel-report",
      "metadata" => { "safe" => [{ "count" => 3, "apiKey" => "secret", "profile_key" => "incidental",
        "password" => "password", "authorization" => "nested-auth", "sessionToken" => "nested-session",
        "automation_requests" => { "nested" => true } }] } }
  end

  def call_app(method, path, bytes = "", headers = {}, length = :actual, input = nil)
    env = Rack::MockRequest.env_for("https://host.example/", :method => method, :input => "")
    # Preserve raw malformed escapes for the real Rails stack to reject instead
    # of rejecting them in MockRequest's URI builder before the request begins.
    raw_path, query = path.split("?", 2)
    env["PATH_INFO"] = raw_path.b
    env["QUERY_STRING"] = query.to_s
    env.merge!("CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "https://host.example",
      "HTTP_COOKIE" => @cookie.to_s, "HTTP_X_CSRF_TOKEN" => @csrf.to_s)
    env.merge!(headers)
    env["rack.input"] = input || StringIO.new(bytes)
    length == :absent ? env.delete("CONTENT_LENGTH") : env["CONTENT_LENGTH"] = (length == :actual ? bytes.bytesize : length).to_s
    status, response_headers, response_body = Rails.application.call(env)
    body = ""
    response_body.each { |part| body << part }
    response_body.close if response_body.respond_to?(:close)
    [status, response_headers, body]
  end

  def assert_private(response)
    assert_equal "private, no-store", response[1]["cache-control"] || response[1]["Cache-Control"]
    assert_match(/application\/json/, response[1]["content-type"] || response[1]["Content-Type"])
    assert_nil response[1]["authorization"]
    assert_nil response[1]["x-handrail-application-session-token"]
    refute_includes response[1].values.join, "upstream-secret"
    refute_includes response[1].values.join, "evil=1"
    Array(response[1]["set-cookie"] || response[1]["Set-Cookie"]).each { |cookie| assert_match(/httponly/i, cookie) }
  end

  def assert_rejected(status, response, head = false)
    assert_equal status, response[0], response[2]
    head ? assert_equal("", response[2]) : assert(JSON.parse(response[2]).key?("error"))
    assert_private(response)
    assert_empty @calls
    assert_empty @resolved
  end

end
