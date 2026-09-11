# Rails 4.2 runtime acceptance — 2026-09-10

**Passed: 1 run, 77 assertions, 0 failures, 0 errors, 0 skips.**
Scope: Rails SDK 0.4.49 with bundled JavaScript 0.4.50, on Ruby 2.3.8p459,
Rails components 4.2.11.3 and Bundler 2.3.26. Source checkout HEAD:
`47f24091ae01e6363b3dd1acf9b497183ee9ebe0`. The synthetic Git package revision
and every current package file's SHA-256 are retained below. This is acceptance
of the recorded working-tree package, not a release or consumer installation.
The successful end-to-end bootstrap tested package revision
`92da5c8ff2000d164ef1f8e9d17cec1417a11d93` with Minitest seed `38426`.

From the Rails repository root, outside `bundle exec`:

```sh
ruby test/compatibility/bootstrap_rails_4_2.rb
```

The bootstrap builds from checksum-verified upstream archives into a private
scratch prefix, with two compiler jobs. It uses the existing exact matrix,
appraisal gemfile, Git snapshot runner, lock verifier, dummy Rails host and smoke
without changing their version pins. No Docker daemon or system runtime changes
are used. Runtime details and compiler/build commands are in the retained logs.

The acceptance establishes:

- Actual Bundler Git loading from the synthetic full SHA, outside the source
  checkout; Engine root and all loaded SDK libraries resolve to the installed gem.
- Equality of the 26-entry package snapshot with installed bytes, with normalized
  gemspec version, dependency names and package inventory checked separately.
- An exact 25-gem dependency closure and frozen installation (27 installed gems
  including the SDK and Bundler); the resolved lock is preserved without edits.
- Real Sprockets 3.7.2 precompilation with no executables on PATH, no ExecJS,
  ActiveRecord, database, or external HTTP/socket requests during execution.
- A real HttpOnly cookie session and Rails-generated CSRF token: the valid request
  returns 201 and forwards exactly once with the session principal; an invalid
  token returns 403 and makes no additional upstream call. Only the external HTTP
  transport boundary is injected.

The compiled reporter is **241,155 bytes**, SHA-256
`bdab3525cf1f8de0f7ac1f2966d8a6f9afc1840f46c77437d0aa5c9140694a17`.
The gzip artifact decompresses to those exact bytes.

## Retained evidence

- `acceptance.json`: runner-generated source revision/status, runtime versions,
  harness hashes, synthetic package SHA, artifact hashes, timestamps and totals.
- `snapshot.json`: raw package-file SHA-256 inventory.
- `Gemfile` and `Gemfile.lock`: exact generated Git fixture declaration and lock.
  Their local absolute Git path is historical evidence, not an installation URL.
- `run.log` and `smoke.log`: actual command output, lock verification, asset build,
  request outcomes, assertion count and Minitest seed.
- `sources.json`: bootstrap archive URLs and pinned SHA-256 values.
- `bootstrap.log.gz`: source build and isolated Bundler installation output.
- `skip-control.log`: expected rejection of an intentional skip in a temporary
  clone; this is a negative control, separate from the successful acceptance.
- `package.bundle`: self-contained Git bundle of the tested package commit.
- `sprockets-manifest.json` and `reporter.js.gz`: actual precompile artifacts.
- `artifacts.json`: original scratch locations, toolchain details, archive hashes,
  and the mapping of retained copies to their original artifacts.

The machine-specific source prefix and full temporary fixture remain available
at the locations in `artifacts.json`. A new run creates its own fixture and lock;
its synthetic SHA changes if package bytes (including README.md) change.

Additional checks passed: host and Ruby 2.3.8 syntax checks for compatibility and
dummy-host Ruby files; matrix consistency; corrupt-archive rejection before
extraction/build; rejection of a runtime prefix inside the source checkout;
rejection of an intentional skip alongside 77 successful assertions; retained
artifact/package/harness hash verification; and `git diff --check`.

Initial bootstrap attempts exposed a legacy configure-option spelling, legacy
RubyGems option ordering, and a source-isolation rejection when the cache was
inside the checkout. These were corrected in bootstrap support. No smoke
assertions, SDK implementation, or dummy-host behavior were weakened or changed.
RubyGems 2.5.2.3 emits its known unpinned-Bundler-install warning; this bootstrap
installs the checksum-pinned Bundler 2.3.26 gem locally.

Rails 5.2/6.1, consumer applications, browser QA, hosted CI, tagging and releases
were not evaluated by this cell. No commit, push, deployment or PR was made.
