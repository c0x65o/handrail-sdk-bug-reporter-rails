require "test_helper"
require "tmpdir"
require "fileutils"
require "rubygems/package"

class InstallGeneratorTest < ScaffoldTestCase
  INITIALIZER = "config/initializers/handrail_bug_reporter.rb"
  GENERATOR = "lib/generators/handrail/bug_reporter/install_generator.rb"
  ENVIRONMENT = {
    "RAILS_ENV" => "test", "RACK_ENV" => "test",
    "HANDRAIL_API_URL" => "https://generation.example",
    "HANDRAIL_PROJECT_ID" => "generation-project-sentinel",
    "HANDRAIL_BUG_REPORT_TOKEN" => "generation-token-sentinel"
  }.freeze

  def with_host
    Dir.mktmpdir("handrail-install") do |host|
      write(host, "config/application.rb", <<-'RUBY')
        require "logger"
        require "rails"
        require "action_controller/railtie"
        require "handrail/bug_reporter"
        module InstallHost
          class Application < Rails::Application
            config.root = File.expand_path("..", File.dirname(__FILE__))
            config.eager_load = false
            config.cache_classes = true
            config.secret_key_base = "install-fixture-only-" * 8
            config.logger = Logger.new(nil)
            config.active_support.deprecation = :stderr
            config.hosts.clear if config.respond_to?(:hosts)
            config.action_controller.allow_forgery_protection = true
            config.session_store :cookie_store, :key => "_install_host"
          end
        end
      RUBY
      write(host, "config/routes.rb", "Rails.application.routes.draw do\n  get '/health' => proc { [200, {}, ['host']] }\nend\n")
      write(host, "app/controllers/application_controller.rb", <<-'RUBY')
        class ApplicationController < ActionController::Base
          protect_from_forgery :with => :exception
        end
      RUBY
      write(host, "app/views/layouts/application.html.erb",
        "<html><head><%= csrf_meta_tags %></head><body><%= yield %></body></html>\n")
      write(host, "app/assets/javascripts/application.js", "// host-owned asset\n")
      yield host
    end
  end

  def write(host, path, contents)
    destination = File.join(host, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.binwrite(destination, contents)
  end

  def snapshot(host)
    Dir[File.join(host, "**/*")].select { |path| File.file?(path) }.each_with_object({}) do |path, files|
      files[path.sub(host + "/", "")] = File.binread(path)
    end
  end

  def in_host(host, source, environment = {}, sdk_root = ROOT)
    bootstrap = <<-'RUBY'
      $LOAD_PATH.unshift(File.join(ENV.fetch("SDK_ROOT"), "lib"))
      require File.join(ENV.fetch("HOST_ROOT"), "config/application")
      app = InstallHost::Application.instance
      app.initialize! unless ENV["BOOT_HOST"] == "0"
      raise "Wrong SDK loaded" unless Handrail::BugReporter::Engine.root.to_s == ENV.fetch("SDK_ROOT")
    RUBY
    run_ruby(bootstrap + source, ENVIRONMENT.merge(environment).merge(
      "HOST_ROOT" => host, "SDK_ROOT" => sdk_root), host)
  end

  def generate(host, arguments = [], sdk_root = ROOT)
    in_host(host, <<-'RUBY', { "GENERATOR_ARGUMENTS" => JSON.generate(arguments), "BOOT_HOST" => "0" }, sdk_root)
      require "rails/generators"
      app.load_generators
      generator = Rails::Generators.find_by_namespace("handrail:bug_reporter:install")
      raise "Generator not discovered" unless generator && generator.namespace == "handrail:bug_reporter:install"
      expected = File.join(ENV.fetch("SDK_ROOT"), "lib/generators/handrail/bug_reporter/templates")
      raise "Wrong templates loaded" unless generator.source_root == expected
      Rails::Generators.invoke("handrail:bug_reporter:install",
        JSON.parse(ENV.fetch("GENERATOR_ARGUMENTS")), :destination_root => ENV.fetch("HOST_ROOT"))
    RUBY
  end

  def configuration(host, environment = {}, sdk_root = ROOT)
    JSON.parse(in_host(host, <<-'RUBY', environment, sdk_root))
      factory = app.config.handrail_bug_reporter_factory
      raise "Wrong factory API" unless factory.is_a?(Handrail::BugReporter::Factory)
      request = ActionDispatch::Request.new("HTTP_AUTHORIZATION" => "caller-token",
        "HTTP_X_HANDRAIL_APPLICATION_SESSION" => "caller-session",
        "QUERY_STRING" => "user_id=123&email=caller@example.test")
      first = factory.for_request(request)
      second = factory.for_request(request)
      raise "Clients must be request scoped" unless first.is_a?(Handrail::BugReporter::Client) && !first.equal?(second)
      resolver = factory.instance_variable_get(:@resolver)
      raise "Default authentication must stay anonymous" unless resolver.respond_to?(:call) && resolver.call(request).nil?
      configuration = factory.configuration
      puts JSON.generate(:status => configuration.status, :project_id => configuration.project_id,
        :environment => configuration.environment, :endpoints => configuration.endpoints,
        :headers => configuration.send(:report_headers),
        :csrf => app.config.action_controller.allow_forgery_protection)
    RUBY
  end

  def test_discovery_default_no_mount_and_manual_instructions
    with_host do |host|
      before = snapshot(host)
      output = generate(host)
      after = snapshot(host)
      assert_equal [INITIALIZER], after.keys - before.keys
      before.each { |path, bytes| assert_equal bytes, after.fetch(path), path }
      assert_includes output, "--mount"
      assert_includes output, '<%= handrail_bug_reporter(:endpoint => handrail_bug_reporter_path) %>'
      %w[csrf_meta_tags session Sprockets javascript_include_tag application-session].each do |requirement|
        assert_includes output, requirement
      end
      assert_equal true, configuration(host).fetch("csrf")
      output = in_host(host, <<-'RUBY')
        require "rack/mock"
        response = Rack::MockRequest.new(app).post("/handrail/api/mobile-bug-reports")
        raise "Default generator mounted engine" unless response.status == 404
        puts "unmounted"
      RUBY
      assert_equal "unmounted\n", output
    end
  end

  def test_explicit_mount_repeated_and_forced_invocations_preserve_all_bytes
    with_host do |host|
      before = snapshot(host)
      generate(host, ["--mount"])
      installed = snapshot(host)
      before.each do |path, bytes|
        assert_equal bytes, installed.fetch(path), path unless path == "config/routes.rb"
      end
      generate(host, ["--mount"])
      generate(host, ["--mount", "--force"])
      generate(host)
      assert_equal installed, snapshot(host)
      assert_equal 1, installed.fetch("config/routes.rb").scan("mount Handrail::BugReporter::Engine").length
      assert_equal 1, installed.fetch(INITIALIZER).scan("handrail_bug_reporter_factory =").length
      output = in_host(host, <<-'RUBY')
        endpoint = app.routes.url_helpers.handrail_bug_reporter_path
        raise "Wrong mount helper" unless endpoint == "/handrail/api/mobile-bug-reports"
        route = app.routes.recognize_path(endpoint, :method => :post)
        raise "Wrong route" unless route[:controller] == "handrail/bug_reporter/reports" && route[:action] == "create"
        require "rack/mock"
        response = Rack::MockRequest.new(app).post(endpoint,
          "CONTENT_TYPE" => "application/json", :input => '{}')
        raise "CSRF check failed: #{response.status} #{response.body}" unless response.status == 403 &&
          JSON.parse(response.body) == { "error" => "invalid_authenticity_token" }
        puts "mounted and CSRF protected"
      RUBY
      assert_equal "mounted and CSRF protected\n", output
    end
  end

  def test_existing_custom_initializer_is_byte_preserved_even_with_force
    with_host do |host|
      custom = "# Custom host settings: caf\xC3\xA9\r\nRails.application.config.handrail_bug_reporter_factory = nil\r\n"
      write(host, INITIALIZER, custom)
      generate(host)
      generate(host, ["--mount", "--force"])
      assert_equal custom.b, File.binread(File.join(host, INITIALIZER))
    end
  end

  def test_existing_custom_multiline_mount_is_preserved
    with_host do |host|
      routes = <<-'RUBY'
Rails.application.routes.draw do
  mount(
    Handrail::BugReporter::Engine,
    :at => "/support/api/mobile-bug-reports",
    :as => :support_feedback
  )
end
      RUBY
      write(host, "config/routes.rb", routes)
      generate(host, ["--mount"])
      generate(host, ["--mount", "--force"])
      assert_equal routes, File.binread(File.join(host, "config/routes.rb"))
      output = in_host(host, 'puts app.routes.url_helpers.support_feedback_path')
      assert_equal "/support/api/mobile-bug-reports\n", output
    end
  end

  def test_mount_in_a_separate_route_file_is_preserved
    with_host do |host|
      write(host, "config/routes.rb", "Rails.application.routes.draw do\n  instance_eval(File.read(Rails.root.join('config/routes/reporter.rb')))\nend\n")
      write(host, "config/routes/reporter.rb",
        'mount Handrail::BugReporter::Engine => "/support/api/mobile-bug-reports", :as => "support_feedback"')
      before = snapshot(host)
      generate(host, ["--mount", "--force"])
      before.each { |path, bytes| assert_equal bytes, snapshot(host).fetch(path), path }
    end
  end

  def test_initializer_symlink_is_preserved_even_with_force
    with_host do |host|
      target = File.join(host, "host_settings.rb")
      FileUtils.mkdir_p(File.join(host, "config/initializers"))
      File.symlink(target, File.join(host, INITIALIZER))
      # A dangling symlink must not become a generated credentials file.
      generate(host, ["--force"])
      assert File.symlink?(File.join(host, INITIALIZER))
      refute File.exist?(target)
    end
  end

  def test_runtime_env_references_and_actual_sdk_configuration
    with_host do |host|
      generate(host)
      source = File.read(File.join(host, INITIALIZER))
      assert_equal %w[HANDRAIL_API_URL HANDRAIL_BUG_REPORT_TOKEN HANDRAIL_PROJECT_ID], source.scan(/ENV\["([^"]+)"\]/).flatten.sort
      ENVIRONMENT.values.each { |value| refute_includes source, value unless value == "test" }
      runtime = {
        "HANDRAIL_API_URL" => "https://runtime.example/base",
        "HANDRAIL_PROJECT_ID" => "runtime-project",
        "HANDRAIL_BUG_REPORT_TOKEN" => "runtime-token"
      }
      result = configuration(host, runtime)
      assert_equal "ready", result.fetch("status")
      assert_equal "runtime-project", result.fetch("project_id")
      assert_equal "https://runtime.example/base/api/mobile-bug-reports", result.fetch("endpoints").fetch("reports")
      assert_equal({ "authorization" => "Bearer runtime-token" }, result.fetch("headers"))
      %w[development test staging production].each do |environment|
        assert_equal environment, configuration(host, runtime.merge("RAILS_ENV" => environment)).fetch("environment")
      end
      custom = configuration(host, runtime.merge("RAILS_ENV" => "preview"))
      assert_nil custom.fetch("environment")
      assert_equal "misconfigured", custom.fetch("status")
      missing = configuration(host, "HANDRAIL_BUG_REPORT_TOKEN" => nil)
      assert_equal "misconfigured", missing.fetch("status")
      write(host, INITIALIZER, source.sub('"staging" => "staging",', '"staging" => "staging", "preview" => "staging",'))
      assert_equal "staging", configuration(host, runtime.merge("RAILS_ENV" => "preview")).fetch("environment")
    end
  end

  def test_documented_authentication_example_uses_current_trusted_request_context
    with_host do |host|
      generate(host)
      source = File.read(File.join(host, INITIALIZER))
      source = source.sub('# principal =', 'principal =').sub('# principal &&', 'principal &&')
      source = source.sub("    nil\n", "")
      write(host, INITIALIZER, source)
      output = in_host(host, <<-'RUBY')
        installed = app.config.handrail_bug_reporter_factory
        calls = []
        # Only the outbound HTTP boundary is replaced; use the generated
        # configuration and callable with the real Factory/Client/Transport.
        factory = Handrail::BugReporter::Factory.new(installed.configuration,
          :resolve_application_session_token => installed.instance_variable_get(:@resolver),
          :http => lambda do |uri, method, headers, body, timeouts|
            calls << headers
            { :status => 200, :body => '{}' }
          end)
        request = ActionDispatch::Request.new("HTTP_AUTHORIZATION" => "caller-token",
          "HTTP_X_HANDRAIL_APPLICATION_SESSION" => "caller-session")
        client = factory.for_request(request)
        client.request(:method => "GET", :endpoint => :policy)
        principal = Struct.new(:handrail_application_session_token).new("trusted-session-one")
        request.env["my_app.authenticated_principal"] = principal
        client.request(:method => "GET", :endpoint => :policy)
        principal.handrail_application_session_token = "trusted-session-two"
        client.request(:method => "GET", :endpoint => :policy)
        request.env.delete("my_app.authenticated_principal")
        client.request(:method => "GET", :endpoint => :policy)
        sessions = calls.map { |headers| headers["x-handrail-application-session-token"] }
        raise "Resolver did not use current trusted context" unless sessions == [nil, "trusted-session-one", "trusted-session-two", nil]
        raise "Report token confused with session" unless calls.all? { |headers| headers["authorization"] == "Bearer generation-token-sentinel" }
        puts "trusted request-scoped authentication"
      RUBY
      assert_equal "trusted request-scoped authentication\n", output
    end
  end

  def test_built_package_can_discover_generate_and_boot_using_its_own_templates
    Dir.mktmpdir("handrail-generator-package") do |directory|
      archive = File.join(directory, "reporter.gem")
      spec = Gem::Specification.load(File.join(ROOT, "handrail-bug-reporter.gemspec"))
      capture_io { Gem::Package.build(spec, false, false, archive) }
      package = Gem::Package.new(archive)
      required = [GENERATOR,
        "lib/generators/handrail/bug_reporter/templates/initializer.rb.tt",
        "lib/generators/handrail/bug_reporter/templates/instructions.txt"]
      assert_empty required - package.contents
      extracted = File.join(directory, "extracted")
      package.extract_files(extracted)
      with_host do |host|
        generate(host, ["--mount"], extracted)
        installed = snapshot(host)
        generate(host, ["--mount", "--force"], extracted)
        assert_equal installed, snapshot(host)
        assert_equal "ready", configuration(host, {}, extracted).fetch("status")
      end
    end
  end
end
