require "json"

# Pin the entire dependency closure, including legacy-compatible transitive gems.
# The canonical smoke runner replaces only gemspec with an isolated Git source.
# Appraisal 2.5 evaluates this DSL with its own source filename, so use the
# repository working directory rather than __dir__.
JSON.parse(File.read("test/compatibility/matrix.json")).each do |name, cell|
  appraise name do
    ruby cell.fetch("ruby")
    cell.fetch("gems").each { |name, version| gem name, "= #{version}" }
  end
end
