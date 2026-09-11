# Rails 5.2 runtime acceptance — 2026-09-10

**Passed: 1 run, 77 assertions, 0 failures, 0 errors, 0 skips.**
Scope: Rails SDK 0.4.49 with bundled JavaScript 0.4.50, on Ruby 2.5.9p229,
Rails components 5.2.8.1, RubyGems 2.7.6.3 and Bundler 2.3.26. Source checkout
HEAD: `47f24091ae01e6363b3dd1acf9b497183ee9ebe0`. The final working-tree package
(including the updated compatibility README) was installed from synthetic Git
revision `894b8dbc7461776ab9b96b7d043faa4b370a0814`, Minitest seed `11829`.
This records a current-package fixture, not a release or consumer installation.

From the Rails repository root, outside `bundle exec`:

```sh
ruby test/compatibility/bootstrap_rails_5_2.rb
```

On this worker, `TMPDIR` was set to the private run directory recorded in
`artifacts.json`. The bootstrap built Ruby from checksum-verified upstream source
using two compiler jobs and private static OpenSSL 1.0.2u / libyaml 0.2.5. Ruby's
SHA-256 pin matches the [upstream release announcement](https://www.ruby-lang.org/en/news/2021/04/05/ruby-2-5-9-released/).
Bundler was installed from the checksum-pinned local gem. No Docker daemon,
system runtime modification, database, credentials or running server was used.

The Rails 4.2 bootstrap was extracted into `test/compatibility/bootstrap.rb`;
`bootstrap_rails_4_2.rb` retains its documented entry point and runtime pins.
The shared cache identity includes the bootstrap bytes and cell name. New scratch
outputs use umask 0077. All pre-existing Rails 4.2 evidence and `run.rb` remained
byte-for-byte unchanged. No SDK implementation, matrix, appraisal, smoke assertion
or dummy-host change was required by Rails 5.2.

The acceptance establishes:

- Actual Bundler Git loading at the full synthetic revision outside the source
  checkout; Engine root and all loaded SDK libraries resolve to the installed gem.
- Equality of all 26 package snapshot entries with the installed package, with
  normalized gemspec version, dependency names and inventory checked separately.
- Exact 25-gem dependency closure and frozen installation, with 27 installed gems
  including the SDK and Bundler. `Gemfile.lock` is the unedited resolved lock.
- Actual Sprockets 3.7.2 precompilation with empty executable PATH, without Node,
  ExecJS, ActiveRecord, a database or external HTTP/socket requests during execution.
- A real HttpOnly cookie session and Rails-generated CSRF token. A valid request
  returns 201 and forwards once with the session principal; an invalid token
  returns 403 with no additional upstream call. Only the external HTTP transport
  boundary is injected; Rails, cookie sessions and CSRF verification are real.

The compiled reporter is **241,155 bytes**, SHA-256
`bdab3525cf1f8de0f7ac1f2966d8a6f9afc1840f46c77437d0aa5c9140694a17`.
The retained gzip decompresses to those exact bytes.

## Retained evidence

- `acceptance.json`: runner-generated source revision/status, runtime versions,
  harness hashes, package revision, artifact hashes, timestamps and test totals.
- `snapshot.json`: SHA-256 inventory of the current package files.
- `Gemfile` and `Gemfile.lock`: actual fixture Git dependency and exact lock.
  The local absolute Git URL is historical fixture evidence, not an adoption URL.
- `run.log` and `smoke.log`: lock verification, frozen install, actual precompile,
  request outcomes, assertion totals and Minitest seed.
- `sources.json`: verified upstream source URLs and pinned SHA-256 values.
- `bootstrap.log.gz`: full source compilation and isolated Bundler install output.
- `bootstrap-controls.log`: six successful negative controls; both entry points
  rejected corrupt Ruby archives, in-checkout runtime prefixes and concurrent use.
- `package.bundle`: self-contained Git bundle of the tested package commit.
- `sprockets-manifest.json` and `reporter.js.gz`: actual precompilation artifacts.
- `artifacts.json`: original scratch locations, bootstrap/runtime/toolchain identity,
  retained-artifact hashes and cached gem archive hashes.

Host Ruby and built Ruby 2.5.9 syntax checks passed for all compatibility and dummy
Ruby files. Matrix consistency, artifact/package/harness hash verification,
Rails 4.2 evidence preservation and `git diff --check` also passed. The first full
source bootstrap passed 77 assertions on package `92da5c8ff2000d164ef1f8e9d17cec1417a11d93`
(seed `26260`); the final acceptance above reran after the packaged README changed.
The runtime cache was reused while the runner created a fresh fixture and lock.

RubyGems 2.7.6.3 emits its existing warning about future unpinned Bundler installs;
this bootstrap installs the pinned, checksum-verified Bundler 2.3.26 gem locally.
The source-build warnings did not prevent successful runtime and native gem builds.

Rails 6.1, consumer applications, browser re-QA, hosted CI, tagging and releases
were outside this request. Prior Rails 4.2 evidence is preserved, not claimed as
a fresh Rails 4.2 execution of the extracted bootstrap. No checkout commit, push,
PR, deployment, database or queue-state change was made.
