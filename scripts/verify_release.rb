#!/usr/bin/env ruby
# Contributor-only Git operations. Gem loading and installation never load this file.
require "optparse"
require "open3"
require_relative "../lib/handrail/bug_reporter/version"
require_relative "../lib/handrail/bug_reporter/release_manifest"

module HandrailReleaseTool
  Contract = Handrail::BugReporter::ReleaseManifest
  module_function

  def git(root, *args)
    # Ignore inherited Git overrides; require the SDK's own repository root.
    env = {}
    ENV.keys.grep(/\AGIT_/).each { |key| env[key] = nil }
    out, err, status = Open3.capture3(env, "git", "-C", root, *args)
    Contract.check(status.success?, "Git verification failed: #{err.strip}")
    out
  end

  def repository!(root)
    Contract.check(File.realpath(git(root, "rev-parse", "--show-toplevel").strip) == File.realpath(root),
      "Git root must be the SDK checkout, not a consumer repository")
  end

  def verify_git!(root, manifest, tag = nil)
    repository!(root)
    rails = manifest.fetch("rails")
    if tag
      Contract.check(rails["provenance"] == "committed_source", "A release tag requires committed source")
      Contract.check(tag == "refs/tags/v#{rails['version']}", "Distribution tag/version mismatch")
      head = git(root, "rev-parse", "HEAD^{commit}").strip
      Contract.check(git(root, "rev-parse", "#{tag}^{commit}").strip == head, "Distribution tag must resolve to HEAD")
      Contract.check(git(root, "show", "HEAD:#{Contract::FILE}") == File.binread(File.join(root, Contract::FILE)),
        "Distribution tag must contain this manifest")
      git(root, "merge-base", "--is-ancestor", rails.fetch("commit"), head)
    end
    if rails["provenance"] == "source_snapshot"
      base = rails.fetch("base_commit")
      Contract.check(git(root, "rev-parse", "#{base}^{commit}").strip == base, "Snapshot base is not a commit")
      return
    end
    commit = rails.fetch("commit")
    Contract.check(git(root, "rev-parse", "#{commit}^{commit}").strip == commit, "Rails revision is not a commit")
    if rails.fetch("ref").start_with?("refs/tags/")
      Contract.check(git(root, "rev-parse", "#{rails['ref']}^{commit}").strip == commit, "Rails tag/commit mismatch")
    end
    # The manifest is a later attestation of source bytes, so exclude only it.
    # Every other staged, unstaged or untracked change disqualifies exact provenance.
    dirty = git(root, "status", "--porcelain", "--untracked-files=all", "--", ".", ":(exclude)#{Contract::FILE}")
    Contract.check(dirty.empty?, "Dirty source tree cannot claim committed_source provenance")
    source_files = git(root, "ls-tree", "-r", "--name-only", commit).lines.map(&:strip).select do |path|
      path =~ /\Alib\/.*\.rb\z/ || path =~ /\Aapp\/(?:controllers|helpers)\/.*\.rb\z/ ||
        path =~ /\Alib\/generators\/handrail\/bug_reporter\/templates\/[^\/]+\z/ ||
        [Contract::ASSET, "config/routes.rb"].include?(path)
    end
    Contract.check(source_files.sort == manifest.fetch("files_sha256").keys.sort, "Source revision artifact inventory differs")
    [[manifest.fetch("files_sha256"), nil],
      [manifest.fetch("source_sha256"), Contract.source_fingerprint_mode(manifest)]].each do |expected, mode|
      actual = Contract.hashes(root, expected.keys, mode) { |path| git(root, "show", "#{commit}:#{path}") }
      expected.each do |path, hash|
        Contract.check(actual[path] == hash, "Source revision differs: #{path}")
      end
    end
  end

  def run(argv)
    options = { :root => File.expand_path("..", File.dirname(__FILE__)), :source => true }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby scripts/verify_release.rb [--write-snapshot | --write-committed --commit SHA --ref REF] [--git] [--root DIR] [--package]"
      opts.on("--root DIR") { |value| options[:root] = File.expand_path(value) }
      opts.on("--package", "Verify installed package only, without contributor inputs") { options[:source] = false }
      opts.on("--git", "Also verify against this SDK checkout's Git objects/refs") { options[:git] = true }
      opts.on("--tag REF", "Verify an existing distribution tag at HEAD (implies --git)") { |value| options[:tag] = value; options[:git] = true }
      opts.on("--write-snapshot", "Record current bytes with null release identity") { options[:snapshot] = true }
      opts.on("--write-committed", "Attest bytes from an existing clean source revision") { options[:committed] = true }
      opts.on("--commit SHA") { |value| options[:commit] = value }
      opts.on("--ref REF") { |value| options[:ref] = value }
      opts.on("--source-fingerprint MODE", "Opt in when writing: #{Contract::SOURCE_FINGERPRINT}") { |value| options[:fingerprint] = value }
    end
    parser.parse!(argv)
    Contract.check(argv.empty?, "Unexpected arguments")
    root = options[:root]
    # Read the target version without evaluating arbitrary target source code.
    version_source = File.read(File.join(root, "lib/handrail/bug_reporter/version.rb"))
    version = version_source[/^\s*VERSION = "([^"]+)"\s*$/, 1]
    Contract.check(version, "Missing literal Rails VERSION")
    writing = options[:snapshot] || options[:committed]
    Contract.check(writing || !options[:fingerprint], "Source fingerprint option requires a manifest write")
    Contract.check(!(writing && options[:tag]), "Verify distribution tags after the manifest is committed")
    Contract.check(!(options[:snapshot] && options[:committed]), "Choose one provenance mode")
    Contract.check(options[:committed] || !(options[:commit] || options[:ref]), "Commit/ref require --write-committed")
    if writing
      Contract.check(options[:source], "Write requires contributor source inputs")
      repository!(root)
      rails = { "package" => Contract::PACKAGE, "version" => version }
      if options[:snapshot]
        base = git(root, "rev-parse", "HEAD^{commit}").strip
        rails.merge!("provenance" => "source_snapshot", "commit" => nil, "ref" => nil,
          "base_commit" => base, "base_ref" => "commit:#{base}")
      else
        rails.merge!("provenance" => "committed_source", "commit" => options[:commit], "ref" => options[:ref])
        Contract.validate_identity(rails, Contract::PACKAGE, version)
      end
      manifest = { "schema_version" => 1, "rails" => rails, "bundled_js" => Contract::JS_BASELINE,
        "files_sha256" => Contract.hashes(root, Contract.runtime_files(root)),
        "source_sha256" => Contract.hashes(root, Contract::SOURCE_FILES, options[:fingerprint]) }
      manifest["source_fingerprint"] = options[:fingerprint] if options[:fingerprint]
      Contract.verify!(root, version, true, manifest)
      verify_git!(root, manifest)
      File.write(File.join(root, Contract::FILE), JSON.pretty_generate(manifest) + "\n")
    else
      manifest = Contract.verify!(root, version, options[:source])
      verify_git!(root, manifest, options[:tag]) if options[:git]
    end
    puts JSON.pretty_generate({ "rails" => manifest["rails"], "bundled_js" => manifest["bundled_js"],
      "artifact" => Contract::ASSET, "sha256" => manifest["files_sha256"][Contract::ASSET],
      "runtime_files_verified" => manifest["files_sha256"].length,
      "verification" => options[:git] || writing ? "offline + SDK Git" : "offline checksums (Git provenance not authenticated)" })
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    HandrailReleaseTool.run(ARGV)
  rescue Handrail::BugReporter::ReleaseManifest::Invalid, OptionParser::ParseError, Errno::ENOENT => error
    warn "Release verification failed: #{error.message}"
    exit 1
  end
end
