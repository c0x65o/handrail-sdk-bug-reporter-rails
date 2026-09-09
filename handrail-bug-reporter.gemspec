require_relative "lib/handrail/bug_reporter/version"

Gem::Specification.new do |spec|
  spec.name = "handrail-bug-reporter"
  spec.version = Handrail::BugReporter::VERSION
  spec.authors = ["Handrail"]
  spec.summary = "Handrail bug reporter integration for Rails."
  spec.homepage = "https://github.com/c0x65o/handrail-sdk-bug-reporter-rails"

  # Provisional compatibility bounds; see test/README.md for verified coverage.
  spec.required_ruby_version = ">= 2.3"
  spec.add_runtime_dependency "railties", ">= 4.2", "< 8.0"

  # Do not require Git, Rails, or network access to evaluate/package the gem.
  spec.files = Dir.chdir(File.dirname(__FILE__)) do
    Dir["lib/**/*.rb", "config/routes.rb", "app/controllers/**/*.rb", "app/helpers/**/*.rb",
      "README.md", "app/assets/javascripts/handrail_bug_reporter.js"].sort
  end
  spec.require_paths = ["lib"]
  # No license has been granted in this repository; do not invent one here.
end
