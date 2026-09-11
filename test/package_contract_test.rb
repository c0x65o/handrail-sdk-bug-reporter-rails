# Plain Ruby + local Git; no Bundler, Node, npm, downloads or registered Git writes.
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../lib/handrail/bug_reporter/release_manifest"
require_relative "../scripts/verify_release"

class PackageContractTest < Minitest::Test
  ROOT = File.expand_path("..", File.dirname(__FILE__))
  Contract = Handrail::BugReporter::ReleaseManifest
  TOOL = File.join(ROOT, "scripts/verify_release.rb")
  FIXTURE_VERSION = "1.2.3" # Rails and bundled JS versions must be independent.

  def command(*args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    env = {}
    ENV.keys.grep(/\ABUNDLE_|\ARUBY(?:OPT|LIB)\z|\AGIT_/).each { |key| env[key] = nil }
    env.merge!(options.delete(:env) || {})
    out, err, status = Open3.capture3(env, *args, options)
    assert status.success?, "#{args.inspect}: #{out}\n#{err}"
    out
  end

  def setup
    @work = Dir.mktmpdir("handrail-release-contract-")
    @source = File.join(@work, "source")
    FileUtils.mkdir_p(@source)
    paths = Contract.runtime_files(ROOT) + Contract::SOURCE_FILES + ["README.md", Contract::FILE, "scripts/verify_release.rb"]
    paths.uniq.each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(@source, path)))
      FileUtils.cp(File.join(ROOT, path), File.join(@source, path))
    end
    # A distinct valid gem version exercises Rails/JS independence.
    File.write(File.join(@source, "lib/handrail/bug_reporter/version.rb"),
      "module Handrail; module BugReporter\n  VERSION = \"#{FIXTURE_VERSION}\"\nend; end\n")
  end

  def teardown
    FileUtils.remove_entry(@work) if @work && File.directory?(@work)
  end

  def manifest
    Contract.read_json(File.join(@source, Contract::FILE))
  end

  def write_manifest(value)
    File.write(File.join(@source, Contract::FILE), JSON.pretty_generate(value) + "\n")
  end

  def snapshot(mode = nil)
    value = manifest
    value.delete("source_fingerprint")
    value["source_fingerprint"] = mode if mode
    value["rails"]["version"] = FIXTURE_VERSION
    value["files_sha256"] = Contract.hashes(@source, Contract.runtime_files(@source))
    value["source_sha256"] = Contract.hashes(@source, Contract::SOURCE_FILES, mode)
    write_manifest(value)
    value
  end

  def reject(message, source = false)
    error = assert_raises(Contract::Invalid) { Contract.verify!(@source, FIXTURE_VERSION, source) }
    assert_match message, error.message
  end

  # Git plumbing writes only a temporary bare clone and index. No git init,
  # commit, reset, checkout, branch switching or tag command touches the workspace.
  def fixture_git
    @bare = File.join(@work, "fixture.git")
    command("git", "clone", "--quiet", "--bare", "--no-hardlinks", ROOT, @bare)
    @git_env = {
      "GIT_DIR" => @bare, "GIT_INDEX_FILE" => File.join(@work, "fixture.index"),
      "GIT_AUTHOR_NAME" => "Package fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid",
      "GIT_COMMITTER_NAME" => "Package fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid",
      "GIT_AUTHOR_DATE" => "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2000-01-01T00:00:00Z"
    }
    # Deliberately omit the manifest from source A; source B attests A.
    @revision = fixture_commit(nil, false)
    command("git", "update-ref", "refs/heads/package-fixture", @revision, :env => @git_env)
    @checkout = File.join(@work, "checkout")
    command("git", "clone", "--quiet", "--branch", "package-fixture", @bare, @checkout)
  end

  def fixture_commit(parent, include_manifest)
    Dir.chdir(@source) do
      Dir["**/*"].sort.select { |path| File.file?(path) }.each do |path|
        next if path == Contract::FILE && !include_manifest
        object = command("git", "hash-object", "-w", "--stdin",
          :env => @git_env, :stdin_data => File.binread(path)).strip
        command("git", "update-index", "--add", "--cacheinfo", "100644", object, path, :env => @git_env)
      end
    end
    tree = command("git", "write-tree", :env => @git_env).strip
    args = ["git", "commit-tree", tree, "-m", "Isolated package fixture"]
    args += ["-p", parent] if parent
    command(*args, :env => @git_env).strip
  end

  def committed_fixture(mode = nil)
    snapshot
    fixture_git
    options = mode ? ["--source-fingerprint", mode] : []
    output = command(RbConfig.ruby, TOOL, "--root", @checkout, "--write-committed",
      "--commit", @revision, "--ref", "commit:#{@revision}", *options)
    assert_equal @revision, JSON.parse(output).fetch("rails").fetch("commit")
    FileUtils.cp(File.join(@checkout, Contract::FILE), File.join(@source, Contract::FILE))
    yield if block_given?
    distribute_fixture
  end

  def distribute_fixture
    distribution = fixture_commit(@revision, true)
    # Synthetic tag exists only in the disposable fixture, never the SDK checkout.
    @tag = "refs/tags/v#{FIXTURE_VERSION}"
    command("git", "update-ref", @tag, distribution, :env => @git_env)
    @distribution = File.join(@work, "distribution")
    command("git", "clone", "--quiet", "--branch", "v#{FIXTURE_VERSION}", @bare, @distribution)
    command(RbConfig.ruby, TOOL, "--root", @distribution, "--tag", @tag)
    distribution
  end

  def edit_contributor(path)
    absolute = File.join(@source, path)
    value = Contract.read_json(absolute)
    yield value
    File.write(absolute, JSON.pretty_generate(value) + "\n")
  end

  def contributor_version(version)
    edit_contributor("package.json") { |value| value["version"] = version }
    edit_contributor("package-lock.json") do |value|
      value["version"] = version
      value["packages"][""]["version"] = version
    end
  end

  def test_fingerprint_accepts_consistent_versions_and_canonical_json
    original = snapshot(Contract::SOURCE_FINGERPRINT)
    ["9.8.7", "10.0.0-rc.1+build.2"].each do |version|
      contributor_version(version)
      Contract::CONTRIBUTOR_FILES.each do |path|
        value = Contract.read_json(File.join(@source, path))
        # Reorder objects at every depth; array order remains significant.
        reverse = lambda do |entry|
          case entry
          when Hash then Hash[entry.to_a.reverse.map { |key, child| [key, reverse.call(child)] }]
          when Array then entry.map { |child| reverse.call(child) }
          else entry
          end
        end
        File.write(File.join(@source, path), JSON.generate(reverse.call(value)))
      end
      assert_equal original, Contract.verify!(@source, FIXTURE_VERSION, true)
    end
    assert_equal original["source_sha256"], Contract.hashes(@source, Contract::SOURCE_FILES, Contract::SOURCE_FINGERPRINT)
  end

  def test_fingerprint_rejects_malformed_or_mismatched_declarations
    snapshot(Contract::SOURCE_FINGERPRINT)
    originals = Hash[Contract::CONTRIBUTOR_FILES.map { |path| [path, File.binread(File.join(@source, path))] }]
    changes = [
      ["package.json", lambda { |value| value.delete("private") }],
      ["package.json", lambda { |value| value["private"] = false }],
      ["package.json", lambda { |value| value["private"] = "true" }],
      ["package-lock.json", lambda { |value| value["packages"] = [] }],
      ["package-lock.json", lambda { |value| value["packages"].delete("") }]
    ]
    [nil, 123, "", "01.2.3", "1.2", "1.2.3\n", "1.2.3-01", "1.2.3+", "9.9.9"].each do |version|
      changes << ["package.json", lambda { |value| value["version"] = version }]
      changes << ["package-lock.json", lambda { |value| value["version"] = version }]
      changes << ["package-lock.json", lambda { |value| value["packages"][""]["version"] = version }]
    end
    changes.each do |path, change|
      originals.each { |name, bytes| File.binwrite(File.join(@source, name), bytes) }
      edit_contributor(path, &change)
      reject(/Contributor|contributor/, true)
      assert_raises(Contract::Invalid) { Contract.hashes(@source, Contract::SOURCE_FILES, Contract::SOURCE_FINGERPRINT) }
    end
    Contract::CONTRIBUTOR_FILES.each do |path|
      ["{", "[]", "null", originals[path].sub('{', '{"version":"malformed",')].each do |bytes|
        originals.each { |name, content| File.binwrite(File.join(@source, name), content) }
        File.write(File.join(@source, path), bytes)
        reject(/Contributor|contributor/, true)
      end
    end
  end

  def test_fingerprint_keeps_other_values_and_runtime_bytes_covered
    original = snapshot(Contract::SOURCE_FINGERPRINT)
    changes = [
      ["package.json", lambda { |value| value["dependencies"]["react"] = "19.0.0" }],
      ["package.json", lambda { |value| value["scripts"]["build"] = "echo changed" }],
      ["package.json", lambda { |value| value["extra"] = [1, 2] }],
      ["package.json", lambda { |value| value["nested"] = { "version" => "9.9.9" } }],
      ["package-lock.json", lambda { |value| value["packages"][""]["dependencies"]["react"] = "19.0.0" }],
      ["package-lock.json", lambda { |value| value["packages"]["node_modules/react"]["version"] = "19.0.0" }],
      ["package-lock.json", lambda { |value| value["packages"]["node_modules/@handrail/bug-reporter"]["resolved"] = "git+https://example.invalid/sdk.git##{'a' * 40}" }],
      ["package-lock.json", lambda { |value| value["packages"]["node_modules/react"]["integrity"] = "sha512-changed" }]
    ]
    changes.each do |path, change|
      bytes = File.binread(File.join(@source, path))
      edit_contributor(path, &change)
      reject(/tampered artifact/, true)
      File.binwrite(File.join(@source, path), bytes)
    end
    [Contract::ASSET, "lib/handrail/bug_reporter/identity.rb", "frontend/rails_adapter.js"].each do |path|
      bytes = File.binread(File.join(@source, path))
      File.binwrite(File.join(@source, path), bytes + "\n")
      reject(/tampered artifact/, true)
      File.binwrite(File.join(@source, path), bytes)
    end
    assert_equal original, Contract.verify!(@source, FIXTURE_VERSION, true)
  end

  def test_fingerprint_package_only_does_not_require_contributor_files
    snapshot(Contract::SOURCE_FINGERPRINT)
    Contract::SOURCE_FILES.each { |path| FileUtils.rm(File.join(@source, path)) }
    assert_equal Contract::SOURCE_FINGERPRINT, Contract.verify!(@source, FIXTURE_VERSION)["source_fingerprint"]
    command(RbConfig.ruby, TOOL, "--root", @source, "--package")
    reject(/Missing or unsafe artifact/, true)
  end

  def test_fingerprint_mode_requires_explicit_supported_opt_in
    original = snapshot
    [nil, false, {}, "unknown"].each do |mode|
      value = original.merge("source_fingerprint" => mode)
      write_manifest(value)
      reject(/Unsupported source fingerprint mode/)
    end
    assert_raises(Contract::Invalid) do
      HandrailReleaseTool.run(["--root", @source, "--source-fingerprint", Contract::SOURCE_FINGERPRINT])
    end
  end

  def test_legacy_fingerprint_rejects_version_and_formatting_changes
    original = snapshot
    refute original.key?("source_fingerprint")
    contributor_version("9.8.7")
    reject(/tampered artifact/, true)
    snapshot
    File.open(File.join(@source, "package.json"), "a") { |file| file.puts }
    reject(/tampered artifact/, true)
  end

  def test_fingerprint_snapshot_writer_requires_explicit_mode
    fixture_git
    command(RbConfig.ruby, TOOL, "--root", @checkout, "--write-snapshot",
      "--source-fingerprint", Contract::SOURCE_FINGERPRINT)
    value = Contract.read_json(File.join(@checkout, Contract::FILE))
    assert_equal Contract::SOURCE_FINGERPRINT, value["source_fingerprint"]
    assert_equal Contract.hashes(@checkout, Contract::SOURCE_FILES, Contract::SOURCE_FINGERPRINT), value["source_sha256"]
    command(RbConfig.ruby, TOOL, "--root", @checkout, "--write-snapshot")
    value = Contract.read_json(File.join(@checkout, Contract::FILE))
    refute value.key?("source_fingerprint")
    assert_equal Contract.hashes(@checkout, Contract::SOURCE_FILES), value["source_sha256"]
  end

  def test_fingerprint_git_accepts_committed_version_bump_and_checks_tampering
    committed_fixture(Contract::SOURCE_FINGERPRINT) { contributor_version("9.8.7") }
    value = Contract.verify!(@distribution, FIXTURE_VERSION, true)
    assert_equal "committed_source", value["rails"]["provenance"]
    assert_equal @revision, value["rails"]["commit"]
    # Source A and clean distribution B have distinct private versions.
    refute_equal command("git", "-C", @distribution, "show", "#{@revision}:package.json"),
      File.binread(File.join(@distribution, "package.json"))
    ["source_sha256", "files_sha256"].each do |inventory|
      bad = Marshal.load(Marshal.dump(value))
      path = inventory == "source_sha256" ? "package-lock.json" : Contract::ASSET
      bad[inventory][path] = "a" * 64
      error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, bad) }
      assert_match(/Source revision differs/, error.message)
    end
    File.open(File.join(@distribution, "package.json"), "a") { |file| file.puts }
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, value) }
    assert_match(/Dirty source tree/, error.message)
  end

  def test_fingerprint_git_validates_selected_revision_declarations
    # A has invalid excluded metadata; B repairs it. Valid local declarations
    # must never excuse the invalid declarations in the attested source A.
    edit_contributor("package-lock.json") { |value| value["version"] = "9.9.9" }
    fixture_git
    contributor_version("1.0.0")
    value = snapshot(Contract::SOURCE_FINGERPRINT)
    value["rails"] = { "package" => Contract::PACKAGE, "version" => FIXTURE_VERSION,
      "provenance" => "committed_source", "commit" => @revision, "ref" => "commit:#{@revision}" }
    write_manifest(value)
    distribution = fixture_commit(@revision, true)
    command("git", "update-ref", "refs/heads/valid-local", distribution, :env => @git_env)
    local = File.join(@work, "valid-local")
    command("git", "clone", "--quiet", "--branch", "valid-local", @bare, local)
    assert_equal value, Contract.verify!(local, FIXTURE_VERSION, true)
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(local, value) }
    assert_match(/Contributor version declarations mismatch/, error.message)
  end

  def test_tag_archive_build_install_identity_and_integrity_without_tools_or_git
    distribution = committed_fixture
    tar = command("git", "--git-dir", @bare, "archive", @tag)
    archive = File.join(@work, "archive")
    FileUtils.mkdir_p(archive)
    command("tar", "-xf", "-", "-C", archive, :stdin_data => tar)
    refute File.exist?(File.join(archive, ".git"))
    refute File.exist?(File.join(archive, "node_modules"))
    # Host is a real, different Git repo; hostile env/cwd cannot stamp SDK identity.
    host = File.join(@work, "host")
    command("git", "clone", "--quiet", "--no-hardlinks", ROOT, host)
    empty_path = File.join(@work, "no-executables")
    FileUtils.mkdir_p(empty_path)
    source = <<-'CODE'
      require "rubygems/package"
      require "rubygems/installer"
      require "json"
      root, work = ARGV
      spec = Gem::Specification.load(File.join(root, "handrail-bug-reporter.gemspec"))
      raise "Invalid spec" unless spec
      raise "Install hooks" unless spec.extensions.empty?
      raise "License changed" unless spec.licenses.empty?
      raise "Contributor files packaged" if spec.files.any? { |p| p =~ /\A(?:frontend|scripts|node_modules)\// }
      archive = File.join(work, "reporter.gem")
      Dir.chdir(root) { Gem::Package.build(spec, false, false, archive) }
      package = Gem::Package.new(archive)
      raise "Missing manifest" unless package.contents.include?("release-manifest.json")
      installed = Gem::Installer.at(archive, :install_dir => File.join(work, "gems"),
        :ignore_dependencies => true, :wrappers => false).install
      $LOAD_PATH.unshift(File.join(installed.full_gem_path, "lib"))
      require "handrail/bug_reporter/identity"
      contract = Handrail::BugReporter::ReleaseManifest
      manifest = contract.verify!(installed.full_gem_path, "1.2.3")
      raise "Extra or missing gem files" unless (manifest.fetch("files_sha256").keys - package.contents).empty?
      raise "Git or node_modules installed" if %w[.git node_modules].any? { |p| File.exist?(File.join(installed.full_gem_path, p)) }
      puts JSON.generate("identity" => Handrail::BugReporter::Identity::SDK_IDENTITY,
        "bundled_js" => Handrail::BugReporter::Release::BUNDLED_JS,
        "asset_sha256" => manifest.fetch("files_sha256").fetch(contract::ASSET))
    CODE
    output = command(RbConfig.ruby, "-r", File.join(ROOT, "test/support/no_network.rb"), "-e", source, archive, @work,
      :chdir => host, :env => { "PATH" => empty_path, "GIT_DIR" => File.join(host, ".git"),
        "HANDRAIL_BUG_REPORTER_SDK_COMMIT" => "f" * 40, "HANDRAIL_BUG_REPORTER_SDK_REF" => "refs/heads/main" })
    result = JSON.parse(output.lines.last)
    assert_equal @revision, result["identity"]["reporter_sdk_commit"]
    assert_equal "commit:#{@revision}", result["identity"]["reporter_sdk_ref"]
    assert_equal FIXTURE_VERSION, result["identity"]["reporter_sdk_version"]
    assert_equal Contract::JS_BASELINE, result["bundled_js"]
    assert_equal manifest["files_sha256"][Contract::ASSET], result["asset_sha256"]
    puts "PACKAGE EVIDENCE: source=#{@revision} distribution=#{distribution} tag=#{@tag} #{JSON.generate(result)}"
  end

  def test_snapshot_has_honest_unknown_release_identity
    snapshot
    assert_nil Contract.verify!(@source, FIXTURE_VERSION, true)["rails"]["commit"]
    value = manifest
    value["rails"]["commit"] = "a" * 40
    write_manifest(value)
    reject(/snapshot cannot claim/)
  end

  def test_runtime_and_gemspec_fail_closed_for_tampered_package
    snapshot
    File.open(File.join(@source, Contract::ASSET), "a") { |file| file.puts "// tampered" }
    code = <<-'CODE'
      begin
        require "handrail/bug_reporter/identity"
        abort "Tampered runtime loaded"
      rescue Handrail::BugReporter::ReleaseManifest::Invalid => error
        raise unless error.message.include?("tampered artifact")
      end
      spec = Gem::Specification.load(File.join(ARGV.fetch(0), "handrail-bug-reporter.gemspec"))
      raise "Tampered gemspec accepted" if spec
      puts "Rejected runtime and gemspec"
    CODE
    output = command(RbConfig.ruby, "-I", File.join(@source, "lib"), "-e", code, @source)
    assert_equal "Rejected runtime and gemspec\n", output
  end

  def test_missing_malformed_and_stale_manifest
    snapshot
    path = File.join(@source, Contract::FILE)
    FileUtils.rm(path)
    reject(/Missing or malformed/)
    File.write(path, "{")
    reject(/Missing or malformed/)
    File.write(path, "[]")
    reject(/schema/)
  end

  def test_stale_rails_version
    value = snapshot
    value["rails"]["version"] = "9.9.9"
    write_manifest(value)
    reject(/version is stale/)
  end

  def test_version_ref_and_commit_ref_mismatches
    value = snapshot
    value["rails"] = { "package" => Contract::PACKAGE, "version" => FIXTURE_VERSION,
      "provenance" => "committed_source", "commit" => "a" * 40 }
    ["refs/tags/v9.9.9", "refs/heads/main", "commit:#{'b' * 40}", nil].each do |ref|
      value["rails"]["ref"] = ref
      write_manifest(value)
      reject(/ref mismatch/)
    end
    ["abc123", "g" * 40, "a" * 41, "a" * 40 + "\n", nil].each do |commit|
      value["rails"]["commit"] = commit
      write_manifest(value)
      reject(/Invalid full commit/)
    end
  end

  def test_invalid_and_inconsistent_js_identity
    original = snapshot
    { "commit" => "a" * 40, "version" => "0.4.48", "ref" => "refs/tags/v0.4.48" }.each do |key, value|
      changed = Marshal.load(Marshal.dump(original))
      changed["bundled_js"][key] = value
      write_manifest(changed)
      reject(/baseline|mismatch/)
    end
  end

  def test_missing_and_tampered_asset_and_stale_ruby
    snapshot
    path = File.join(@source, Contract::ASSET)
    bytes = File.binread(path)
    FileUtils.rm(path)
    reject(/Missing or unsafe artifact/)
    File.binwrite(path, bytes + "\n// tampered")
    reject(/tampered artifact/)
    File.binwrite(path, bytes)
    File.open(File.join(@source, "lib/handrail/bug_reporter/identity.rb"), "a") { |f| f.puts "# changed" }
    reject(/tampered artifact/)
  end

  def test_missing_or_forged_hash_inventory
    value = snapshot
    value["files_sha256"].delete(Contract::ASSET)
    write_manifest(value)
    reject(/artifact inventory/)
    value = snapshot
    value["files_sha256"][Contract::ASSET] = "xyz"
    write_manifest(value)
    reject(/Invalid SHA/)
  end

  def test_stale_frontend_inputs_and_inconsistent_dependency_lock
    snapshot
    path = File.join(@source, "frontend/rails_adapter.js")
    File.open(path, "a") { |f| f.puts "// changed" }
    reject(/tampered artifact/, true)
    snapshot
    path = File.join(@source, "package-lock.json")
    lock = JSON.parse(File.read(path))
    lock["packages"]["node_modules/@handrail/bug-reporter"]["resolved"] = "git+https://example.invalid/sdk.git##{'a' * 40}"
    File.write(path, JSON.generate(lock))
    snapshot # Even refreshed hashes cannot excuse an inconsistent lock.
    reject(/dependency\/lock commit mismatch/, true)
  end

  def test_git_rejects_dirty_stamp_and_mismatched_source_or_tag
    committed_fixture
    value = Contract.read_json(File.join(@distribution, Contract::FILE))
    bad = Marshal.load(Marshal.dump(value))
    bad["rails"]["ref"] = @tag # Distribution commit differs from source commit.
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, bad) }
    assert_match(/tag\/commit mismatch/, error.message)
    bad["rails"]["commit"] = "f" * 40
    bad["rails"]["ref"] = "commit:#{'f' * 40}"
    assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, bad) }
    bad = Marshal.load(Marshal.dump(value))
    bad["files_sha256"].delete("lib/handrail/bug_reporter/client.rb")
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, bad) }
    assert_match(/artifact inventory differs/, error.message)
    bad = Marshal.load(Marshal.dump(value))
    bad["files_sha256"][Contract::ASSET] = "a" * 64
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, bad) }
    assert_match(/Source revision differs/, error.message)
    assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, value, "refs/tags/v9.9.9") }
    File.write(File.join(@distribution, "untracked.txt"), "dirty")
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(@distribution, value) }
    assert_match(/Dirty source tree/, error.message)
    before = File.binread(File.join(@distribution, Contract::FILE))
    assert_raises(Contract::Invalid) do
      HandrailReleaseTool.run(["--root", @distribution, "--write-committed", "--commit", @revision, "--ref", "commit:#{@revision}"])
    end
    assert_equal before, File.binread(File.join(@distribution, Contract::FILE))
  end

  def test_archive_cannot_borrow_consumer_git_for_verification
    snapshot
    fixture_git
    nested = File.join(@checkout, "vendor/sdk")
    FileUtils.mkdir_p(File.dirname(nested))
    FileUtils.cp_r(@source, nested)
    error = assert_raises(Contract::Invalid) { HandrailReleaseTool.verify_git!(nested, manifest) }
    assert_match(/not a consumer repository/, error.message)
  end
end
