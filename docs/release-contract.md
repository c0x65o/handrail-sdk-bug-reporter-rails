# Rails package provenance contract

`release-manifest.json` is packaged with the Ruby sources, generator templates and
self-contained browser asset. Gem specification evaluation and reporter identity
validate it using Ruby's JSON and SHA-256 libraries. They do not run Git, Node,
npm, an asset build or a network request. A missing, malformed, stale or corrupted
manifest/package raises `Handrail::BugReporter::ReleaseManifest::Invalid`.

The Rails gem version comes from `lib/handrail/bug_reporter/version.rb`. It is
independent of the frozen browser dependency: `@handrail/bug-reporter` **0.4.49**,
`refs/tags/v0.4.49`, commit
`96b293248611594c388d0fab3af63b1b2d1aae5c`. The verifier compares that mapping with
`frontend/upstream.json`, the dependency and both relevant package-lock entries.
The JS repository's tracked generated release.ts is not an input.

## Provenance semantics

* `source_snapshot`: records the base Git commit and `commit:<base>` separately
  from release identity. Rails reporter commit/ref remain JSON null. Checksums
  identify the actual current files, including uncommitted work; the base is not
  claimed to contain those bytes. This is the checked-in manifest's current mode.
* `committed_source`: Rails reporter commit/ref identify an existing immutable
  **source revision**, with all runtime files and contributor inputs byte-equal to
  that revision. The manifest is a later attestation, excluded from its own input
  hashes. Its containing commit is deliberately not its source commit. A ref must
  be `commit:<full SHA>` or an existing matching `refs/tags/v<gem version>` resolving
  to the source commit. Missing tags, branch refs, short SHAs, version/ref mismatches
  and dirty source trees are rejected by Git verification.

For an eventual distribution tag, the natural sequence is source commit A, then
manifest-only commit B attesting A, then a version tag pointing at B. Runtime
identity is `commit:A`; it does not pretend that A is B. `--tag` verifies the
existing distribution tag/version at HEAD, the committed manifest, ancestry of A,
clean source and byte equality. No script creates a commit or tag. Finalization
and any release remain separately authorized operations.

Offline checks establish internal consistency and detect accidental corruption;
they cannot authenticate a claimed Git revision or a maliciously rewritten file
plus checksum. Use `--git`/`--tag` with the trusted SDK checkout for that evidence.
Neither mode consults a parent consumer repository. At runtime all paths are
relative to the installed SDK and environment identity overrides are ignored.

## Local commands

```sh
# Offline contributor verification, including frontend inputs; no node_modules.
ruby scripts/verify_release.rb
# Also check that the snapshot base or committed source exists in this SDK Git.
ruby scripts/verify_release.rb --git
# Check an installed package or exported package-only tree.
ruby scripts/verify_release.rb --root /path/to/installed/gem --package
# Refresh a development snapshot after intentional source changes.
ruby scripts/verify_release.rb --write-snapshot
# Attest an existing clean source revision; supply a full SHA and explicit ref.
ruby scripts/verify_release.rb --write-committed --commit FULL_SHA --ref commit:FULL_SHA
# Verify an already-existing distribution tag after manifest finalization.
ruby scripts/verify_release.rb --tag refs/tags/vVERSION
# Isolated local packaging tests, including negative cases.
ruby test/package_contract_test.rb
ruby test/frontend/package_contract.rb
ruby -Ilib:test test/payload_test.rb
```

`--write-snapshot` intentionally records current reviewed bytes; it does not build
or prove reproducibility of the browser bundle. When frontend inputs change, use
the existing frontend build/verification workflow before refreshing the manifest.
The ordinary verifier rejects changed inputs until the manifest is refreshed.
The existing Node contract still verifies installed upstream identity and sources;
this Ruby contract adds an offline package check without replacing that build check.
Runtime file hashes and the asset are always checked, even in package-only mode.
Contributor hashes are checked only in source mode because those files are not
shipped in the gem. README prose is not a runtime identity input.

The package test uses a temporary bare clone, temporary Git index and Git plumbing
for synthetic source/distribution commits and a synthetic `v1.2.3` tag. It never
changes registered checkout refs or history. It archives that tag, builds and
installs the gem with an empty executable PATH and network guard, then checks
identity from a different consumer Git repository. Rails 1.2.3 and JS 0.4.49 in
this fixture explicitly prove version independence. No actual SDK release tag,
publish operation or network install occurs.

## Artifact evidence

Committed browser asset: `app/assets/javascripts/handrail_bug_reporter.js`.
SHA-256: `9c535c29d0d454a49705944b8dc74fb344f600ca55d8855a57b9a09644f84269`.
The verifier prints Rails provenance, JS identity, this checksum and the number
of verified runtime files; the package test prints its synthetic commit evidence.

Validation on Ruby 3.1.2 (2026-09-09):

| Command | Result |
| --- | --- |
| `ruby scripts/verify_release.rb --git` | Passed; 23 runtime files and 8 source inputs; snapshot base `a1f896610d6a3e6b71766a605ffe9c0841980f02` |
| `ruby test/package_contract_test.rb` | Passed; 12 tests, 468 assertions |
| `ruby test/frontend/package_contract.rb` | Passed; gem built/installed, asset byte equality |
| `ruby -Ilib:test test/payload_test.rb` | Passed; 59 tests, 278 assertions |
| `ruby -Ilib:test test/scaffold_test.rb --name test_gemspec_evaluates_without_rails_from_another_directory` | Passed; 1 test, 2 assertions |
| `ruby -c` on release_manifest.rb, verify_release.rb and package_contract_test.rb | Syntax OK |
| `git diff --check` | Passed |

The final isolated package fixture recorded source
`2d7cfe1fa4f1d5b84892c0babf7dea70db3cb927` and distribution
`dd3cdb9fdaae7342d7140b115470919168458908`, synthetic tag `refs/tags/v1.2.3`.
Installed Rails identity used the source SHA and `commit:<source SHA>`;
the installed asset matched the checksum above. Temporary fixtures were removed.
The legacy Ruby/Rails appraisal matrix was not rerun for this scoped package task.
An initial payload invocation without `-Ilib` failed to locate the library; the
corrected command listed above passed. RubyGems emitted its existing empty-license
warning; licensing was left unchanged.
