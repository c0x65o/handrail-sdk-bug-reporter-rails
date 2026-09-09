require "handrail/bug_reporter/release"

module Handrail
  module BugReporter
    module Identity
      # Kept separate for backend compatibility verification. Ruby is not Node.
      SOURCE = "node_web_bug_reporter".freeze
      RUNTIME = "ruby".freeze
      PLATFORM = "ruby".freeze
      SDK_IDENTITY = {
        "source" => SOURCE,
        "platform" => PLATFORM,
        "reporter_sdk_runtime" => RUNTIME,
        "reporter_sdk_package" => Release::PACKAGE,
        "reporter_sdk_version" => Release::VERSION,
        "reporter_sdk_commit" => Release::COMMIT,
        "reporter_sdk_ref" => Release::REF
      }.freeze
    end
  end
end
