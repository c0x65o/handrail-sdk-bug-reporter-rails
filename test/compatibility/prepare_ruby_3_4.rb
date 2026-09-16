# Optional Linux x86_64 worker setup. Does not change a system Ruby or run tests.
# With a native Ruby 3.4.5 installation, just install Bundler 2.6.9 instead.
require "digest"
require "fileutils"
require "rbconfig"
require "tmpdir"

abort "Requires Linux x86_64" unless RUBY_PLATFORM =~ /x86_64-linux/
root = File.realpath(File.expand_path("../..", __dir__))
work = File.expand_path(ARGV.fetch(0) { File.join(Dir.tmpdir, "rails81-runtime") })
abort "Use a runtime path without whitespace" if work =~ /\s/
FileUtils.mkdir_p(work)
work = File.realpath(work)
abort "Runtime must be outside the checkout" if work == root || work.start_with?(root + "/")
guard = File.open(File.join(work, "prepare.lock"), "w")
abort "Runtime is already in use" unless guard.flock(File::LOCK_EX | File::LOCK_NB)
archive = File.join(work, "ruby.tar.gz")
url = "https://github.com/ruby/ruby-builder/releases/download/toolcache/ruby-3.4.5-ubuntu-22.04.tar.gz"
sha = "97246f1170eac708172707f18a87df57746c9bf4b2bc620f5c305f5c53e52154"
unless File.file?(archive)
  abort "Download failed" unless system("curl", "-fL", "--retry", "2", url, "-o", archive)
end
abort "Ruby archive checksum mismatch" unless Digest::SHA256.file(archive).hexdigest == sha
runtime = File.join(work, "x64")
unless File.directory?(runtime)
  abort "Extraction failed" unless system("tar", "-xzf", archive, "-C", work)
end
# ruby-builder's toolcache prefix is absolute. Keep the original binary and
# extensions intact, relocate standard-library discovery before Bundler runs,
# and retain Bundler's normal precedence over default gems. No SDK monkeypatches.
ruby = File.join(runtime, "bin/ruby")
FileUtils.mv(ruby, ruby + ".bin") unless File.file?(ruby + ".bin")
File.write(File.join(runtime, "relocate.rb"), <<-'CODE')
require "rbconfig"
stdlib = [RbConfig::CONFIG.fetch("rubylibdir"), RbConfig::CONFIG.fetch("rubyarchdir")]
ENV["RUBYLIB"] = ENV.fetch("RUBYLIB", "").split(File::PATH_SEPARATOR).reject { |p| stdlib.include?(p) }.join(File::PATH_SEPARATOR)
$LOAD_PATH.reject! { |p| stdlib.include?(p) }
$LOAD_PATH.concat(stdlib)
CODE
File.write(ruby, <<-'SH')
#!/bin/sh
runtime_root=$(CDPATH= cd -- "${0%/*}/.." && pwd)
export LD_LIBRARY_PATH="$runtime_root/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export RUBYLIB="$runtime_root/lib/ruby/3.4.0:$runtime_root/lib/ruby/3.4.0/x86_64-linux${RUBYLIB:+:$RUBYLIB}"
export RUBYOPT="-r$runtime_root/relocate.rb${RUBYOPT:+ $RUBYOPT}"
runtime_bundle_setup=${BUNDLER_SETUP:-}
unset BUNDLER_SETUP
if [ -n "$runtime_bundle_setup" ]; then
  exec "$runtime_root/bin/ruby.bin" -r"$runtime_root/relocate.rb" -r"$runtime_bundle_setup" "$@"
fi
exec "$runtime_root/bin/ruby.bin" -r"$runtime_root/relocate.rb" "$@"
SH
File.chmod(0755, ruby)
Dir[File.join(runtime, "bin/*")].each do |path|
  next unless File.file?(path)
  bytes = File.binread(path)
  next unless bytes.start_with?("#!/opt/hostedtoolcache/")
  File.binwrite(path, bytes.sub(/\A[^\n]+/, "#!/usr/bin/env ruby"))
end
env = { "PATH" => File.join(runtime, "bin") + ":" + ENV.fetch("PATH") }
ENV.keys.grep(/\ABUNDLE|\AGEM_|\ARUBY(?:OPT|LIB)\z/).each { |key| env[key] = nil }
abort "Bundler install failed" unless system(env, ruby, File.join(runtime, "bin/gem"), "install", "bundler", "-v", "2.6.9", "--no-document")
abort "Runtime probe failed" unless system(env, ruby, "-e", 'require "openssl"; require "yaml"; require "rbconfig"; abort RUBY_DESCRIPTION unless RUBY_VERSION == "3.4.5"; puts RUBY_DESCRIPTION; puts OpenSSL::OPENSSL_VERSION; puts RbConfig.ruby')
puts "SHA256 #{sha} #{archive}"
puts "Use PATH=#{runtime}/bin:$PATH; bundle _2.6.9_ --version"
