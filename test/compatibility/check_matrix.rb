# Structural checks run with the worker's Ruby; they are not matrix acceptance.
require "json"
require "rubygems"
require "yaml"

root = File.expand_path("../..", File.dirname(__FILE__))
matrix = JSON.parse(File.read(File.join(root, "test/compatibility/matrix.json")))
class AppraisalDefinition
  attr_reader :gems, :version
  def initialize
    @gems = {}
  end
  def ruby(version)
    @version = version
  end
  def gem(name, requirement)
    @gems[name] = requirement.sub("= ", "")
  end
end
definitions = {}
context = Object.new
context.define_singleton_method(:appraise) do |name, &block|
  definition = AppraisalDefinition.new
  definition.instance_eval(&block)
  definitions[name] = definition
end
Dir.chdir(root) do
  context.instance_eval(File.read("Appraisals"), File.join(root, "Appraisals"))
end
matrix.each do |name, cell|
  definition = definitions.fetch(name)
  raise "Appraisals drift: #{name}" unless definition.version == cell.fetch("ruby") && definition.gems == cell.fetch("gems")
  gemfile = File.read(File.join(root, "gemfiles", name + ".gemfile"))
  parsed = AppraisalDefinition.new
  parsed.define_singleton_method(:source) { |url| raise url unless url == "https://rubygems.org" }
  parsed.define_singleton_method(:gemspec) { |options| raise options.inspect unless options == { :path => "../" } }
  parsed.instance_eval(gemfile)
  raise "Gemfile drift: #{name}" unless parsed.version == definition.version && parsed.gems == definition.gems
  cell.fetch("gems").each do |gem, version|
    raise "Not an exact patch: #{gem} #{version}" unless version =~ /\A\d+\.\d+\.\d+(?:\.\d+)*\z/
  end
  puts "CONFIG PASS #{name}: Ruby #{cell['ruby']}, Rails #{cell['rails']}, Bundler #{cell['bundler']}, #{cell['gems'].length} exact gem pins"
end

workflow = YAML.load_file(File.join(root, ".github/workflows/rails-compatibility.yml"))
rows = workflow.fetch("jobs").fetch("smoke").fetch("strategy").fetch("matrix").fetch("include")
expected = matrix.map { |name, cell| { "cell" => name, "ruby" => cell.fetch("ruby"), "bundler" => cell.fetch("bundler") } }
raise "Workflow matrix drift" unless rows == expected
puts "CONFIG PASS: workflow matches all four exact runtime/Bundler pairs"

# Optional online metadata audit, useful even when a target interpreter is absent.
# Fetch generic ruby gemspecs (the JSON API may return a Java platform variant).
if ARGV.include?("--metadata")
  require "net/http"
  require "zlib"
  cache = {}
  matrix.each do |name, cell|
    cell.fetch("gems").merge("bundler" => cell.fetch("bundler")).each do |gem, version|
      key = "#{gem}-#{version}"
      spec = cache[key] ||= begin
        uri = URI("https://rubygems.org/quick/Marshal.4.8/#{key}.gemspec.rz")
        response = Net::HTTP.get_response(uri)
        raise "Metadata unavailable #{uri}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        Marshal.load(Zlib::Inflate.inflate(response.body))
      end
      raise "#{name}: #{key} rejects Ruby #{cell['ruby']}" unless spec.required_ruby_version.satisfied_by?(Gem::Version.new(cell.fetch("ruby")))
      spec.runtime_dependencies.each do |dependency|
        pin = cell.fetch("gems")[dependency.name]
        raise "#{name}: #{key} needs #{dependency}" unless pin && dependency.requirement.satisfied_by?(Gem::Version.new(pin))
      end
    end
    puts "METADATA PASS #{name}: generic gem dependency closure and required Ruby versions (not runtime acceptance)"
  end
end
