# Scaffold verification

The scaffold harness covers gem metadata, loading, Engine registration, and an
unmounted Rails host boot. Focused mounted request and package checks are described
in [forwarding.md](../docs/forwarding.md). These do not establish browser parity.

## Compatibility bounds

- `required_ruby_version >= 2.3` and `railties >= 4.2, < 8.0` are provisional
  resolver bounds, not a verified support matrix. Ruby 2.3 / Rails 4.2 are planning
  targets, not confirmed Bluecotton or Monuvision versions. The source avoids
  syntax introduced after Ruby 2.3. The appraisal targets and executed evidence
  are recorded below; unavailable legacy runtimes remain unverified.
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
  The local, Git-ignored `Gemfile.lock` records the historical modern environment;
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

## Legacy appraisal smoke

This is a separate, narrow suite; it does not run the modern scaffold/browser
tests under legacy Ruby. `Appraisals`, `gemfiles/rails_*.gemfile` and
`test/compatibility/matrix.json` record exact versions of railties, actionpack,
actionview, activesupport and their complete generic-Ruby dependency closure.
The `rails` meta-gem is deliberately absent: no ActiveRecord or database is loaded.
The matrix uses Sprockets `3.7.2` / sprockets-rails `3.2.2` for Rails 4.2 and 5.2,
and Sprockets `4.2.1` with sprockets-rails `3.4.2` / `3.5.2` for Rails 6.1 / 7.2.
Full dependency patches are in the matrix JSON and each gemfile, including
legacy-compatible Nokogiri, Rack, Thor, concurrent-ruby and Minitest pins.

| Cell | Ruby | Rails components | Bundler | Executed acceptance on 2026-09-09 |
| --- | --- | --- | --- | --- |
| `rails_4_2` | 2.3.8 | 4.2.11.3 | 2.3.26 | **Unavailable**: interpreter absent |
| `rails_5_2` | 2.5.9 | 5.2.8.1 | 2.3.26 | **Unavailable**: interpreter absent |
| `rails_6_1` | 2.7.8 | 6.1.7.10 | 2.4.22 | **Unavailable**: interpreter absent |
| `rails_7_2` | 3.1.2p20 | 7.2.3.2 | 2.3.7 | **Passed**: 1 run, 74 assertions, 0 failures/errors/skips |

The worker is Debian 12 with only `/usr/bin/ruby3.1`; no rbenv, mise or ruby-build
is available. `docker version --format '{{.Server.Version}}'` fails to connect to
`unix:///var/run/docker.sock`. Each legacy runner invocation exits nonzero with
`UNAVAILABLE ... requires Ruby ...; current 3.1.2`. No legacy skip is counted as a
pass. The upper cell covers the declared Rails 7.x range; it is a fresh smoke run,
separate from the historical scaffold evidence above. No SDK compatibility fix
was required by this executed cell. Other allowed runtime combinations remain
unverified, and the scoped workflow is authored source, not executed CI evidence.

### Reproduce

Select the exact Ruby in the table, install its exact Bundler, and run from the
repository root **outside `bundle exec`**. For example, on Ruby 3.1.2:

```sh
gem install bundler -v 2.3.7 --no-document
ruby test/compatibility/check_matrix.rb
ruby test/compatibility/run.rb rails_7_2
```

For the legacy cells use Ruby 2.3.8/Bundler 2.3.26, Ruby 2.5.9/Bundler 2.3.26 or
Ruby 2.7.8/Bundler 2.4.22, then substitute `rails_4_2`, `rails_5_2` or `rails_6_1`.
The runner rejects a different Ruby patch or missing Bundler instead of silently
testing a substitute. Native gem compilation needs the normal Ruby development
headers and C build tools; it uses generic Ruby gems, not floating platform builds.
Gem installation/metadata resolution uses RubyGems network access. App boot,
precompile and requests reject external HTTP/socket attempts and require no
credentials or running server.

`TMPDIR` can select a writable scratch directory. Optional
`HANDRAIL_COMPAT_BUNDLE_PATH` selects a reusable gem cache. The runner retains its
printed `EVIDENCE` directory for inspection: the generated `host/Gemfile.lock`,
Git source, `snapshot.json`, dummy app and compiled assets. Remove that temporary
directory after review. No Bundler configuration, generated assets, Git index,
commit or branch is written in the registered checkout.

The runner clones the existing repository as an isolated bare fixture (no Git
initialization), then writes a synthetic commit containing the **current gemspec
package files**, including modified and untracked SDK implementation. It pins
Bundler's Git dependency to that full synthetic SHA. This local Git source is a
test fixture, not an application installation recommendation. Adoption must use
the public HTTPS SDK repository at a full committed SHA and a matching lockfile.

Appraisal gemfiles normally use the development gemspec; the canonical runner
replaces only that declaration with its temporary Git dependency. All dependency
versions are exact pins. `bundle lock` resolves them, `verify_lock.rb` rejects any
extra/mismatched gem or wrong SDK revision, then installation and execution use
frozen mode. There is no floating transitive resolution. The generated lockfile
must refer to the current fixture SHA/path, so it is retained per run rather than
checking a machine-specific local Git remote into the project.

To update pins, edit `matrix.json` and regenerate with Appraisal `2.5.0` from the
repository root. The generation tool is separate from the smoke bundles:

```sh
gem install appraisal -v 2.5.0 --no-document
ruby -e 'gem "appraisal", "2.5.0"; require "appraisal"; require "appraisal/cli"; Appraisal::CLI.start(["generate"])'
ruby test/compatibility/check_matrix.rb --metadata
```

The worker generated all four gemfiles using real Appraisal 2.5.0 in a temporary
copy, then verified their definitions and the CI matrix against `matrix.json`.

The smoke asserts Bundler Git provenance, Engine root, loaded SDK library paths,
installed asset filename, and SHA-256 equality for all 23 package files. Bundler
normalizes the installed gemspec, so its version, dependency names and package
file list are checked separately. Real `rake assets:precompile` must produce a
fingerprinted reporter entry in the Sprockets manifest whose bytes equal the
resolved asset. An empty executable `PATH` removes Node during precompile and
requests. Rails itself, cookie sessions and the CSRF verifier are never stubbed.
Only the HTTP transport boundary is injected: a valid token from the session
route yields 201 and exactly one forwarded call with session identity; an invalid
token yields 403 and no further call, even with host test CSRF protection off.

### Recorded commands and evidence

```sh
export compat_tmp=/opt/handrail/.handrail/codex-runs/a0df5d34-08c5-4f1d-a614-6df0eac89d04/tmp
TMPDIR="$compat_tmp" HANDRAIL_COMPAT_BUNDLE_PATH="$compat_tmp/compat-gems" \
  ruby test/compatibility/run.rb rails_7_2 > "$compat_tmp/rails_7_2.log" 2>&1
ruby test/compatibility/check_matrix.rb --metadata
ruby test/compatibility/run.rb rails_4_2 # exits 1: unavailable
ruby test/compatibility/run.rb rails_5_2 # exits 1: unavailable
ruby test/compatibility/run.rb rails_6_1 # exits 1: unavailable
```

The structural check passed for all four Appraisals/gemfiles. The optional online
metadata audit passed every pinned generic RubyGems gem's required Ruby version
and runtime dependency constraint for all four targets; **this is not legacy
runtime acceptance**. Metadata comes from the exact generic gemspecs under
`https://rubygems.org/quick/Marshal.4.8/`, avoiding Java variants in the JSON API.
The modern run installed 45 gems with 43 exact non-SDK/non-Bundler dependency
pins. RubyGems was `3.3.15`; important runtime pins include Rack `3.1.16`, Nokogiri
`1.15.7`, Minitest `5.22.3`, Rake `13.2.1` and Psych `4.0.3`.

Final successful fixture: `handrail-rails_7_2-20260909-5-f3p64n` under `compat_tmp`,
synthetic Git revision `5df3bfdf2487e11c485b97bceedb5daba767944f`; the installed
SDK root was `compat-gems/ruby/3.1.0/bundler/gems/sdk-5df3bfdf2487`. The exact
resolved lock is retained at that fixture's `host/Gemfile.lock`. This snapshot
included the uncommitted generator, notification, client, payload and gemspec
work; it did not simply test registered checkout HEAD `a1f8966`.

The compiled reporter was **240,060 bytes**, SHA-256
`9c535c29d0d454a49705944b8dc74fb344f600ca55d8855a57b9a09644f84269`, with manifest
entry `handrail_bug_reporter-831ebd94520bf49ede447a22c14da69f7abce02c1574a75abc3645e03798d13f.js`.
The run printed `valid=201/one HTTP boundary call; invalid=403/no additional call`.
Initial fixture-only failures (Rake's executable shebang with empty PATH, missing
environment initialization, and Bundler's normalized gemspec hash) were corrected
before the successful run. No unrelated test suite was run or claimed green.

`.github/workflows/rails-compatibility.yml` configures these four exact pairs on
Ubuntu 22.04 using [ruby/setup-ruby](https://github.com/ruby/setup-ruby), runs only
this suite, and retains locks, snapshot hashes and compiled assets as artifacts.
Workflow authoring does not prove the hosted runners have executed successfully.
Before Bluecotton or Monuvision adoption, obtain and match **each application's
actual `Gemfile.lock` and Ruby version** and run its matching cell. No supplied
evidence establishes either application's compatibility. Browser/CSS parity and
comprehensive installation documentation belong to separate checklist items.
