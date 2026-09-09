# Scaffold verification

The scaffold harness covers gem metadata, loading, Engine registration, and an
unmounted Rails host boot. Focused mounted request and package checks are described
in [forwarding.md](../docs/forwarding.md). These do not establish browser parity.

## Compatibility bounds

- `required_ruby_version >= 2.3` and `railties >= 4.2, < 8.0` are provisional
  resolver bounds, not a verified support matrix. Ruby 2.3 / Rails 4.2 are planning
  targets, not confirmed Bluecotton or Monuvision versions. The source avoids
  syntax introduced after Ruby 2.3. The separate appraisal item must establish
  compatible Ruby, Rails, Bundler, and transitive dependency combinations.
- The Rails lower bound preserves the requested legacy target; the upper bound
  avoids admitting Rails 8 before its compatibility is evaluated. Other permitted
  combinations remain unverified, even though the resolver allows them.
- `railties` is the only direct runtime dependency. It brings its own Rails
  dependencies, including Action Pack and Active Support. The Engine explicitly
  loads Action Dispatch so requiring the SDK before the host loads Rails works.
  No ActiveRecord, database adapter, React, Node, or HTTP client gem is required.
  Future transport code can use standard-library HTTP/JSON facilities.
- Rake (`>= 10, < 14`) and Minitest (`>= 5, < 6`) are development dependencies in
  the Gemfile. These ranges permit older versions for legacy appraisal bundles.
  The checked-in `Gemfile.lock` records this worker's modern smoke environment;
  it is not a lockfile for a Ruby 2.3 host and is not packaged into the gem.
- Version `0.4.49` records the intended JavaScript baseline only. It does not mean
  this scaffold already implements that release's functionality. No tag or release
  was created. No license grant exists in the inspected repository, so the
  gemspec intentionally omits license metadata.

The Engine uses Rails' documented
[namespace isolation](https://guides.rubyonrails.org/v7.2/engines.html).
Its intake/policy routes and request guard run only when a host explicitly mounts
it. Requiring the gem adds no host routes or host middleware and mounts no widget.

## Harness

Run `bundle exec rake test` from the repository root (`bundle3.1` on this worker).
The four tests start fresh Ruby processes to prevent require order and Rails
singleton state leaking between cases:

1. Evaluate the gemspec from a temporary directory with Rails/Active Support
   requires rejected. Check version metadata, package file selection, dependency
   scope, and provisional lower bounds without booting Rails.
2. Require the entry point before Rails, verify real Engine inheritance,
   registration and isolation, require twice, and verify no application boot.
3. Require the entry point after Rails and the controller railtie.
4. Initialize the actual Rails application in `fixtures/minimal`, both without
   and with the Engine. Confirm the Engine participates in the host's railties,
   ActiveRecord is absent, and the engine defines intake/policy routes. Compare
   host routes, middleware, and responses. `/health` stays exactly `<p>host only</p>`
   with status 200; unclaimed and unmounted intake URLs remain 404. No TCP server
   or database is used.

Every child process rejects Net::HTTP requests and TCP/socket connection attempts
before they execute, and fails at exit even if application code rescues a rejected
attempt. These guards are service-boundary checks; Engine registration and Rails
boot use the real framework, with no mocked Rails classes.

## Recorded worker run (2026-09-09)

Verified: Ruby `3.1.2p20` (`4491bb740a`, x86_64-linux-gnu), RubyGems `3.3.15`,
Bundler `2.3.7`, railties/actionpack/actionview/activesupport `7.2.3.2`, Rack
`3.2.7`, Minitest `5.27.0`, Rake `13.4.2`, Psych `5.5.0`. All resolved gem versions
are recorded in `Gemfile.lock`.

Commands below ran from the repository root. The first install attempt without
the Psych build option failed because this worker lacks `yaml.h`. Providing
libyaml source in the run's temporary directory resolved that setup issue;
no runtime dependency constraints or system packages were changed.

```sh
export scaffold_tmp=/opt/handrail/.handrail/codex-runs/0721161e-1038-4153-871a-ff49265652e9/tmp
export BUNDLE_USER_HOME="$scaffold_tmp/bundler"
export BUNDLE_APP_CONFIG="$scaffold_tmp/bundle-config"
export BUNDLE_PATH="$scaffold_tmp/gems"
curl --fail --location --silent --show-error https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz --output "$scaffold_tmp/yaml-0.2.5.tar.gz"
tar -xzf "$scaffold_tmp/yaml-0.2.5.tar.gz" -C "$scaffold_tmp"
export BUNDLE_BUILD__PSYCH="--with-libyaml-source-dir=$scaffold_tmp/yaml-0.2.5"
bundle3.1 install --jobs 2 --retry 2
bundle3.1 exec rake test
```

Install: **passed**, 47 gems. Final tests: **4 runs, 12 assertions, 0 failures,
0 errors, 0 skips**, seed `45564`. The libyaml archive SHA-256 was
`c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4`.

Additional executed checks (same `scaffold_tmp` as above):

```sh
ruby -e 'spec = Gem::Specification.load("handrail-bug-reporter.gemspec"); abort "invalid spec" unless spec; abort "Rails loaded" if defined?(Rails); puts "#{spec.name} #{spec.version}: #{spec.files.join(", ")}"'
ruby -e 'paths = Dir["lib/**/*.rb", "test/**/*.rb"] + ["Gemfile", "Rakefile", "handrail-bug-reporter.gemspec"]; paths.each { |path| abort path unless system(RbConfig.ruby, "-c", path) }'
gem build handrail-bug-reporter.gemspec --output "$scaffold_tmp/handrail-bug-reporter-0.4.49.gem"
ruby -rrubygems/package -e 'package = Gem::Package.new(ARGV.fetch(0)); required = Dir["lib/**/*.rb"]; abort "missing library files" unless (required - package.contents).empty?; puts package.contents' "$scaffold_tmp/handrail-bug-reporter-0.4.49.gem"
git diff --check
```

All passed. The local gem archive contains README.md and all three library files.
Gem build emits the expected missing-license warning; visibility was not treated
as permission to invent a license. The archive remains outside the checkout.
No publication, tagging, deployment, commit, push, or PR was performed.
