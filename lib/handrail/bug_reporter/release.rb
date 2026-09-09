require "handrail/bug_reporter/version"

module Handrail
  module BugReporter
    # Static gem release metadata. This implementation has not been committed or
    # tagged: unknown provenance must stay null, not impersonate a JS release.
    module Release
      PACKAGE = "handrail-bug-reporter".freeze
      VERSION = BugReporter::VERSION.dup.freeze
      COMMIT = nil
      REF = nil
    end
  end
end
