require "test_helper"
require "handrail/bug_reporter/payload"
require "handrail/bug_reporter/configuration"

class PayloadTest < ScaffoldTestCase
  Payload = Handrail::BugReporter::Payload
  Identity = Handrail::BugReporter::Identity
  FIXTURES = JSON.parse(File.read(File.join(ROOT, "test/fixtures/js_v0.4.49_payload.json")))
  IDENTITY_DIFFERENCES = %w[platform reporter_sdk_runtime reporter_sdk_package reporter_sdk_commit reporter_sdk_ref].freeze

  def report(input = {}, hooks = [])
    Payload.new({ :title => "Title", :description => "Description" }.merge(input),
      :project_id => "project-123", :environment => "staging", :redaction_hooks => hooks)
  end

  FIXTURES.fetch("cases").each_with_index do |fixture, index|
    define_method("test_js_fixture_#{index}_#{fixture.fetch('name').gsub(/\W+/, '_')}") do
      hooks = fixture.fetch("hooks").map do |step|
        lambda do |fields|
          raise "private hook error" if step["error"]
          output = fields.merge(step["merge"] || {})
          output.delete(step["remove"]) if step["remove"]
          output
        end
      end
      build = lambda do
        Payload.new(fixture.fetch("input"), :project_id => FIXTURES["config"]["projectId"],
          :environment => FIXTURES["config"]["environment"], :redaction_hooks => hooks)
      end
      if fixture["error"]
        error = assert_raises(Payload::Error, &build)
        assert_equal fixture["error"], { "code" => error.code, "message" => error.message }
      else
        actual = JSON.parse(build.call.to_json)
        expected = fixture.fetch("expected")
        assert_equal expected.reject { |key, _| IDENTITY_DIFFERENCES.include?(key) },
          actual.reject { |key, _| IDENTITY_DIFFERENCES.include?(key) }
        assert_equal Identity::SDK_IDENTITY, actual.select { |key, _| Identity::SDK_IDENTITY.key?(key) }
      end
    end
  end

  def test_ruby_field_names_and_alias_precedence
    input = { :app_version => "ruby-version", :appVersion => "js-version", :build_number => 5,
      :commit_sha => "app-commit", :app_flavor => "internal", :steps => "Click", :event_id => " ruby-id " }
    body = report(input).to_h
    %w[app_version build_number commit_sha app_flavor].each { |key| assert_equal input[key.to_sym], body[key] }
    assert_equal "Click", body["reproducer"]
    assert_equal "ruby-id", body["event_id"]
    assert_equal "Primary steps", report(:steps_to_reproduce => "Primary steps", :steps => "Secondary").to_h["reproducer"]
  end

  def test_required_fields_fail_before_any_hook_can_repair_them
    [nil, false, 1, [], {}, "", " \n", "\u00a0\ufeff"].each do |value|
      [:title, :description].each do |field|
        called = false
        hook = lambda { |fields| called = true; fields.merge("title" => "Repaired", "description" => "Repaired") }
        error = assert_raises(Payload::Error) { report({ field => value }, [hook]) }
        assert_equal "invalid_report", error.code
        refute called
      end
    end
    [nil, false, [], "report"].each do |value|
      assert_raises(Payload::Error) { Payload.new(value, :project_id => "p", :environment => "dev") }
    end
  end

  def test_each_hook_must_return_valid_required_fields
    [nil, [], false, {}, { "title" => 3, "description" => "ok" }].each do |output|
      reached = false
      hooks = [lambda { |_| output }, lambda { |fields| reached = true; fields }]
      assert_raises(Payload::Error) { report({}, hooks) }
      refute reached
    end
  end

  def test_redacts_nested_key_variants_before_and_after_every_hook
    keys = %w[authorization proxyAuthorization bearer cookie set_cookie password passwd passphrase
      credential credentials secret clientSecret private_key apiKey access-key profileKey session
      session.id sessionToken accessToken refresh_token id-token jwt csrf xsrf verifier cardNumber
      credit-card cvv cvc privateMessage direct_message dm-content customToken customSecret]
    secrets = keys.each_with_object({}) { |key, hash| hash[key] = "raw-secret" }
    hooks = [lambda do |fields|
      assert_equal keys.map { Payload::REDACTED }, fields["metadata"]["nested"][0].values
      fields["metadata"]["nested"] << { "refreshToken" => "hook-secret" }
      fields
    end, lambda do |fields|
      assert_equal Payload::REDACTED, fields["metadata"]["nested"][1]["refreshToken"]
      fields["metadata"]["password"] = "last-hook-secret"
      fields
    end]
    payload = report({ :metadata => { "nested" => [secrets], "safe" => "visible" } }, hooks)
    refute_match(/raw-secret|hook-secret/, payload.to_json)
    assert_equal Payload::REDACTED, payload.to_h["metadata"]["password"]
    assert_equal "visible", payload.to_h["metadata"]["safe"]
    assert_equal "raw-secret", secrets["password"]
  end

  def test_reserved_fields_never_reach_later_hooks_or_the_wire
    reserved = %w[project_id environment event_id source platform reporter_sdk_runtime reporter_sdk_package
      reporter_sdk_version reporter_sdk_commit reporter_sdk_ref profile_key authorization report_token
      credentials reporter reporter_assertion reporter_identity screenshot screenshot_base64 screenshot_filename
      screenshot_mime_type allow_screenshots allowScreenshots notification reporter_notification notification_subscription automation_requests]
    injection = reserved.each_with_object({}) { |key, fields| fields[key] = "injected" }
    hooks = [lambda { |fields| fields.merge(injection) }, lambda do |fields|
      assert_empty fields.keys & reserved
      fields
    end]
    # screenshot is now an explicit attachment input, not an ignored wire field.
    # Keep the invalid placeholder in hook output to prove hooks cannot attach it.
    body = report(injection.reject { |key, _| key == "screenshot" }, hooks).to_h
    assert_equal "project-123", body["project_id"]
    assert_equal "staging", body["environment"]
    # event_id/profile_key in input are trusted API arguments, independently of hooks.
    assert_equal "injected", body["event_id"]
    assert_equal "injected", body["profile_key"]
    assert_equal Identity::SDK_IDENTITY, body.select { |key, _| Identity::SDK_IDENTITY.key?(key) }
    assert_empty body.keys - Payload::CALLER_REPORT_FIELDS - Identity::SDK_IDENTITY.keys - %w[project_id environment event_id profile_key]
  end

  def test_profile_key_is_intentional_and_never_visible_to_hooks
    hook = lambda do |fields|
      refute fields.key?("profile_key")
      assert_equal Payload::REDACTED, fields["metadata"]["profile_key"]
      fields.merge("profile_key" => "hook-profile")
    end
    payload = report({ :profile_key => " intentional ", :metadata => { :profile_key => "metadata-profile" } }, [hook])
    assert_equal "intentional", payload.to_h["profile_key"]
    refute_match(/hook-profile|metadata-profile/, payload.to_json)
    [nil, "", " \n", 42, false].each do |value|
      refute report(:profile_key => value).to_h.key?("profile_key")
    end
    refute report({}, [lambda { |fields| fields.merge("profile_key" => "hook-only") }]).to_h.key?("profile_key")
  end

  def test_ids_are_generated_once_and_serialization_never_reruns_hooks
    count = 0
    hook = lambda { |fields| count += 1; fields }
    [nil, "", " \t", false, 123].each do |value|
      payload = report({ :event_id => value }, [hook])
      id = payload.to_h["event_id"]
      assert_match(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/, id)
      3.times { assert_equal id, JSON.parse(payload.to_json)["event_id"] }
      assert_equal id, payload.as_json["event_id"]
    end
    assert_equal 5, count
    refute_equal report.to_h["event_id"], report.to_h["event_id"]
    assert_equal "x" * 160, report(:event_id => " \n" + "x" * 180 + "\t").to_h["event_id"]
  end

  def test_caller_and_hook_objects_are_cloned_and_snapshot_is_deeply_frozen
    input = { :title => "Mutable", :metadata => { :nested => ["original"] }, :event_id => "stable", :profile_key => "profile" }
    before = Marshal.dump(input)
    captured = nil
    hook = lambda { |fields| captured = fields; fields["metadata"]["nested"] << "hook"; fields }
    payload = report(input, [hook])
    assert_equal before, Marshal.dump(input)
    captured["metadata"]["nested"][0].replace("later mutation")
    input[:title].replace("later input")
    input[:event_id].replace("later id")
    input[:profile_key].replace("later profile")
    assert_equal "Mutable", payload.to_h["title"]
    assert_equal ["original", "hook"], payload.to_h["metadata"]["nested"]
    assert_equal "stable", payload.to_h["event_id"]
    assert_equal "profile", payload.to_h["profile_key"]
    assert_raises(RuntimeError) { payload.to_h["metadata"]["nested"] << "mutation" }
    assert_raises(RuntimeError) { payload.to_h["source"].replace("node") }
    assert_raises(RuntimeError) { payload.to_h["reporter_sdk_version"] = "999" }
    assert_raises(RuntimeError) { Identity::SDK_IDENTITY["reporter_sdk_version"].replace("999") }
    assert_raises(RuntimeError) { Identity::SDK_IDENTITY["platform"] = "node" }
  end

  def test_json_normalization_is_bounded_and_does_not_invoke_custom_serializers
    cycle = {}; cycle["self"] = cycle
    shared = { "ok" => true }
    unsafe = Object.new
    def unsafe.to_json(*_args); raise "must not serialize arbitrary objects"; end
    value = { "cycle" => cycle, "repeated" => [shared, shared], "array" => [unsafe, nil, Float::INFINITY],
      "nan" => Float::NAN, "object" => unsafe, "time" => Time.utc(2026, 9, 9, 1, 2, 3),
      "symbol" => :omit, "prototype" => "omit", "constructor" => "omit", "__proto__" => "omit",
      "" => "omit", "k" * 201 => "bounded" }
    result = Payload.redact_sensitive_values(value)
    assert_equal({ "self" => "[Circular]" }, result["cycle"])
    assert_equal [shared, shared], result["repeated"]
    assert_equal [nil, nil], result["array"]
    assert_nil result["nan"]
    assert_equal "2026-09-09T01:02:03.000Z", result["time"]
    assert_equal "bounded", result["k" * 200]
    %w[object symbol prototype constructor __proto__].each { |key| refute result.key?(key) }
    nested = {}; cursor = nested
    25.times { cursor["child"] = {}; cursor = cursor["child"] }
    normalized = Payload.redact_sensitive_values(nested)
    20.times { normalized = normalized["child"] }
    assert_equal "[Circular]", normalized
    [nil, [], "string", 1].each { |input| assert_equal({}, Payload.redact_sensitive_values(input)) }
  end

  def test_hook_exception_has_no_secret_message_or_cause
    error = assert_raises(Payload::Error) { report({}, [lambda { |_| raise "secret-token" }]) }
    assert_equal "redaction_failed", error.code
    assert_nil error.cause
    refute_match(/secret-token/, error.inspect + error.message + error.backtrace.join)
  end

  def test_fixed_js_json_normalization_cases
    shared = { "safe" => "visible" }
    cycle = {}; cycle["self"] = cycle
    array_cycle = []; array_cycle << array_cycle
    deep = {}; cursor = deep
    25.times { cursor["child"] = {}; cursor = cursor["child"] }
    inputs = {
      "cycles" => { "cycle" => cycle, "arrayCycle" => array_cycle },
      "depth" => deep,
      "shared reference" => { "repeated" => [shared, shared] },
      "numbers and date" => { "nan" => Float::NAN, "infinity" => Float::INFINITY,
        "negativeInfinity" => -Float::INFINITY, "time" => Time.utc(2026, 9, 9, 1, 2, 3), "number" => 42 },
      "unsupported values" => { "fn" => lambda {}, "symbol" => :omit, "array" => [lambda {}, :omit, nil] },
      "bounded keys" => { "" => "omit", "prototype" => "omit", "constructor" => "omit",
        "k" * 201 => "bounded", "safe" => "visible" }
    }
    FIXTURES.fetch("normalization_cases").each do |fixture|
      assert_equal fixture.fetch("expected"), Payload.redact_sensitive_values(inputs.fetch(fixture.fetch("name"))), fixture.fetch("name")
    end
  end

  def test_configuration_readers_are_the_only_project_environment_source
    config = Handrail::BugReporter::Configuration.new(:project_id => " project-123 ", :environment => " STAGING ",
      :api_base_url => "https://fixture.invalid", :report_token => "private-token")
    payload = Payload.new({ :title => "Title", :description => "Description", :project_id => "foreign", :environment => "prod" },
      :project_id => config.project_id, :environment => config.environment)
    assert_equal "project-123", payload.to_h["project_id"]
    assert_equal "staging", payload.to_h["environment"]
    refute_match(/private-token|foreign/, payload.to_json)
    [nil, "", " ", 42].each do |value|
      error = assert_raises(Payload::Error) { Payload.new({ :title => "t", :description => "d" }, :project_id => value, :environment => "dev") }
      assert_equal "invalid_configuration", error.code
    end
  end

  def test_identity_agrees_with_gemspec_and_does_not_invent_a_release
    spec = Gem::Specification.load(File.join(ROOT, "handrail-bug-reporter.gemspec"))
    identity = Identity::SDK_IDENTITY
    assert_equal spec.name, identity["reporter_sdk_package"]
    assert_equal spec.version.to_s, identity["reporter_sdk_version"]
    assert_equal "ruby", identity["reporter_sdk_runtime"]
    assert_equal "ruby", identity["platform"]
    assert_nil identity["reporter_sdk_commit"]
    assert_nil identity["reporter_sdk_ref"]
    assert_equal "0.4.49", FIXTURES["provenance"]["version"]
    assert_equal "96b293248611594c388d0fab3af63b1b2d1aae5c", FIXTURES["provenance"]["commit"]
  end

  def test_runtime_needs_no_rails_git_or_network
    output = run_ruby(<<-'RUBY')
      module NoCommands
        def system(*args); raise "Runtime command forbidden"; end
        def `(command); raise "Runtime command forbidden"; end
      end
      Kernel.prepend(NoCommands)
      require "handrail/bug_reporter/payload"
      raise "Rails loaded" if defined?(Rails)
      payload = Handrail::BugReporter::Payload.new({ :title => "t", :description => "d" }, :project_id => "p", :environment => "dev")
      raise "Missing identity" unless JSON.parse(payload.to_json)["reporter_sdk_runtime"] == "ruby"
      puts "offline OK"
    RUBY
    assert_equal "offline OK\n", output
  end
end
