require "bundler"
require "json"

cell = JSON.parse(File.read(ENV.fetch("HANDRAIL_COMPAT_MATRIX"))).fetch(ENV.fetch("HANDRAIL_COMPAT_CELL"))
lock = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile))
actual = {}
lock.specs.each { |spec| actual[spec.name] = spec.version.to_s unless spec.name == "handrail-bug-reporter" }
raise "Dependency closure differs from exact matrix pins: #{actual.inspect}" unless actual == cell.fetch("gems")
raise "Wrong Bundler" unless Bundler::VERSION == cell.fetch("bundler")
sdk = lock.specs.find { |spec| spec.name == "handrail-bug-reporter" }
raise "SDK must use Bundler Git" unless sdk && sdk.source.is_a?(Bundler::Source::Git)
raise "Wrong Git revision" unless sdk.source.revision == ENV.fetch("HANDRAIL_COMPAT_REVISION")
puts "LOCK PASS: #{actual.length} exact dependency versions; SDK Git #{sdk.source.revision}"
