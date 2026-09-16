# Reproduce validation 6444b0fe in an ordinary writable Linux x86_64 worker.
# Run with system Ruby 3.1.2, outside bundle exec. See docs/validation-environment.md.
require "json"
require "digest"
require "fileutils"
require "open3"
require "rbconfig"
require "time"
$stdout.sync = true

RAILS_SHA = "6fe35a72a689aebb3e5f627f1e56deda0a7f590e"
JS_SHA = "7dfb33f548448f864cf957f19d96f8b5a27bc787"
SOURCE = File.expand_path("../..", __dir__)
work = File.expand_path(ARGV.fetch(0) { abort "Usage: ruby #{$0} OUTSIDE_CHECKOUT_WORK_DIR target|existing|json" })
phase = ARGV.fetch(1)
abort "Unknown phase" unless %w[target existing json].include?(phase)
abort "Use system Ruby 3.1.2, outside Bundler" unless RUBY_VERSION == "3.1.2" && !defined?(Bundler)
FileUtils.mkdir_p(work)
work = File.realpath(work)
abort "Work directory must be outside the checkout, without whitespace" if work =~ /\s/ || work == SOURCE || work.start_with?(SOURCE + "/")
guard = File.open(File.join(work, "reproduce.lock"), "w")
abort "Work directory is in use" unless guard.flock(File::LOCK_EX | File::LOCK_NB)
logs = File.join(work, "receipts")
FileUtils.mkdir_p(logs)
abort "Phase already has receipts; use a fresh directory or retain and rename the old receipts" if File.exist?(File.join(logs, "#{phase}.json"))
receipts = []
base = ENV.to_h.reject { |key, _| key =~ /\ABUNDLE|\AGEM_|\ARUBY(?:OPT|LIB)\z|\AGIT_/ }
# env is supplied with unsetenv_others, so source-tree and user Bundler overrides
# cannot leak into the isolated closures. Keep the worker's ordinary tool PATH.
base["TMPDIR"] = File.join(work, "tmp")
FileUtils.mkdir_p(base["TMPDIR"])
ca = ENV.fetch("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")
abort "Trusted CA file unavailable: #{ca}" unless File.file?(ca) && File.size(ca) > 0
FileUtils.cp(ca, File.join(work, "ca-certificates.crt")) unless File.expand_path(ca) == File.join(work, "ca-certificates.crt")
%w[SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO BUNDLE_SSL_CA_CERT].each { |key| base[key] = File.join(work, "ca-certificates.crt") }
base["npm_config_cache"] = File.join(work, "npm-cache")

run = lambda do |label, env, cwd, *argv|
  path = File.join(logs, "#{phase}-#{label}.log")
  receipt = { "label" => label, "argv" => argv, "cwd" => cwd,
    "started_at" => Time.now.utc.iso8601, "log" => File.basename(path) }
  puts "+ #{phase}/#{label}: #{argv.join(' ')}"
  File.open(path, "w") do |file|
    file.sync = true
    Open3.popen2e(env, *argv, :chdir => cwd, :unsetenv_others => true) do |input, output, child|
      input.close
      output.each_line { |line| file.write(line) }
      status = child.value
      receipt["exit_code"] = status.exitstatus
      receipt["signal"] = status.termsig
    end
  end
  receipt["finished_at"] = Time.now.utc.iso8601
  receipt["sha256"] = Digest::SHA256.file(path).hexdigest
  receipt["minitest_totals"] = File.read(path).scan(/^(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors, (\d+) skips$/).map do |values|
    %w[runs assertions failures errors skips].zip(values.map(&:to_i)).to_h
  end
  receipts << receipt
  File.write(File.join(logs, "#{phase}.json"), JSON.pretty_generate(receipts) + "\n")
  puts "  exit #{receipt['exit_code'].inspect}; #{receipt['minitest_totals'].inspect}"
  receipt["exit_code"] == 0
end
must = lambda do |*args|
  abort "Preparation failed; see #{logs}" unless run.call(*args)
end
sdk = File.join(work, "handrail-sdk-bug-reporter-rails")
if phase == "target"
  [["rails", RAILS_SHA], ["js", JS_SHA]].each do |kind, sha|
    name = "handrail-sdk-bug-reporter-#{kind}"
    dest = File.join(work, name)
    abort "Clone destination exists: #{dest}" if File.exist?(dest)
    must.call("clone-#{kind}", base, work, "git", "clone", "--quiet", "https://github.com/c0x65o/#{name}.git", dest)
    must.call("checkout-#{kind}", base, dest, "git", "checkout", "--quiet", "--detach", sha)
    must.call("objects-#{kind}", base, dest, "git", "fsck", "--full", "--no-dangling")
    must.call("tree-#{kind}", base, dest, "git", "ls-tree", "-r", "HEAD")
  end
  must.call("clone-package-source", base, work, "git", "clone", "--quiet", "--bare", "--no-hardlinks", sdk, File.join(work, "clone-probe.git"))
  must.call("clone-package-objects", base, work, "git", "--git-dir=#{File.join(work, 'clone-probe.git')}", "fsck", "--full", "--no-dangling")
  must.call("prepare-ruby", base, sdk, RbConfig.ruby, "test/compatibility/prepare_ruby_3_4.rb", File.join(work, "runtime"))
end
abort "Run target preparation first" unless File.directory?(sdk)
target = base.merge("PATH" => File.join(work, "runtime/x64/bin") + ":" + base.fetch("PATH"),
  "BUNDLE_GEMFILE" => File.join(sdk, "gemfiles/rails_8_1.gemfile"),
  "BUNDLE_PATH" => File.join(work, "target-gems"), "BUNDLE_APP_CONFIG" => File.join(work, "target-config"),
  "BUNDLE_USER_HOME" => File.join(work, "target-bundler"), "BUNDLE_FORCE_RUBY_PLATFORM" => "true",
  "BUNDLE_FROZEN" => "true", "HANDRAIL_TEST_RAILS_DEFAULTS" => "8.1")
probe = 'require "rails"; require "rack"; require "json"; require "rbconfig"; require "openssl"; expected = ARGV; actual = [RUBY_VERSION, Bundler::VERSION, Rails.version, Rack.release, JSON::VERSION]; puts({versions: actual, ruby: RbConfig.ruby, gems: Gem.loaded_specs.transform_values { |s| s.full_gem_path }, ca: ENV["SSL_CERT_FILE"]}.inspect); abort actual.inspect unless actual == expected; OpenSSL::X509::Store.new.add_file(ENV.fetch("SSL_CERT_FILE"))'
lock_paths = %w[Gemfile.lock gemfiles/rails_8_1.gemfile.lock package-lock.json]
lock_hashes = lock_paths.to_h { |p| [p, Digest::SHA256.file(File.join(sdk, p)).hexdigest] }
File.write(File.join(logs, "#{phase}-inputs.json"), JSON.pretty_generate({"rails_sha" => RAILS_SHA, "js_sha" => JS_SHA,
  "driver_sha256" => Digest::SHA256.file(__FILE__).hexdigest, "ca_sha256" => Digest::SHA256.file(base.fetch("SSL_CERT_FILE")).hexdigest,
  "locks_sha256" => lock_hashes}) + "\n")

case phase
when "target"
  must.call("install", target, sdk, "bundle", "_2.6.9_", "install", "--jobs", "2", "--retry", "2")
  must.call("bundle-check", target, sdk, "bundle", "_2.6.9_", "check")
  must.call("runtime", target, sdk, "bundle", "_2.6.9_", "exec", "ruby", "-e", probe, "3.4.5", "2.6.9", "8.1.3", "3.2.6", "2.9.1")
  must.call("setup", target, sdk, "npm", "run", "setup")
  run.call("suite", target, sdk, "bundle", "_2.6.9_", "exec", "rake", "test")
  %w[request authorization history subscription accepted_response].each do |check|
    run.call("mounted-#{check}", target.merge("RAILS_ENV" => "test", "RACK_ENV" => "test"), sdk,
      "bundle", "_2.6.9_", "exec", "ruby", "-Ilib", "-Itest", "test/fixtures/mounted/#{check}_checks.rb")
  end
  run.call("release", target, sdk, "ruby", "scripts/verify_release.rb", "--git")
  run.call("smoke", target.merge("HANDRAIL_COMPAT_BUNDLE_PATH" => target.fetch("BUNDLE_PATH")), sdk,
    "ruby", "test/compatibility/run.rb", "rails_8_1")
when "existing"
  # The existing Ruby has libyaml runtime libraries but no development headers.
  url = "https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz"
  archive = File.join(work, "yaml-0.2.5.tar.gz")
  must.call("yaml-download", base, work, "curl", "-fsSL", url, "-o", archive)
  abort "libyaml checksum mismatch" unless Digest::SHA256.file(archive).hexdigest == "c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4"
  must.call("yaml-extract", base, work, "tar", "-xzf", archive)
  yaml = File.join(work, "yaml-0.2.5")
  must.call("yaml-configure", base, yaml, "./configure", "--prefix=#{File.join(work, 'libyaml')}")
  must.call("yaml-build", base, yaml, "make", "-j2")
  must.call("yaml-install", base, yaml, "make", "install")
  env = base.merge("BUNDLE_GEMFILE" => File.join(sdk, "Gemfile"), "BUNDLE_PATH" => File.join(work, "existing-gems"),
    "BUNDLE_APP_CONFIG" => File.join(work, "existing-config"), "BUNDLE_USER_HOME" => File.join(work, "existing-bundler"),
    "BUNDLE_BUILD__PSYCH" => "--with-libyaml-dir=#{File.join(work, 'libyaml')}", "BUNDLE_FROZEN" => "true")
  must.call("install", env, sdk, "bundle3.1", "_2.3.7_", "install", "--jobs", "2", "--retry", "2")
  must.call("bundle-check", env, sdk, "bundle3.1", "_2.3.7_", "check")
  must.call("runtime", env, sdk, "bundle3.1", "_2.3.7_", "exec", "ruby", "-e", 'require "rails"; require "rack"; puts [RUBY_DESCRIPTION, Bundler::VERSION, Rails.version, Rack.release, RbConfig.ruby]; abort unless [RUBY_VERSION, Bundler::VERSION, Rails.version, Rack.release] == %w[3.1.2 2.3.7 7.2.3.2 3.2.7]')
  run.call("suite", env, sdk, "bundle3.1", "_2.3.7_", "exec", "rake", "test")
  run.call("package", env, sdk, "bundle3.1", "_2.3.7_", "exec", "ruby", "-Ilib", "-Itest", "test/package_contract_test.rb")
when "json"
  variant = File.join(work, "json-2.21.1-sdk-only")
  must.call("clone", base, work, "git", "clone", "--quiet", "--no-hardlinks", sdk, variant)
  # Keep every other pin, the matrix structure, test code and production source.
  %w[test/compatibility/matrix.json gemfiles/rails_8_1.gemfile gemfiles/rails_8_1.gemfile.lock].each do |path|
    dest = File.join(variant, path)
    bytes = File.read(dest)
    count = bytes.scan(/2\.9\.1/).length
    abort "Unexpected JSON pin occurrences: #{path} #{count}" unless count == (path.end_with?(".lock") ? 2 : 1)
    File.write(dest, bytes.gsub("2.9.1", "2.21.1"))
  end
  target["BUNDLE_GEMFILE"] = File.join(variant, "gemfiles/rails_8_1.gemfile")
  must.call("install", target, variant, "bundle", "_2.6.9_", "install", "--jobs", "2", "--retry", "2")
  must.call("bundle-check", target, variant, "bundle", "_2.6.9_", "check")
  must.call("runtime", target, variant, "bundle", "_2.6.9_", "exec", "ruby", "-e", probe, "3.4.5", "2.6.9", "8.1.3", "3.2.6", "2.21.1")
  must.call("matrix", target, variant, "ruby", "test/compatibility/check_matrix.rb")
  run.call("smoke", target.merge("HANDRAIL_COMPAT_BUNDLE_PATH" => target.fetch("BUNDLE_PATH")), variant,
    "ruby", "test/compatibility/run.rb", "rails_8_1")
  FileUtils.cp(File.join(variant, "gemfiles/rails_8_1.gemfile.lock"), File.join(logs, "json-2.21.1.gemfile.lock"))
  must.call("variant-diff", base, variant, "git", "diff", "--", "Appraisals", "test/compatibility/matrix.json", "gemfiles/rails_8_1.gemfile", "gemfiles/rails_8_1.gemfile.lock")
end
lock_paths.each do |path|
  abort "Baseline lock changed: #{path}" unless Digest::SHA256.file(File.join(sdk, path)).hexdigest == lock_hashes.fetch(path)
end
abort "Checks failed; see #{logs}" unless receipts.all? { |r| r["exit_code"] == 0 }
puts "PASS #{phase}; receipts: #{logs}. This is SDK evidence, not independent or consumer acceptance."
