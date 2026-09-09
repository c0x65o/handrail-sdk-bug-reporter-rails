require "test_helper"
require "tmpdir"
require "rubygems/package"

class ForwardingPackageTest < ScaffoldTestCase
  def test_built_package_has_mountable_routes_controller_and_service
    Dir.mktmpdir("handrail-forwarding-package") do |directory|
      archive = File.join(directory, "reporter.gem")
      spec = Gem::Specification.load(File.join(ROOT, "handrail-bug-reporter.gemspec"))
      capture_io { Gem::Package.build(spec, false, false, archive) }
      package = Gem::Package.new(archive)
      required = %w[config/routes.rb app/controllers/handrail/bug_reporter/reports_controller.rb
        lib/handrail/bug_reporter/forwarding.rb lib/handrail/bug_reporter/forwarding_guard.rb]
      assert_empty(required - package.contents)
      extracted = File.join(directory, "extracted")
      package.extract_files(extracted)
      output = run_ruby(<<-'RUBY', "PACKAGE_ROOT" => extracted, "RAILS_ENV" => "test", "RACK_ENV" => "test")
        $LOAD_PATH.unshift(File.join(ENV.fetch("PACKAGE_ROOT"), "lib"))
        require "rack/mock"
        require File.expand_path("test/fixtures/mounted/config/application")
        app = MountedHost::Application.initialize!
        engine = Handrail::BugReporter::Engine
        raise "Loaded source engine" unless engine.root.to_s == ENV.fetch("PACKAGE_ROOT")
        response = Rack::MockRequest.new(app).get("https://host.example/api/mobile-bug-reports/policy")
        raise "Packaged mount failed: #{response.status} #{response.body}" unless response.status == 503 &&
          JSON.parse(response.body) == { "error" => "bug_reporting_unavailable" }
        raise "Controller not packaged" unless engine.root.join("app/controllers/handrail/bug_reporter/reports_controller.rb").file?
        config = Handrail::BugReporter::Configuration.new(:api_base_url => "https://upstream.example",
          :project_id => "package-project", :environment => "test", :report_token => "hbr_package_fixture")
        calls = []
        boundary = lambda do |uri, method, headers, body, timeouts|
          calls << uri.path
          { :status => 200, :body => '{"enabled":true}' }
        end
        app.config.handrail_bug_reporter_factory = Handrail::BugReporter::Factory.new(config, :http => boundary)
        response = Rack::MockRequest.new(app).get("https://host.example/api/mobile-bug-reports/policy")
        raise "Packaged forwarding failed" unless response.status == 200 && JSON.parse(response.body) == { "enabled" => true }
        raise "Unexpected calls" unless calls == ["/api/mobile-bug-reports/policy"]
        %w[/mine /bugs/bug.json].each do |path|
          response = Rack::MockRequest.new(app).get("https://host.example/api/mobile-bug-reports" + path)
          raise "Packaged history failed" unless response.status == 200 && response.body == '{"enabled":true}' &&
            calls.last == "/api/mobile-bug-reports" + path && response["cache-control"] == "private, no-store"
        end
        before = calls.length
        [["PUT", "/bugs/bug.json/archive"], ["DELETE", "/bugs/bug.json/archive"], ["POST", "/mine/archive-closed"]].each do |method, path|
          response = Rack::MockRequest.new(app).request(method, "https://host.example/api/mobile-bug-reports" + path)
          raise "Packaged archive CSRF failed" unless response.status == 403 &&
            JSON.parse(response.body) == { "error" => "invalid_authenticity_token" } && calls.length == before
        end
        puts "Packaged engine mount OK"
      RUBY
      assert_equal "Packaged engine mount OK\n", output
    end
  end
end
