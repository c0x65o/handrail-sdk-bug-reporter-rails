require "json"
require "digest"
require "minitest/autorun"
require "rack/mock"
require_relative "no_network"
require_relative "../config/application"

CompatibilityHost::Application.initialize!

class CompatibilitySmoke < Minitest::Test
  def test_installed_assets_precompile_and_real_csrf_requests
    cell = JSON.parse(File.read(ENV.fetch("HANDRAIL_COMPAT_MATRIX"))).fetch(ENV.fetch("HANDRAIL_COMPAT_CELL"))
    assert_equal cell.fetch("ruby"), RUBY_VERSION
    assert_equal cell.fetch("rails"), Rails.version
    assert_equal cell.fetch("bundler"), Bundler::VERSION
    spec = Gem.loaded_specs.fetch("handrail-bug-reporter")
    assert_kind_of Bundler::Source::Git, spec.source
    assert_equal ENV.fetch("HANDRAIL_COMPAT_REVISION"), spec.source.revision
    installed = File.realpath(spec.full_gem_path)
    assert installed.start_with?(File.realpath(ENV.fetch("BUNDLE_PATH")) + "/"), installed
    refute installed.start_with?(ENV.fetch("HANDRAIL_COMPAT_SOURCE") + "/"), installed
    assert_equal installed, File.realpath(Handrail::BugReporter::Engine.root)
    features = $LOADED_FEATURES.select { |path| path.include?("/handrail/bug_reporter") }
    refute_empty features
    features.each { |path| assert File.realpath(path).start_with?(installed + "/"), path }
    # Bundler normalizes the installed gemspec. All actual package bytes must
    # still match, including dirty/untracked implementation files.
    snapshot = JSON.parse(File.read(ENV.fetch("HANDRAIL_COMPAT_SNAPSHOT")))
    snapshot.each do |path, sha|
      next if path == "handrail-bug-reporter.gemspec"
      assert_equal sha, Digest::SHA256.file(File.join(installed, path)).hexdigest, path
    end
    installed_spec = Gem::Specification.load(File.join(installed, "handrail-bug-reporter.gemspec"))
    assert_equal spec.version, installed_spec.version
    assert_equal ["railties"], installed_spec.runtime_dependencies.map(&:name)
    assert_equal snapshot.keys.reject { |path| path.end_with?(".gemspec") }.sort, installed_spec.files.sort
    refute defined?(ActiveRecord)
    refute defined?(ExecJS)
    assert_equal [], Dir[File.join(ENV.fetch("PATH"), "*")]

    asset = Rails.application.assets.find_asset("handrail_bug_reporter.js")
    refute_nil asset
    assert_equal File.join(installed, "app/assets/javascripts/handrail_bug_reporter.js"), File.realpath(asset.filename)
    manifest_path = Dir[File.join(Rails.root, "public/assets/.sprockets-manifest-*.json")].first
    refute_nil manifest_path, "rake assets:precompile did not produce a manifest"
    manifest = JSON.parse(File.read(manifest_path))
    compiled = manifest.fetch("assets").fetch("handrail_bug_reporter.js")
    output = File.join(Rails.root, "public/assets", compiled)
    assert File.size(output) > 0
    assert_equal asset.to_s, File.binread(output).force_encoding(asset.to_s.encoding)

    calls = []
    config = Handrail::BugReporter::Configuration.new(:api_base_url => "https://upstream.example/api",
      :project_id => "compat-project", :environment => "test", :report_token => "hbr_fixture",
      :max_attempts => 1)
    boundary = lambda do |uri, method, headers, body, _timeouts|
      calls << { :path => uri.path, :method => method, :headers => headers, :body => JSON.parse(body) }
      { :status => 201, :body => '{"bug_id":"compat-bug"}' }
    end
    resolver = lambda { |request| request.session[:principal] }
    Rails.application.config.handrail_bug_reporter_factory = Handrail::BugReporter::Factory.new(config,
      :http => boundary, :resolve_application_session_token => resolver)

    login = request("GET", "/fixture-session")
    assert_equal 200, login[0], login[2]
    cookie = Array(login[1]["set-cookie"] || login[1]["Set-Cookie"]).first
    assert_match(/httponly/i, cookie)
    @cookie = cookie.split(";", 2).first
    token = JSON.parse(login[2]).fetch("csrf")
    refute_empty token
    valid = request("POST", "/api/mobile-bug-reports", token)
    assert_equal 201, valid[0], valid[2]
    assert_equal({ "bug_id" => "compat-bug" }, JSON.parse(valid[2]))
    assert_equal 1, calls.length
    assert_equal "/api/mobile-bug-reports", calls.first[:path]
    assert_equal "POST", calls.first[:method].to_s.upcase
    assert_equal "fixture-principal", calls.first[:headers]["x-handrail-application-session-token"]
    assert_equal "Compatibility report", calls.first[:body]["title"]
    invalid = request("POST", "/api/mobile-bug-reports", "invalid-csrf")
    assert_equal 403, invalid[0], invalid[2]
    assert_equal({ "error" => "invalid_authenticity_token" }, JSON.parse(invalid[2]))
    assert_equal 1, calls.length, "invalid CSRF forwarded upstream"
    puts "SMOKE PASS: Ruby #{RUBY_VERSION}; Rails #{Rails.version}; Bundler #{Bundler::VERSION}"
    puts "INSTALL: #{installed}; #{snapshot.length} snapshot files verified"
    puts "PRECOMPILE: #{output}; #{File.size(output)} bytes; SHA256 #{Digest::SHA256.file(output).hexdigest}"
    puts "REQUESTS: valid=201/one HTTP boundary call; invalid=403/no additional call"
  end

  def request(method, path, token = "")
    body = method == "POST" ? JSON.generate(:title => "Compatibility report", :description => "Smoke fixture") : ""
    env = Rack::MockRequest.env_for("https://host.example" + path, :method => method, :input => body)
    env.merge!("CONTENT_TYPE" => "application/json", "HTTP_ORIGIN" => "https://host.example",
      "HTTP_COOKIE" => @cookie.to_s, "HTTP_X_CSRF_TOKEN" => token)
    status, headers, response = Rails.application.call(env)
    bytes = ""
    response.each { |part| bytes << part }
    response.close if response.respond_to?(:close)
    [status, headers, bytes]
  end
end
