# Run with the host Ruby, outside bundle exec. Guards never build a runtime.
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

class CompatibilityBootstrapTest < Minitest::Test
  ROOT = File.expand_path("../..", File.dirname(__FILE__))
  CELLS = {
    "rails_4_2" => ["2.3.8", "4.2.11.3", "2.3.26"],
    "rails_5_2" => ["2.5.9", "5.2.8.1", "2.3.26"],
    "rails_6_1" => ["2.7.8", "6.1.7.10", "2.4.22"]
  }

  CELLS.each do |name, versions|
    define_method("test_#{name}_pins_and_guards") do
      Dir.mktmpdir("bootstrap-controls-") do |scratch|
        checkout = File.join(scratch, "sdk")
        harness = File.join(checkout, "test/compatibility")
        FileUtils.mkdir_p(harness)
        %W[bootstrap.rb bootstrap_#{name}.rb matrix.json].each do |file|
          FileUtils.cp(File.join(ROOT, "test/compatibility", file), harness)
        end
        matrix_file = File.join(harness, "matrix.json")
        original = File.read(matrix_file)
        matrix = JSON.parse(original)
        assert_equal versions, matrix.fetch(name).values_at("ruby", "rails", "bundler")
        work = File.join(scratch, "runtime")
        env = { "HANDRAIL_COMPAT_RUNTIME" => work, "HANDRAIL_COMPAT_JOBS" => "2" }
        reject = lambda do |overrides, message|
          output, status = Open3.capture2e(env.merge(overrides), RbConfig.ruby,
            File.join(harness, "bootstrap_#{name}.rb"))
          refute status.success?, output
          assert_includes output, message
          puts "#{name}: rejected #{message}"
        end
        %w[ruby rails bundler].each do |key|
          changed = JSON.parse(original)
          changed.fetch(name)[key] = "0.0.0"
          File.write(matrix_file, JSON.generate(changed))
          reject.call({}, "Bootstrap pins must match #{name}")
        end
        File.write(matrix_file, original)
        reject.call({ "HANDRAIL_COMPAT_RUNTIME" => checkout }, "Runtime directory must be outside the SDK checkout")
        reject.call({ "HANDRAIL_COMPAT_RUNTIME" => work + " space" }, "Use a runtime directory without whitespace")
        reject.call({ "HANDRAIL_COMPAT_JOBS" => "3" }, "HANDRAIL_COMPAT_JOBS must be 1 or 2")
        File.open(File.join(work, "bootstrap.lock"), "w") do |guard|
          assert guard.flock(File::LOCK_EX | File::LOCK_NB)
          reject.call({}, "Runtime directory is already in use")
        end
        FileUtils.mkdir_p(File.join(work, "downloads"))
        archive = File.join(work, "downloads", "ruby-#{versions.first}.tar.gz")
        File.write(archive, "deliberately corrupt archive")
        reject.call({}, "SHA256 mismatch: #{archive}")
        refute File.exist?(File.join(work, "runtime")), "Guards must stop before compiling"
      end
    end
  end
end
