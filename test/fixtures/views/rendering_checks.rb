require "minitest/autorun"
require "json"
require "rack/mock"
require "nokogiri"
require_relative "config/application"

ReporterViewHost::Application.initialize!

class ReporterRenderingChecks < Minitest::Test
  ENDPOINT = "/feedback/api/mobile-bug-reports"
  TOKEN = "hbr_NEVER_RENDER_THIS_TOKEN"
  HOSTILE = "\" ' & <img src=x onerror=alert(1)> </script><script>alert(2)</script> \u2028\u2029 snowman \u2603"

  def setup
    @calls = []
    configuration = Handrail::BugReporter::Configuration.new(
      :api_base_url => "https://private-upstream.example", :project_id => "host-project",
      :environment => "staging", :report_token => TOKEN)
    @factory = Handrail::BugReporter::Factory.new(configuration,
      :resolve_application_session_token => lambda { |request| @calls << :resolver; raise "Resolver called by view" },
      :http => lambda { |*args| @calls << :http; raise "HTTP called by view" })
    Rails.application.config.handrail_bug_reporter_factory = @factory
    Rails.application.config.reporter_view_options = { :endpoint => ENDPOINT }
  end

  def teardown
    assert_empty @calls, "Rendering must not invoke credentials or transport"
  end

  def render_options(options = {}, script_name = "")
    Rails.application.config.reporter_view_options = { :endpoint => ENDPOINT }.merge(options)
    response = Rack::MockRequest.new(Rails.application).get("/view", "SCRIPT_NAME" => script_name)
    assert_equal 200, response.status, response.body
    Nokogiri::HTML.fragment(response.body)
  end

  def payload(document)
    JSON.parse(document.at_css('[data-handrail-bug-reporter="1"]')["data-handrail-bug-reporter-options"])
  end

  def helper
    controller = ReporterViewsController.new
    controller.set_request!(ActionDispatch::Request.new(Rack::MockRequest.env_for("/view")))
    controller.view_context
  end

  def test_default_launcher_and_only_allowlisted_public_configuration
    document = render_options
    island = document.at_css('[data-handrail-bug-reporter="1"]')
    assert_equal "launcher", island["data-handrail-bug-reporter-mode"]
    assert_empty island.children
    assert_equal({ "transport" => "same-origin", "enabled" => true,
      "apiBaseUrl" => ENDPOINT, "projectId" => "host-project", "environment" => "staging",
      "allowScreenshots" => false }, payload(document)["config"])
    assert_equal true, payload(document)["showHistory"]
    assert_equal({}, payload(document)["initialForm"])
    [TOKEN, "private-upstream", "Configuration", "Factory", "resolver", "reportToken", "authorization"].each do |secret|
      refute_includes document.to_html, secret
    end
  end

  def test_custom_launcher_is_metadata_and_preserves_host_content
    document = render_options(:mode => "custom-launcher", :launcher_id => "host-bug-button")
    island = document.at_css('[data-handrail-bug-reporter="1"]')
    assert_equal "custom-launcher", island["data-handrail-bug-reporter-mode"]
    assert_equal "host-bug-button", island["data-handrail-bug-reporter-launcher-id"]
    assert_equal "Host content", document.at_css("#host-content").text
    assert_equal "host-theme", document.at_css("#host-content")["class"]
    assert_equal "Help", document.at_css("#host-bug-button").text
    assert_empty island.children
    refute payload(document).key?("mode")
  end

  def test_disabled_and_unconfigured_render_no_island_or_asset
    [nil, Handrail::BugReporter::Factory.new(Handrail::BugReporter::Configuration.new(:enabled => false))].each do |factory|
      Rails.application.config.handrail_bug_reporter_factory = factory
      document = render_options(:endpoint => "invalid")
      assert_nil document.at_css("[data-handrail-bug-reporter]")
      assert_empty document.css("script")
      assert_equal "Host content", document.at_css("#host-content").text
    end
    Rails.application.config.handrail_bug_reporter_factory = @factory
    assert_empty render_options(:enabled => false).css("[data-handrail-bug-reporter], script")
  end

  def test_context_features_and_scoped_appearance_round_trip_hostile_strings
    options = { :label => HOSTILE, :heading => HOSTILE, :show_history => false,
      :allow_screenshots => true, :load_policy_on_mount => false, :history_page_size => 37,
      :context => { :route => HOSTILE, :app_version => HOSTILE, :build_number => "42",
        :commit_sha => "abc", :app_flavor => "internal", :profile_key => "public-profile" },
      :appearance => { :theme_mode => :dark, :class_name => HOSTILE,
        :tokens => { :accent => HOSTILE, :fontFamily => HOSTILE },
        :style => { "--handrail-bug-radius" => HOSTILE } } }
    original = Marshal.dump(options)
    document = render_options(options)
    data = payload(document)
    assert_equal HOSTILE, data["initialForm"]["route"]
    assert_equal HOSTILE, data["initialForm"]["appVersion"]
    assert_equal "staging", data["config"]["environment"]
    assert_equal HOSTILE, data["label"]
    assert_equal HOSTILE, data["heading"]
    assert_equal false, data["showHistory"]
    assert_equal false, data["loadPolicyOnMount"]
    assert_equal true, data["config"]["allowScreenshots"]
    assert_equal 37, data["historyPageSize"]
    assert_equal({ "themeMode" => "dark", "className" => HOSTILE,
      "tokens" => { "accent" => HOSTILE, "fontFamily" => HOSTILE },
      "style" => { "--handrail-bug-radius" => HOSTILE } }, data["appearance"])
    assert_empty document.css("img, style, [onerror], [onclick], [style]")
    assert_equal 1, document.css("script").length
    assert_empty document.at_css("script").text
    assert_equal "host-theme", document.at_css("#host-content")["class"]
    assert_equal original, Marshal.dump(options)
    json = document.at_css("[data-handrail-bug-reporter]")["data-handrail-bug-reporter-options"]
    refute_match(/[<>&\u2028\u2029]/, json)
  end

  def test_all_bundle_tokens_and_themes_are_supported
    %w[auto light dark].each do |theme|
      tokens = Handrail::BugReporterHelper::TOKENS.each_with_object({}) { |name, hash| hash[name] = "test" }
      styles = Handrail::BugReporterHelper::STYLE_KEYS.each_with_object({}) { |name, hash| hash[name] = "12px" }
      data = payload(render_options(:appearance => { :theme_mode => theme, :tokens => tokens, :style => styles }))
      assert_equal theme, data["appearance"]["themeMode"]
      assert_equal tokens, data["appearance"]["tokens"]
      assert_equal styles, data["appearance"]["style"]
    end
    data = payload(render_options(:appearance => { :style => { "--handrail-bug-radius" => 0 } }))
    assert_equal 0, data["appearance"]["style"]["--handrail-bug-radius"]
  end

  def test_hostile_public_configuration_is_escaped_without_server_secrets
    configuration = Handrail::BugReporter::Configuration.new(
      :api_base_url => "https://private-upstream.example", :project_id => HOSTILE,
      :environment => HOSTILE, :report_token => TOKEN)
    Rails.application.config.handrail_bug_reporter_factory = Handrail::BugReporter::Factory.new(configuration)
    document = render_options
    assert_equal HOSTILE, payload(document)["config"]["projectId"]
    assert_equal configuration.environment, payload(document)["config"]["environment"]
    assert_equal 1, document.css("script").length
    assert_empty document.css("img, [onerror]")
    refute_includes document.to_html, TOKEN
    refute_includes document.to_html, "private-upstream"
  end

  def test_rejects_nonlocal_ambiguous_and_unmounted_endpoints
    invalid = [nil, "https://host.example" + ENDPOINT, "//evil.example" + ENDPOINT,
      "javascript:alert(1)", "\\\\evil.example" + ENDPOINT, "/wrong/api/mobile-bug-reports",
      "/api/mobile-bug-reports", "/other/api/mobile-bug-reports", ENDPOINT + "/policy", ENDPOINT + "/", ENDPOINT + "?token=bad",
      ENDPOINT + "#fragment", "/x/../feedback/api/mobile-bug-reports", "/./feedback/api/mobile-bug-reports",
      "/%2f/feedback/api/mobile-bug-reports", "/%252f/feedback/api/mobile-bug-reports",
      "/feedback//api/mobile-bug-reports", "/feedback\n/api/mobile-bug-reports", "/feedback/api"]
    invalid.each do |endpoint|
      assert_raises(ArgumentError) { helper.handrail_bug_reporter(:endpoint => endpoint) }
    end
    assert_equal ENDPOINT, payload(render_options)["config"]["apiBaseUrl"]
  end

  def test_host_script_name_is_preserved
    document = render_options({ :endpoint => "/tenant" + ENDPOINT }, "/tenant")
    assert_equal "/tenant" + ENDPOINT, payload(document)["config"]["apiBaseUrl"]
  end

  def test_rejects_objects_credentials_callbacks_and_unsupported_options
    invalid = [{ :config => @factory.configuration }, { :report_token => TOKEN },
      { :context => @factory }, { :context => { :route => @factory.configuration } },
      { :context => { :session => TOKEN } }, { :appearance => { :style => { :position => "fixed" } } },
      { :appearance => { :tokens => { :unknown => "red" } } }, { :appearance => { :theme_mode => "evil" } },
      { :enabled => "false" }, { :show_history => "false" }, { :load_policy_on_mount => lambda { raise "called" } },
      { :allow_screenshots => @factory }, { :history_page_size => 51 },
      { :mode => "custom-launcher" }, { :mode => "custom-launcher", :launcher_id => HOSTILE },
      { :mode => "other" }, { :launcher_id => "host-bug-button" }]
    invalid.each do |options|
      error = assert_raises(ArgumentError) { helper.handrail_bug_reporter({ :endpoint => ENDPOINT }.merge(options)) }
      refute_includes error.message, TOKEN
    end
  end

  def test_external_asset_uses_rails_resolution_and_optional_sprockets
    document = render_options
    script = document.at_css("script")
    assert script["defer"]
    assert_empty script.text
    if ENV["WITH_SPROCKETS"] == "1"
      manifest = JSON.parse(File.read(File.expand_path("fingerprint-manifest.json", File.dirname(__FILE__))))
      digest_path = manifest.fetch("assets").fetch("handrail_bug_reporter.js")
      assert_equal "https://assets.host.example/assets/" + digest_path, script["src"]
      assert_includes Rails.application.config.assets.precompile, "handrail_bug_reporter.js"
      assert_nil Rails.application.assets, "Must resolve from manifest with runtime compilation disabled"
    else
      assert_equal "https://assets.host.example/javascripts/handrail_bug_reporter.js", script["src"]
      refute Rails.application.config.respond_to?(:assets)
    end
    if ENV["PACKAGE_ROOT"]
      assert_equal ENV["PACKAGE_ROOT"], Handrail::BugReporter::Engine.root.to_s
    end
  end
end
