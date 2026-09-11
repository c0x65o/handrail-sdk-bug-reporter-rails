# Run with the host Ruby, outside bundle exec. No daemon, root, or runtime manager.
require "json"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"

module IsolatedCompatibility
  def self.run(name)
    root = File.expand_path("../..", File.dirname(__FILE__))
    pins = {
      "rails_4_2" => ["2.3.8", "4.2.11.3", "b5016d61440e939045d4e22979e04708ed6c8e1c52e7edb2553cf40b73c59abf", "2.3.26"],
      "rails_5_2" => ["2.5.9", "5.2.8.1", "f5894e05f532b748c3347894a5efa42066fd11cc8d261d4d9788ff71da00be68", "2.3.26"],
      "rails_6_1" => ["2.7.8", "6.1.7.10", "c2dab63cbc8f2a05526108ad419efa63a67ed4074dbbcf9fc2b1ca664cb45ba0", "2.4.22"]
    }
    ruby_version, rails_version, ruby_sha, bundler_version = pins.fetch(name)
    bundler_sha = {
      "2.3.26" => "1ee53cdf61e728ad82c6dbff06cfcd8551d5422e88e86203f0e2dbe9ae999e09",
      "2.4.22" => "747ba50b0e67df25cbd3b48f95831a77a4d53a581d55f063972fcb146d142c5f"
    }.fetch(bundler_version)
    cell = JSON.parse(File.read(File.join(root, "test/compatibility/matrix.json"))).fetch(name)
    abort "Bootstrap pins must match #{name}" unless cell.values_at("ruby", "rails", "bundler") == [ruby_version, rails_version, bundler_version]
    File.umask(0077)
    work = File.expand_path(ENV.fetch("HANDRAIL_COMPAT_RUNTIME", File.join(Dir.tmpdir, "handrail-#{name}-#{Digest::SHA256.hexdigest(root)[0, 12]}")))
    abort "Use a runtime directory without whitespace" if work =~ /\s/
    FileUtils.mkdir_p(work)
    work = File.realpath(work)
    abort "Runtime directory must be outside the SDK checkout" if work == File.realpath(root) || work.start_with?(File.realpath(root) + "/")
    # Prevent simultaneous builds or smoke runs from sharing mutable build outputs.
    guard = File.open(File.join(work, "bootstrap.lock"), "w")
    abort "Runtime directory is already in use: #{work}" unless guard.flock(File::LOCK_EX | File::LOCK_NB)
    jobs = Integer(ENV.fetch("HANDRAIL_COMPAT_JOBS", "2"))
    abort "HANDRAIL_COMPAT_JOBS must be 1 or 2" unless (1..2).include?(jobs)
    sources = {
      "ruby-#{ruby_version}.tar.gz" => ["https://cache.ruby-lang.org/pub/ruby/#{ruby_version.split('.')[0, 2].join('.')}/ruby-#{ruby_version}.tar.gz", ruby_sha],
      "openssl-1.0.2u.tar.gz" => ["https://www.openssl.org/source/old/1.0.2/openssl-1.0.2u.tar.gz", "ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16"],
      "yaml-0.2.5.tar.gz" => ["https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz", "c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4"],
      "bundler-#{bundler_version}.gem" => ["https://rubygems.org/downloads/bundler-#{bundler_version}.gem", bundler_sha]
    }
    prefix = File.join(work, "runtime")
    %w[downloads build tmp gems].each { |dir| FileUtils.mkdir_p(File.join(work, dir)) }
    env = {}
    ENV.keys.grep(/\ABUNDLE_|\AGEM_|\ARUBY|\AGIT_|\A(?:CFLAGS|CPPFLAGS|LDFLAGS|LD_LIBRARY_PATH|CONFIGURE_OPTS|MAKEFLAGS)\z/).each { |key| env[key] = nil }
    env.merge!("GEM_HOME" => File.join(work, "gems"), "GEM_PATH" => File.join(work, "gems"),
      "TMPDIR" => File.join(work, "tmp"), "PATH" => "#{prefix}/bin:/usr/bin:/bin",
      "SSL_CERT_FILE" => ENV.fetch("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt"))
    abort "Missing CA file: #{env['SSL_CERT_FILE']}" unless File.file?(env["SSL_CERT_FILE"])
    log = File.open(File.join(work, "bootstrap.log"), "a")
    log.sync = true
    execute = lambda do |*command|
      puts "+ #{command.join(' ')} (log: #{log.path})"
      log.puts "+ #{command.join(' ')}"
      raise "Failed: #{command.first}; see #{log.path}" unless system(env, *command, :out => log, :err => log)
    end
    sources.each do |file, (url, sha)|
      target = File.join(work, "downloads", file)
      execute.call("curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", url, "--output", target) unless File.file?(target)
      abort "SHA256 mismatch: #{target}" unless Digest::SHA256.file(target).hexdigest == sha
    end
    File.write(File.join(work, "sources.json"), JSON.pretty_generate(sources) + "\n")
    # Reuse only a completely built runtime produced by this exact bootstrap.
    stamp = File.join(work, "runtime.sha256")
    identity = Digest::SHA256.hexdigest(File.binread(__FILE__) + name)
    unless File.file?(stamp) && File.read(stamp).strip == identity
      # A changed recipe or interrupted build must not reuse stale object files.
      FileUtils.rm_rf(File.join(work, "build"))
      FileUtils.rm_rf(prefix)
      FileUtils.mkdir_p(File.join(work, "build"))
      sources.keys.grep(/tar.gz\z/).each do |file|
        execute.call("tar", "xzf", File.join(work, "downloads", file), "-C", File.join(work, "build"))
      end
      Dir.chdir(File.join(work, "build/openssl-1.0.2u")) do
        execute.call("./config", "--prefix=#{prefix}", "--openssldir=#{prefix}/ssl", "no-shared", "-fPIC")
        execute.call("make", "-j#{jobs}")
        execute.call("make", "install_sw")
      end
      Dir.chdir(File.join(work, "build/yaml-0.2.5")) do
        execute.call("./configure", "--prefix=#{prefix}", "--disable-shared", "--with-pic")
        execute.call("make", "-j#{jobs}")
        execute.call("make", "install")
      end
      Dir.chdir(File.join(work, "build/ruby-#{ruby_version}")) do
        execute.call("./configure", "--prefix=#{prefix}", "--disable-install-doc",
          "--with-openssl-dir=#{prefix}", "--with-libyaml-dir=#{prefix}",
          "--without-gmp", "--with-out-ext=readline,dbm,gdbm", "CFLAGS=-O2 -fcommon")
        execute.call("make", "-j#{jobs}")
        execute.call("make", "install")
      end
      execute.call(File.join(prefix, "bin/ruby"), "-ropenssl", "-rpsych", "-rzlib", "-e",
        'abort RUBY_VERSION unless RUBY_VERSION == ARGV.fetch(0); puts [RUBY_DESCRIPTION, OpenSSL::OPENSSL_VERSION, Psych::LIBYAML_VERSION, Zlib::ZLIB_VERSION]', ruby_version)
      File.write(stamp, identity + "\n")
    end
    execute.call(File.join(prefix, "bin/gem"), "install", "--norc", "--local", File.join(work, "downloads/bundler-#{bundler_version}.gem"), "--no-document")
    env["HANDRAIL_COMPAT_BUNDLE_PATH"] = File.join(work, "bundle")
    puts "Running #{name}; complete output: #{work}/acceptance.log"
    File.open(File.join(work, "acceptance.log"), "w") do |output|
      success = system(env, File.join(prefix, "bin/ruby"), File.join(root, "test/compatibility/run.rb"), name, :out => output, :err => output)
      abort "Acceptance failed; see #{output.path}" unless success
    end
    puts File.read(File.join(work, "acceptance.log"))
  end
end
