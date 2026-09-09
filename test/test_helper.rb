require "minitest/autorun"
require "open3"
require "rbconfig"
require "json"

class ScaffoldTestCase < Minitest::Test
  ROOT = File.expand_path("..", File.dirname(__FILE__))

  def run_ruby(source, environment = {}, directory = ROOT)
    stdout, stderr, status = Open3.capture3(
      environment, RbConfig.ruby, "-I", File.join(ROOT, "lib"),
      "-I", File.join(ROOT, "test"), "-r", "support/no_network",
      "-e", source, :chdir => directory
    )
    assert status.success?, "Child Ruby failed (#{status.exitstatus}):\n#{stdout}\n#{stderr}"
    stdout
  end
end
