require "json"
require "digest"

module Handrail
  module BugReporter
    # Offline validation shared by the gemspec, runtime identity and release tool.
    # Git verification belongs exclusively to scripts/verify_release.rb.
    module ReleaseManifest
      FILE = "release-manifest.json".freeze
      ASSET = "app/assets/javascripts/handrail_bug_reporter.js".freeze
      PACKAGE = "handrail-bug-reporter".freeze
      FULL_COMMIT = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/
      SHA256 = /\A[0-9a-f]{64}\z/
      VERSION = /\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\.[a-zA-Z0-9]+)*\z/
      JS_BASELINE = {
        "package" => "@handrail/bug-reporter", "version" => "0.4.50",
        "ref" => "refs/tags/v0.4.50",
        "commit" => "7dfb33f548448f864cf957f19d96f8b5a27bc787"
      }.freeze
      SOURCE_FILES = %w[handrail-bug-reporter.gemspec frontend/upstream.json
        frontend/entry.jsx frontend/rails_adapter.js package.json package-lock.json
        scripts/build.mjs scripts/contract.mjs].freeze
      SOURCE_FINGERPRINT = "private-contributor-v1".freeze
      CONTRIBUTOR_FILES = %w[package.json package-lock.json].freeze
      CONTRIBUTOR_VERSION = /\A
        (?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)
        (?:-(?:0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)
          (?:\.(?:0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*)?
        (?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?\z/x

      class Invalid < StandardError; end

      # Ambiguous duplicate declarations must not disappear during parsing.
      class ContributorObject < Hash
        def []=(key, value)
          raise Invalid, "Duplicate contributor JSON key: #{key}" if key?(key)
          super
        end
      end
      module_function

      def check(condition, message)
        raise Invalid, message unless condition
      end

      def read_json(path)
        JSON.parse(File.read(path))
      rescue Errno::ENOENT, JSON::ParserError => error
        raise Invalid, "Missing or malformed #{path}: #{error.message}"
      end

      def runtime_files(root)
        Dir.chdir(root) do
          (Dir["lib/**/*.rb", "config/routes.rb", "app/controllers/**/*.rb",
            "app/helpers/**/*.rb", "lib/generators/handrail/bug_reporter/templates/*"] + [ASSET]).uniq.sort
        end
      end

      def source_fingerprint_mode(manifest)
        return nil unless manifest.key?("source_fingerprint")
        check(manifest["source_fingerprint"] == SOURCE_FINGERPRINT, "Unsupported source fingerprint mode")
        manifest["source_fingerprint"]
      end

      def canonical_json(value)
        case value
        when Hash
          value.keys.sort.each_with_object({}) { |key, result| result[key] = canonical_json(value[key]) }
        when Array
          value.map { |entry| canonical_json(entry) }
        else
          value
        end
      end

      def contributor_documents(bytes)
        documents = CONTRIBUTOR_FILES.map do |path|
          check(bytes.key?(path), "Missing contributor input: #{path}")
          JSON.parse(bytes.fetch(path), :object_class => ContributorObject)
        end
        package, lock = documents
        check(package.is_a?(Hash) && package["private"] == true,
          "Contributor package.json must declare private=true")
        check(lock.is_a?(Hash) && lock["packages"].is_a?(Hash) && lock["packages"][""].is_a?(Hash),
          "Malformed contributor package-lock.json root package")
        versions = [package["version"], lock["version"], lock["packages"][""]["version"]]
        check(versions.all? { |version| version.is_a?(String) && CONTRIBUTOR_VERSION =~ version },
          "Malformed contributor version declaration")
        check(versions.uniq.length == 1, "Contributor version declarations mismatch")
        package.delete("version")
        lock.delete("version")
        lock["packages"][""].delete("version")
        Hash[CONTRIBUTOR_FILES.zip(documents)]
      rescue JSON::ParserError => error
        raise Invalid, "Malformed contributor JSON: #{error.message}"
      end

      # The byte reader also allows Git verification to validate the selected
      # revision's declarations, never borrowing them from the working tree.
      def hashes(root, paths, mode = nil)
        check(mode.nil? || mode == SOURCE_FINGERPRINT, "Unsupported source fingerprint mode")
        bytes = paths.sort.each_with_object({}) do |path, result|
          if block_given?
            result[path] = yield path
          else
            absolute = File.join(root, path)
            check(File.file?(absolute) && !File.symlink?(absolute), "Missing or unsafe artifact: #{path}")
            result[path] = File.binread(absolute)
          end
        end
        documents = mode ? contributor_documents(bytes) : {}
        bytes.each_with_object({}) do |(path, content), result|
          content = JSON.generate(canonical_json(documents[path])) if documents.key?(path)
          result[path] = Digest::SHA256.hexdigest(content)
        end
      end

      def validate_identity(identity, package, version)
        check(identity.is_a?(Hash), "Missing #{package} identity")
        check(identity["package"] == package && identity["version"] == version &&
          version.is_a?(String) && VERSION =~ version, "Package/version mismatch for #{package}")
        commit, ref = identity.values_at("commit", "ref")
        check(commit.is_a?(String) && FULL_COMMIT =~ commit, "Invalid full commit for #{package}")
        check(ref == "commit:#{commit}" || ref == "refs/tags/v#{version}", "Version/ref or commit/ref mismatch for #{package}")
      end

      def verify!(root, version, source = false, manifest = nil)
        manifest ||= read_json(File.join(root, FILE))
        check(manifest.is_a?(Hash) && manifest["schema_version"] == 1, "Unsupported release manifest schema")
        mode = source_fingerprint_mode(manifest)
        rails = manifest["rails"]
        check(rails.is_a?(Hash) && rails["package"] == PACKAGE && rails["version"] == version &&
          version.is_a?(String) && VERSION =~ version, "Rails manifest version is stale or malformed")
        case rails["provenance"]
        when "source_snapshot"
          check(rails.key?("commit") && rails.key?("ref") && rails["commit"].nil? && rails["ref"].nil?,
            "A source snapshot cannot claim an exact release")
          base = rails["base_commit"]
          check(base.is_a?(String) && FULL_COMMIT =~ base && rails["base_ref"] == "commit:#{base}",
            "Invalid snapshot base provenance")
        when "committed_source"
          validate_identity(rails, PACKAGE, version)
          check(!rails.key?("base_commit") && !rails.key?("base_ref"), "Committed source cannot have snapshot provenance")
        else
          raise Invalid, "Unknown Rails provenance"
        end
        js = manifest["bundled_js"]
        validate_identity(js, JS_BASELINE["package"], JS_BASELINE["version"])
        check(js == JS_BASELINE, "Bundled JS must match the explicit frozen baseline")
        files = manifest["files_sha256"]
        check(files.is_a?(Hash) && files.keys.sort == runtime_files(root), "Missing or stale artifact inventory")
        check(%w[lib/handrail/bug_reporter.rb lib/handrail/bug_reporter/release.rb
          lib/handrail/bug_reporter/identity.rb lib/handrail/bug_reporter/version.rb
          lib/handrail/bug_reporter/release_manifest.rb config/routes.rb].all? { |path| files.key?(path) },
          "Missing required Ruby sources")
        verify_hashes!(root, files)
        inputs = manifest["source_sha256"]
        check(inputs.is_a?(Hash) && inputs.keys.sort == SOURCE_FILES.sort &&
          inputs.values.all? { |hash| hash.is_a?(String) && SHA256 =~ hash }, "Missing or malformed source inventory")
        if source
          verify_hashes!(root, inputs, mode)
          upstream = read_json(File.join(root, "frontend/upstream.json"))
          check(upstream.is_a?(Hash) && JS_BASELINE.all? { |key, value| upstream[key] == value }, "Upstream identity mismatch")
          dependency = "git+https://github.com/c0x65o/handrail-sdk-bug-reporter-js.git##{js['commit']}"
          package = read_json(File.join(root, "package.json"))
          lock = read_json(File.join(root, "package-lock.json"))
          check(package.fetch("dependencies").fetch(js["package"]) == dependency &&
            lock.fetch("packages").fetch("").fetch("dependencies").fetch(js["package"]) == dependency &&
            lock.fetch("packages").fetch("node_modules/#{js['package']}").fetch("resolved") == dependency,
            "JS dependency/lock commit mismatch")
        end
        manifest
      rescue KeyError, TypeError, NoMethodError => error
        raise Invalid, "Malformed release metadata: #{error.message}"
      end

      def verify_hashes!(root, expected, mode = nil)
        actual = hashes(root, expected.keys, mode)
        expected.each do |path, hash|
          check(hash.is_a?(String) && SHA256 =~ hash, "Invalid SHA-256: #{path}")
          check(actual[path] == hash, "Stale or tampered artifact: #{path}")
        end
      end
    end
  end
end
