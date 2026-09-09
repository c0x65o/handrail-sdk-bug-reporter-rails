require "handrail/bug_reporter/version"
require "handrail/bug_reporter/release_manifest"

module Handrail
  module BugReporter
    # Resolve relative to the installed SDK, never the host's cwd, Git or env.
    module Release
      manifest = ReleaseManifest.verify!(File.expand_path("../../..", File.dirname(__FILE__)), BugReporter::VERSION)
      rails = manifest.fetch("rails")
      PACKAGE = rails.fetch("package").freeze
      VERSION = rails.fetch("version").freeze
      COMMIT = rails.fetch("commit").freeze
      REF = rails.fetch("ref").freeze
      PROVENANCE = rails.fetch("provenance").freeze
      BUNDLED_JS = manifest.fetch("bundled_js").each_value { |value| value.freeze }.freeze
    end
  end
end
