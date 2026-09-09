require "test_helper"
require "tmpdir"

class ScaffoldTest < ScaffoldTestCase
  def test_gemspec_evaluates_without_rails_from_another_directory
    Dir.mktmpdir("handrail-gemspec") do |directory|
      output = run_ruby(<<-'RUBY', { "SPEC_PATH" => File.join(ROOT, "handrail-bug-reporter.gemspec") }, directory)
        module RejectRails
          def require(path)
            raise "Gemspec must not load Rails: #{path}" if path =~ /\A(?:rails|active_)/
            super
          end
        end
        Kernel.prepend(RejectRails)
        spec = Gem::Specification.load(ENV.fetch("SPEC_PATH"))
        raise "Invalid gemspec" unless spec && spec.version.to_s == Handrail::BugReporter::VERSION
        raise "Rails loaded" if defined?(Rails)
        raise "Engine loaded" if defined?(Handrail::BugReporter::Engine)
        raise "Unexpected runtime dependency" unless spec.runtime_dependencies.map(&:name) == ["railties"]
        required = %w[lib/handrail/bug_reporter.rb lib/handrail/bug_reporter/version.rb lib/handrail/bug_reporter/engine.rb
          lib/handrail/bug_reporter/forwarding.rb lib/handrail/bug_reporter/forwarding_guard.rb
          config/routes.rb app/controllers/handrail/bug_reporter/reports_controller.rb]
        raise "Missing packaged libraries" unless (required - spec.files).empty?
        raise "Ruby target excluded" unless spec.required_ruby_version.satisfied_by?(Gem::Version.new("2.3.0"))
        raise "Rails target excluded" unless spec.runtime_dependencies.first.requirement.satisfied_by?(Gem::Version.new("4.2.0"))
        puts "gemspec OK"
      RUBY
      assert_equal "gemspec OK\n", output
    end
  end

  def test_entry_point_loads_and_registers_once_without_booting_an_application
    output = run_ruby(<<-'RUBY')
      require "handrail/bug_reporter"
      engine = Handrail::BugReporter::Engine
      raise "Not an Engine" unless engine < Rails::Engine
      raise "Not isolated" unless engine.isolated?
      raise "Wrong namespace" unless engine.railtie_namespace == Handrail::BugReporter
      raise "Not registered" unless Rails::Engine.subclasses.include?(engine)
      raise "Require not idempotent" if require "handrail/bug_reporter"
      raise "Engine replaced" unless Handrail::BugReporter::Engine.equal?(engine)
      raise "Application booted" if Rails.respond_to?(:application) && Rails.application
      raise "ActiveRecord loaded" if defined?(ActiveRecord)
      puts "require OK"
    RUBY
    assert_equal "require OK\n", output
  end

  def test_entry_point_loads_after_rails
    output = run_ruby(<<-'RUBY')
      require "rails"
      require "action_controller/railtie"
      require "handrail/bug_reporter"
      raise "Not registered" unless Rails::Engine.subclasses.include?(Handrail::BugReporter::Engine)
      raise "ActiveRecord loaded" if defined?(ActiveRecord)
      puts "Rails-first require OK"
    RUBY
    assert_equal "Rails-first require OK\n", output
  end

  def test_real_host_boot_is_unchanged_by_engine
    source = <<-'RUBY'
      require "json"
      require "rack/mock"
      require File.expand_path("test/fixtures/minimal/config/application")
      app = ScaffoldHost::Application.initialize!
      raise "Host did not boot" unless app.initialized?
      raise "ActiveRecord loaded" if defined?(ActiveRecord) || Gem.loaded_specs.key?("activerecord")
      if ENV["WITH_HANDRAIL"] == "1"
        engine = Handrail::BugReporter::Engine
        raise "Engine not in booted host" unless app.railties.any? { |railtie| railtie.is_a?(engine) }
        paths = engine.routes.routes.map { |route| route.path.spec.to_s }
        raise "Missing opt-in routes" unless paths == ["/", "/policy"]
      end
      request = Rack::MockRequest.new(app)
      response = request.get("/health")
      missing = request.get("/unclaimed/nested/path")
      unmounted = request.post("/api/mobile-bug-reports")
      puts JSON.generate(
        :status => response.status, :body => response.body,
        :missing_status => missing.status,
        :unmounted_status => unmounted.status,
        :routes => app.routes.routes.map { |route| [route.verb.to_s, route.path.spec.to_s] },
        :middleware => app.middleware.map { |middleware| middleware.klass.name }
      )
    RUBY
    environment = { "RAILS_ENV" => "test", "RACK_ENV" => "test" }
    baseline = JSON.parse(run_ruby(source, environment.merge("WITH_HANDRAIL" => "0")))
    with_engine = JSON.parse(run_ruby(source, environment.merge("WITH_HANDRAIL" => "1")))
    assert_equal 200, with_engine.fetch("status")
    assert_equal "<p>host only</p>", with_engine.fetch("body")
    assert_equal 404, with_engine.fetch("missing_status")
    assert_equal 404, with_engine.fetch("unmounted_status")
    assert_equal baseline, with_engine, "Engine changed host routes, middleware, or response"
  end
end
