require "test_helper"
require "tmpdir"
require "rubygems/package"

class ViewHelperTest < ScaffoldTestCase
  def test_real_host_views_without_sprockets
    run_fixture("0")
  end

  def test_real_host_views_with_fingerprinted_assets
    run_fixture("1")
  end

  def test_packaged_gem_renders_host_views_with_fingerprinted_assets
    Dir.mktmpdir("handrail-view-package") do |directory|
      archive = File.join(directory, "reporter.gem")
      spec = Gem::Specification.load(File.join(ROOT, "handrail-bug-reporter.gemspec"))
      capture_io { Gem::Package.build(spec, false, false, archive) }
      package = Gem::Package.new(archive)
      required = %w[app/helpers/handrail/bug_reporter_helper.rb app/assets/javascripts/handrail_bug_reporter.js]
      assert_empty(required - package.contents)
      extracted = File.join(directory, "extracted")
      package.extract_files(extracted)
      required.each do |path|
        assert_equal File.binread(File.join(ROOT, path)), File.binread(File.join(extracted, path))
      end
      run_fixture("1", extracted)
    end
  end

  private

  def run_fixture(sprockets, package_root = nil)
    environment = { "WITH_SPROCKETS" => sprockets, "PACKAGE_ROOT" => package_root,
      "RAILS_ENV" => "test", "RACK_ENV" => "test" }
    output = run_ruby(<<-'RUBY', environment)
      $LOAD_PATH.unshift(File.join(ENV["PACKAGE_ROOT"], "lib")) if ENV["PACKAGE_ROOT"]
      require File.expand_path("test/fixtures/views/rendering_checks")
    RUBY
    assert_match(/0 failures, 0 errors/, output)
  end
end
