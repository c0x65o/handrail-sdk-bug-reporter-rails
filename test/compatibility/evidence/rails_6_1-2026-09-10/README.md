# Rails 6.1 runtime acceptance — 2026-09-10

**Passed: 1 run, 77 assertions, 0 failures, 0 errors, 0 skips.**
Rails SDK 0.4.49 with bundled JavaScript 0.4.50 ran on Ruby 2.7.8p225,
Rails components 6.1.7.10, RubyGems 3.1.6 and Bundler 2.4.22. Source checkout
HEAD: `47f24091ae01e6363b3dd1acf9b497183ee9ebe0`. The final working-tree package,
including the updated compatibility README, was installed from synthetic Git
revision `cf721d3b2381e38407ed10fac362f76dd6a537de`, Minitest seed `49100`.
This is current-package fixture evidence, not a release or consumer installation.

From the Rails repository root, outside `bundle exec`:

```sh
ruby test/compatibility/bootstrap_rails_6_1.rb
ruby test/compatibility/bootstrap_test.rb
```

This worker set `TMPDIR` to the private run directory in `artifacts.json`.
The shared bootstrap built Ruby 2.7.8 from checksum-verified upstream source,
using two compiler jobs and private static OpenSSL 1.0.2u / libyaml 0.2.5.
The Ruby SHA-256 matches the [upstream release announcement](https://www.ruby-lang.org/en/news/2023/03/30/ruby-2-7-8-released/).
The Bundler 2.4.22 SHA-256 matches the [RubyGems version metadata](https://rubygems.org/api/v2/rubygems/bundler/versions/2.4.22.json),
retained here as `bundler-2.4.22-metadata.json`. All four archives were verified
before extraction or installation. No Docker, system runtime installation,
database, credentials or running server was required.

Ruby and Bundler pins are now selected per cell. The Rails 4.2 and 5.2 entry
points and their Ruby/Bundler/source pins remain unchanged. Shared bootstrap
cache identity still includes the recipe bytes and cell name. Existing runtime
prefix, concurrency and job-limit guards and private umask remain in force.
No SDK implementation, matrix, appraisal, Git-install runner, smoke assertion or
dummy-host repair was required. All pre-existing Rails 4.2/5.2 evidence and sibling
runner changes were preserved byte-for-byte.

The acceptance establishes:

- Actual Bundler Git loading at the full synthetic revision outside the source
  checkout, with Engine root and loaded SDK libraries inside the installed gem.
- Equality of all 26 package snapshot entries with the installed package;
  normalized gemspec version, dependency names and inventory checked separately.
- Exact 25-gem dependency closure, resolved lock verification and frozen install;
  27 installed gems including the SDK and Bundler. `Gemfile.lock` is unedited.
- Actual Sprockets 4.2.1 precompilation with an empty executable PATH, without
  Node, ExecJS, ActiveRecord, a database or external HTTP/socket requests during
  precompile and request execution.
- A real HttpOnly cookie session and Rails-generated CSRF token. A valid request
  returns 201 and forwards once with the session principal; an invalid token
  returns 403 with no additional upstream call. Only the external HTTP transport
  boundary is injected; Rails sessions and CSRF verification are real.

The compiled reporter is **241,154 bytes**, SHA-256
`2e2f999cf20760913f1af917bf7cb51d1cc21d0005f15ca74236438b2f04216f`.
The retained gzip decompresses to those exact bytes, and the smoke verifies
that they equal the asset resolved from the installed gem. This is the observed
Sprockets 4 output; the prior Sprockets 3 cell artifacts are preserved separately.

## Retained evidence

- `acceptance.json`: runner-generated source revision/status, runtime versions,
  harness hashes, package revision, artifact hashes, timestamps and test totals.
- `snapshot.json`: SHA-256 inventory of the current package files.
- `Gemfile` and `Gemfile.lock`: actual fixture Git dependency and exact lock.
  The local absolute Git URL is historical fixture evidence, not an adoption URL.
- `run.log` and `smoke.log`: lock verification, frozen install, precompilation,
  request outcomes, assertion totals and seed from final package acceptance.
- `initial-run.log`: first full source-bootstrap acceptance (77 assertions,
  seed `39643`, package `894b8dbc7461776ab9b96b7d043faa4b370a0814`).
  Final acceptance reran with a fresh fixture and lock after README.md changed.
- `sources.json`, `bundler-2.4.22-metadata.json` and `bootstrap.log.gz`: source
  URLs/checksums, upstream Bundler metadata and complete compilation/install log.
- `bootstrap-controls.log`: **3 runs, 81 assertions, zero failures/errors/skips**.
  All three entry points reject drift in Ruby/Rails/Bundler pins, corrupt Ruby
  archives, in-checkout runtime paths, whitespace paths, excess build jobs and
  concurrent use. These are guard checks, not older-cell runtime acceptance.
- `package.bundle`: self-contained Git bundle of the tested package commit.
- `sprockets-manifest.json` and `reporter.js.gz`: actual precompilation artifacts.
- `artifacts.json`: original scratch locations, bootstrap/runtime/toolchain
  identity, retained-artifact hashes and cached gem archive hashes.
- `verification.log`: final package/harness/source/artifact hash verification,
  evidence preservation, syntax, matrix and whitespace checks.

Host Ruby 3.1.2 and built Ruby 2.7.8 syntax checks passed for all 12 compatibility
and dummy Ruby files. Matrix consistency, artifact/package/harness hashes,
Git bundle verification, earlier evidence preservation and `git diff --check`
passed. Compiler warnings did not prevent runtime or native gem builds.

Consumer installation, release tagging, browser re-QA and hosted CI were outside
this request. Older-cell historical evidence is preserved, not presented as fresh
Rails 4.2/5.2 runtime acceptance. No checkout commit, push, PR, deployment, database
or queue-state change was made.
