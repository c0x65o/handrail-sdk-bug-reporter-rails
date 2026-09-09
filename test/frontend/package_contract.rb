require "rubygems/package"
require "rubygems/installer"
require "tmpdir"
require "digest"

root = File.expand_path("../..", __dir__)
asset = "app/assets/javascripts/handrail_bug_reporter.js"
spec = Gem::Specification.load(File.join(root, "handrail-bug-reporter.gemspec"))
raise "Missing asset" unless spec.files.include?(asset)
raise "Unexpected install build" unless spec.extensions.empty?
raise "Contributor files packaged" if spec.files.any? { |path| path =~ /\A(?:node_modules|frontend|scripts)\// }
raise "License changed" unless spec.licenses.empty?

Dir.mktmpdir(".asset-package-", root) do |tmp|
  archive = File.join(tmp, "reporter.gem")
  Dir.chdir(root) { Gem::Package.build(spec, false, false, archive) }
  package = Gem::Package.new(archive)
  raise "Archive missing asset" unless package.contents.include?(asset)
  installed = Gem::Installer.at(archive, :install_dir => File.join(tmp, "gems"),
    :ignore_dependencies => true, :wrappers => false).install
  expected = Digest::SHA256.file(File.join(root, asset)).hexdigest
  actual = Digest::SHA256.file(File.join(installed.full_gem_path, asset)).hexdigest
  raise "Installed asset differs" unless expected == actual
end
puts "Asset packaged and installed without Node or Git"
