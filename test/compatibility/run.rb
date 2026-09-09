# Run with plain Ruby, outside bundle exec. All writes go to a temporary fixture.
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "digest"
require "rbconfig"

root = File.expand_path("../..", File.dirname(__FILE__))
matrix = JSON.parse(File.read(File.join(root, "test/compatibility/matrix.json")))
name = ARGV.fetch(0) { abort "Usage: ruby test/compatibility/run.rb #{matrix.keys.join('|')}" }
cell = matrix.fetch(name)
abort "UNAVAILABLE #{name}: requires Ruby #{cell.fetch('ruby')}; current #{RUBY_VERSION}" unless RUBY_VERSION == cell.fetch("ruby")
begin
  bundle = Gem.bin_path("bundler", "bundle", cell.fetch("bundler"))
rescue Gem::GemNotFoundException
  abort "UNAVAILABLE #{name}: install Bundler #{cell.fetch('bundler')} with gem install bundler -v #{cell.fetch('bundler')} --no-document"
end

def capture(env, *args)
  output, error, status = Open3.capture3(env, *args)
  raise "#{args.first} failed: #{error}\n#{output}" unless status.success?
  output.strip
end

def run(env, *args)
  puts "+ #{args.join(' ')}"
  raise "Command failed: #{args.inspect}" unless system(env, *args)
end

run({}, RbConfig.ruby, File.join(root, "test/compatibility/check_matrix.rb"))
work = Dir.mktmpdir("handrail-#{name}-")
puts "EVIDENCE: #{work} (retained for inspection; safe to remove after review)"
# Eliminate inherited source-tree overrides and Bundler local/Git settings.
env = {}
ENV.keys.grep(/\ABUNDLE_|\ARUBY(?:OPT|LIB)\z|\AGIT_/).each { |key| env[key] = nil }
repository = File.join(work, "sdk.git")
run(env, "git", "clone", "--quiet", "--bare", "--no-hardlinks", root, repository)
git_env = env.merge("GIT_DIR" => repository, "GIT_INDEX_FILE" => File.join(work, "snapshot.index"),
  "GIT_AUTHOR_NAME" => "Compatibility fixture", "GIT_AUTHOR_EMAIL" => "fixture@example.invalid",
  "GIT_COMMITTER_NAME" => "Compatibility fixture", "GIT_COMMITTER_EMAIL" => "fixture@example.invalid",
  "GIT_AUTHOR_DATE" => "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2000-01-01T00:00:00Z")
spec = Gem::Specification.load(File.join(root, "handrail-bug-reporter.gemspec"))
raise "Cannot load gemspec" unless spec
snapshot = {}
# Read current package bytes, not HEAD. This includes untracked generator files.
# Git plumbing writes only the cloned object database and temporary index.
(spec.files + ["handrail-bug-reporter.gemspec"]).uniq.sort.each do |path|
  raise "Unsafe package path: #{path}" if path.start_with?("/") || path.split("/").include?("..") || path =~ /[\t\n]/
  source = File.join(root, path)
  raise "Expected regular package file: #{path}" unless File.file?(source) && !File.symlink?(source)
  bytes = File.binread(source)
  snapshot[path] = Digest::SHA256.hexdigest(bytes)
  object, error, status = Open3.capture3(git_env, "git", "hash-object", "-w", "--stdin", :stdin_data => bytes)
  raise error unless status.success?
  capture(git_env, "git", "update-index", "--add", "--cacheinfo", "100644", object.strip, path)
end
tree = capture(git_env, "git", "write-tree")
revision = capture(git_env, "git", "commit-tree", tree, "-m", "Current package compatibility fixture")
capture(git_env, "git", "update-ref", "refs/heads/compatibility-fixture", revision)
snapshot_file = File.join(work, "snapshot.json")
File.write(snapshot_file, JSON.pretty_generate(snapshot) + "\n")
puts "SNAPSHOT: #{revision}; #{snapshot.length} current package files"

host = File.join(work, "host")
FileUtils.cp_r(File.join(root, "test/dummy"), host)
FileUtils.mkdir_p(File.join(host, "checks"))
%w[smoke.rb verify_lock.rb matrix.json].each do |file|
  FileUtils.cp(File.join(root, "test/compatibility", file), File.join(host, "checks", file))
end
FileUtils.cp(File.join(root, "test/support/no_network.rb"), File.join(host, "checks/no_network.rb"))
gemfile = File.read(File.join(root, "gemfiles", name + ".gemfile"))
gemspec_line = /^gemspec (?:path: |:path => )"\.\.\/"$/
raise "Expected one appraisal gemspec declaration" unless gemfile.scan(gemspec_line).length == 1
gemfile = gemfile.sub(gemspec_line,
  "gem \"handrail-bug-reporter\", :git => #{repository.dump}, :ref => #{revision.dump}, :require => false")
File.write(File.join(host, "Gemfile"), gemfile)
FileUtils.mkdir_p(File.join(work, "no-executables"))
env.merge!("BUNDLE_GEMFILE" => File.join(host, "Gemfile"),
  "BUNDLE_PATH" => File.expand_path(ENV.fetch("HANDRAIL_COMPAT_BUNDLE_PATH", File.join(work, "bundle"))),
  "BUNDLE_APP_CONFIG" => File.join(work, "bundle-config"), "BUNDLE_USER_HOME" => File.join(work, "bundler-home"),
  "BUNDLE_FORCE_RUBY_PLATFORM" => "true", "BUNDLE_DISABLE_SHARED_GEMS" => "true",
  "HANDRAIL_COMPAT_MATRIX" => File.join(host, "checks/matrix.json"), "HANDRAIL_COMPAT_CELL" => name,
  "HANDRAIL_COMPAT_REVISION" => revision, "HANDRAIL_COMPAT_SOURCE" => File.realpath(root),
  "HANDRAIL_COMPAT_SNAPSHOT" => snapshot_file, "RAILS_ENV" => "test", "RACK_ENV" => "test")
# Allow explicit native build flags, while keeping every other Bundler setting isolated.
ENV.keys.grep(/\ABUNDLE_BUILD__/).each { |key| env[key] = ENV[key] }
Dir.chdir(host) do
  run(env, RbConfig.ruby, bundle, "lock")
  run(env, RbConfig.ruby, "-e", 'gem "bundler", ARGV.shift; load ARGV.shift', cell.fetch("bundler"), "checks/verify_lock.rb")
  env["BUNDLE_FROZEN"] = "true"
  run(env, RbConfig.ruby, bundle, "install", "--jobs", "2", "--retry", "2")
  # Empty PATH makes Node unavailable in both actual precompile and requests.
  env["PATH"] = File.join(work, "no-executables")
  env["RUBYOPT"] = "-r#{File.join(host, 'checks/no_network.rb')}"
  run(env, RbConfig.ruby, bundle, "exec", RbConfig.ruby, "-e",
    'load Gem.bin_path("rake", "rake")', "--", "assets:precompile", "--trace")
  run(env, RbConfig.ruby, bundle, "exec", RbConfig.ruby, "checks/smoke.rb")
end
